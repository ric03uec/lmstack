#!/usr/bin/env python3
"""Turn probe-host.sh output into a host role and a model recommendation.

    bash probe-host.sh | python3 classify.py
    python3 classify.py --probe saved-probe.json

Reads the probe on stdin, reads the model catalog out of the repo, and emits a
JSON decision on stdout. Pure function of those two inputs: no network, no
host access, no writes. That is what makes T6.1 and T6.2 possible — the same
fixture always produces the same recommendation.

The decision is a proposal. The skill shows it to the user, who can override
every part of it before anything is written.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import yaml

# Held back from the model budget for the display server, the compositor, and
# the runtime's own context allocations. Without it a card that reports exactly
# 8 GiB gets handed 8 GiB of weights and OOMs on the first long prompt.
RESERVE_GIB = 1

TIER_CEILING_GIB = {"8g": 8, "24g": 24, "48g": 48}

ROLES = {
    "nvidia": {"host": "h1-nvidia", "engine": "vllm"},
    "amd": {"host": "h2-amd", "engine": "llamacpp"},
}


class CatalogError(Exception):
    pass


def find_repo(explicit: Path | None) -> Path:
    """Locate the repository holding the model catalog.

    The installed copy of this skill lives under the agent's skill directory, so
    walking up from __file__ finds ~/.claude rather than the repo. The install
    binds the real path into SKILL.md and the skill passes it in; the walk-up is
    only the convenience case of running from a clone.
    """
    for candidate in (explicit, os.environ.get("LMSTACK_REPO"), Path(__file__).resolve().parents[3]):
        if not candidate:
            continue
        root = Path(candidate).expanduser().resolve()
        if (root / "hosts").is_dir():
            return root
    raise CatalogError(
        "cannot find the lmstack repository. Pass --repo /path/to/lmstack, or set "
        "LMSTACK_REPO. The installed skill does not sit inside the repo, so the "
        "catalog has to be located explicitly."
    )


def load_catalog(repo: Path, host: str, engine: str) -> list[dict]:
    model_dir = repo / "hosts" / host / engine / "models"
    if not model_dir.is_dir():
        raise CatalogError(f"no model catalog at {model_dir}")
    models = []
    for path in sorted(model_dir.glob("*.yml")):
        with path.open() as fh:
            models.append(yaml.safe_load(fh))
    if not models:
        raise CatalogError(f"{model_dir} contains no model definitions")
    return models


def usable_gib(gpu: dict) -> tuple[int, str]:
    """How much GPU memory a model may actually occupy, and why we think so."""
    vram = gpu.get("vram_gib") or 0
    gtt = gpu.get("gtt_gib") or 0

    # An APU reports a token VRAM carve-out (often 512 MiB or 2 GiB) and maps
    # the rest through GTT. Taking the larger of the two is the difference
    # between "this machine cannot run a 7B" and the truth.
    if gtt > vram:
        return gtt, f"GTT budget {gtt} GiB (unified memory; the {vram} GiB VRAM figure is a carve-out)"
    return vram, f"{vram} GiB of dedicated VRAM"


def pick_tier(catalog: list[dict], budget: int) -> str:
    """The largest tier the budget supports that the catalog actually stocks.

    Both halves matter. Choosing on budget alone hands a 48 GiB machine a tier
    with no entries in it; choosing on the catalog alone puts a 24 GiB model on
    an 8 GiB card.
    """
    stocked = {m["tier"] for m in catalog}
    affordable = [t for t in ("48g", "24g", "8g") if t in stocked and budget >= TIER_CEILING_GIB[t]]
    if affordable:
        return affordable[0]
    # Below every tier ceiling. Fall back to the smallest tier on offer and let
    # the per-model budget check decide what actually fits.
    return min(stocked, key=lambda t: TIER_CEILING_GIB[t])


def recommend(catalog: list[dict], budget: int, tier: str) -> tuple[list[dict], list[str]]:
    """Mandatory model first, then whatever else still fits. Greedy, largest first."""
    steps = []
    eligible = [m for m in catalog if m["tier"] == tier]
    chosen: list[dict] = []
    remaining = budget

    mandatory = [m for m in eligible if m.get("mandatory")]
    for model in mandatory:
        if model["vram_estimate_gib"] <= remaining:
            chosen.append(model)
            remaining -= model["vram_estimate_gib"]
            steps.append(f"{model['slug']} needs {model['vram_estimate_gib']} GiB -> fits, {remaining} GiB left")
        else:
            steps.append(
                f"{model['slug']} needs {model['vram_estimate_gib']} GiB but only "
                f"{remaining} GiB is available -> skipped"
            )

    optional = sorted(
        (m for m in eligible if not m.get("mandatory")),
        key=lambda m: m["vram_estimate_gib"],
        reverse=True,
    )
    for model in optional:
        if model["vram_estimate_gib"] <= remaining:
            chosen.append(model)
            remaining -= model["vram_estimate_gib"]
            steps.append(f"{model['slug']} needs {model['vram_estimate_gib']} GiB -> fits, {remaining} GiB left")

    # A machine too small for the mandatory model still gets a usable stack if
    # any catalog entry fits at all.
    if not chosen:
        steps.append("nothing in the tier fits the budget")

    return chosen, steps


def unsupported(reason: str, remedy: str) -> dict:
    return {
        "supported": False,
        "host_role": None,
        "engine": None,
        "reason": reason,
        "remedy": remedy,
    }


def classify(probe: dict, repo: Path) -> dict:
    gpu = probe.get("gpu") or {}
    vendor = gpu.get("vendor", "none")

    if vendor == "none":
        return unsupported(
            "No NVIDIA GPU and no amdgpu DRM render node were found.",
            "lmstack needs a GPU. On NVIDIA install the driver so nvidia-smi answers; "
            "on AMD confirm the amdgpu module is loaded and /dev/dri/renderD128 exists.",
        )

    if vendor not in ROLES:
        return unsupported(
            f"GPU vendor '{vendor}' has no host role in this repo.",
            "Copy hosts/h3-template/ and add an engine for it.",
        )

    role = ROLES[vendor]

    if vendor == "nvidia" and not gpu.get("driver"):
        return unsupported(
            "nvidia-smi did not report a driver version.",
            "Install the NVIDIA driver first. The bootstrap playbook adds Docker and the "
            "container toolkit on top of a working driver; it will not install the driver.",
        )

    if vendor == "amd" and not probe.get("dri_nodes"):
        return unsupported(
            "An amdgpu device was detected but no /dev/dri/renderD* node exists.",
            "Containers reach the GPU through the render node. Check that the amdgpu "
            "module loaded cleanly: dmesg | grep amdgpu",
        )

    total, memory_reason = usable_gib(gpu)
    budget = max(total - RESERVE_GIB, 0)
    catalog = load_catalog(repo, role["host"], role["engine"])
    tier = pick_tier(catalog, budget)
    chosen, steps = recommend(catalog, budget, tier)

    arithmetic = [
        memory_reason,
        f"reserve {RESERVE_GIB} GiB for the display server and runtime context",
        f"model budget: {budget} GiB -> tier {tier}",
        *steps,
        f"total: {sum(m['vram_estimate_gib'] for m in chosen)} of {budget} GiB",
    ]

    warnings = []
    if not probe.get("docker", {}).get("present"):
        warnings.append("Docker is not installed; bootstrap will install it.")
    elif not probe["docker"].get("usable"):
        warnings.append(
            "Docker is installed but not usable by this user. Bootstrap adds you to the "
            "docker group, which needs a fresh login before it takes effect."
        )
    if vendor == "nvidia" and "nvidia" not in (probe.get("docker", {}).get("runtimes") or []):
        warnings.append("The NVIDIA container runtime is not registered; bootstrap registers it.")
    if vendor == "amd" and not probe.get("vulkan", {}).get("present"):
        warnings.append("vulkan-tools is not installed; bootstrap installs it and verifies the device.")
    if probe.get("sudo") == "password":
        warnings.append("sudo needs a password, so bootstrap must be run with -K.")
    if not chosen:
        warnings.append(
            f"No catalog model fits a {budget} GiB budget. The smallest entry needs "
            f"{min(m['vram_estimate_gib'] for m in catalog)} GiB."
        )
    else:
        slugs = {m["slug"] for m in chosen}
        skipped = [m["slug"] for m in catalog if m.get("mandatory") and m["slug"] not in slugs]
        if skipped:
            warnings.append(
                f"{', '.join(skipped)} does not fit a {budget} GiB budget, so this host will "
                f"not serve the alias every other host serves. Anything pointed at it by "
                f"model name will need reconfiguring."
            )
        used = sum(m["vram_estimate_gib"] for m in chosen)
        if budget - used >= TIER_CEILING_GIB[tier]:
            warnings.append(
                f"This host has {budget - used} GiB spare after the recommendation. The "
                f"default catalog is sized for the 8 GiB floor; add a larger model YAML to "
                f"hosts/{role['host']}/{role['engine']}/models/ to use the rest."
            )

    return {
        "supported": bool(chosen),
        "host_role": role["host"],
        "engine": role["engine"],
        "reason": f"{gpu.get('model') or vendor.upper()} via {role['engine']}",
        "usable_gib": total,
        "budget_gib": budget,
        "tier": tier,
        "recommended": [m["slug"] for m in chosen],
        "arithmetic": arithmetic,
        "warnings": warnings,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", type=Path, help="read probe JSON from a file instead of stdin")
    parser.add_argument(
        "--repo",
        type=Path,
        help="path to the lmstack repository holding the model catalog "
        "(default: $LMSTACK_REPO, else inferred from this script's location)",
    )
    args = parser.parse_args()

    raw = args.probe.read_text() if args.probe else sys.stdin.read()
    try:
        probe = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"classify: probe input is not valid JSON: {exc}", file=sys.stderr)
        return 2

    try:
        repo = find_repo(args.repo)
        print(json.dumps(classify(probe, repo), indent=2))
    except CatalogError as exc:
        print(f"classify: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
