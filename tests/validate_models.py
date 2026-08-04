#!/usr/bin/env python3
"""Static validation of host and model configuration (test tier T0).

Two host playbooks are intentionally duplicated rather than sharing Ansible
roles. This validator is what stops them drifting: it enforces one schema, one
set of invariants, and one catalog contract across every host in the repo.

Runs without a host, without a GPU, and without Ansible. Exit 0 = clean.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent

# Fields every model declares, whatever engine serves it.
COMMON_FIELDS = {
    "slug": str,
    "engine": str,
    "image": str,
    "port": int,
    "vram_estimate_gib": (int, float),
    "tier": str,
    "mandatory": bool,
}

ENGINE_FIELDS = {
    "vllm": {
        "hf_model": str,
        "gpu_memory_utilization": (int, float),
        "max_model_len": int,
        "max_num_seqs": int,
        "dtype": str,
    },
    "llamacpp": {
        "hf_repo": str,
        "hf_file": str,
        "context": int,
        "n_gpu_layers": int,
        "parallel_slots": int,
    },
}

VALID_TIERS = {"8g", "24g", "48g"}
TIER_CEILING_GIB = {"8g": 8, "24g": 24, "48g": 48}


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.checks = 0

    def check(self, condition: bool, message: str) -> bool:
        self.checks += 1
        if not condition:
            self.errors.append(message)
        return condition

    def warn(self, condition: bool, message: str) -> None:
        self.checks += 1
        if not condition:
            self.warnings.append(message)


def load_yaml(path: Path) -> dict:
    with path.open() as fh:
        data = yaml.safe_load(fh)
    if not isinstance(data, dict):
        raise ValueError(f"{path} does not contain a YAML mapping")
    return data


def is_template(host_dir: Path) -> bool:
    """A skeleton to copy, not a host. Placeholders would fail every check."""
    return host_dir.name.endswith("-template")


def discover_hosts(root: Path) -> list[Path]:
    hosts_dir = root / "hosts"
    if not hosts_dir.is_dir():
        return []
    return sorted(
        p
        for p in hosts_dir.iterdir()
        if (p / "ansible" / "vars.yml").is_file() and not is_template(p)
    )


def validate_model(path: Path, rep: Report) -> dict | None:
    """T0.3, T0.4, T0.7 — schema, filename agreement, template existence."""
    try:
        model = load_yaml(path)
    except (yaml.YAMLError, ValueError) as exc:
        rep.check(False, f"{path}: unparseable ({exc})")
        return None

    ident = f"{path.parent.parent.parent.name}/{path.name}"

    for field, expected in COMMON_FIELDS.items():
        if not rep.check(field in model, f"{ident}: missing required field '{field}'"):
            continue
        rep.check(
            isinstance(model[field], expected) and not isinstance(model[field], bool)
            if expected is not bool and not isinstance(expected, tuple)
            else isinstance(model[field], expected),
            f"{ident}: field '{field}' should be {expected}, got {type(model[field]).__name__}",
        )

    engine = model.get("engine")
    rep.check(
        engine in ENGINE_FIELDS,
        f"{ident}: engine '{engine}' is not one of {sorted(ENGINE_FIELDS)}",
    )
    if engine in ENGINE_FIELDS:
        for field, expected in ENGINE_FIELDS[engine].items():
            rep.check(
                field in model,
                f"{ident}: engine '{engine}' requires field '{field}'",
            )

    # T0.4 — slug must equal the filename stem, or a rename silently orphans it.
    rep.check(
        model.get("slug") == path.stem,
        f"{ident}: slug '{model.get('slug')}' does not match filename stem '{path.stem}'",
    )

    rep.check(
        model.get("tier") in VALID_TIERS,
        f"{ident}: tier '{model.get('tier')}' is not one of {sorted(VALID_TIERS)}",
    )

    # A model must fit inside the tier it claims, or tier-based recommendation lies.
    tier, vram = model.get("tier"), model.get("vram_estimate_gib")
    if tier in TIER_CEILING_GIB and isinstance(vram, (int, float)):
        rep.check(
            vram <= TIER_CEILING_GIB[tier],
            f"{ident}: vram_estimate_gib {vram} exceeds the {tier} tier ceiling "
            f"of {TIER_CEILING_GIB[tier]} GiB",
        )

    # T0.7 — a dangling chat template reference fails at container start, hours later.
    tmpl = model.get("chat_template_file")
    if tmpl:
        tmpl_path = path.parent.parent / "chat-templates" / tmpl
        rep.check(tmpl_path.is_file(), f"{ident}: chat_template_file '{tmpl}' not found at {tmpl_path}")

    rep.warn(
        bool(model.get("notes")),
        f"{ident}: no 'notes' — record why this quant/context was chosen",
    )

    return model


def aliases_of(model: dict) -> list[str]:
    """Every name LiteLLM will expose for this model."""
    vms = model.get("virtual_models") or []
    if vms:
        return [vm["name"] for vm in vms if isinstance(vm, dict) and "name" in vm]
    return [model["slug"]]


def validate_host(host_dir: Path, rep: Report, state: Path | None = None) -> dict:
    alias = host_dir.name
    vars_path = host_dir / "ansible" / "vars.yml"
    hostvars = load_yaml(vars_path)

    # Mirror Ansible's precedence: `make up` passes ~/.lmstack/<alias>/vars.yml
    # with -e, which wins over the tracked defaults. Validating the tracked file
    # alone would pass while the config actually being deployed is broken.
    if state:
        override_path = state / alias / "vars.yml"
        if override_path.is_file():
            override = load_yaml(override_path)
            if isinstance(override, dict):
                hostvars = {**hostvars, **override}

    engine = hostvars.get("engine")
    rep.check(
        engine in ENGINE_FIELDS,
        f"{alias}/vars.yml: engine '{engine}' is not one of {sorted(ENGINE_FIELDS)}",
    )

    models_dir = host_dir / str(engine) / "models"
    if not models_dir.is_dir():
        rep.check(False, f"{alias}: expected models directory at {models_dir}")
        return {"alias": alias, "aliases": set(), "active": []}

    models = {}
    for path in sorted(models_dir.glob("*.yml")):
        model = validate_model(path, rep)
        if model:
            models[path.stem] = model
            rep.check(
                model.get("engine") == engine,
                f"{alias}/{path.name}: engine '{model.get('engine')}' does not match "
                f"the host engine '{engine}'",
            )

    active = hostvars.get("active_models") or []
    rep.check(bool(active), f"{alias}/vars.yml: active_models is empty")

    # T0.9 — a typo here is the single most common way to break a deploy.
    for slug in active:
        rep.check(
            slug in models,
            f"{alias}/vars.yml: active model '{slug}' has no config at {models_dir}/{slug}.yml",
        )

    active_models = [models[s] for s in active if s in models]

    # T0.5 — two engines on one port means one container silently never starts.
    ports: dict[int, str] = {}
    for model in active_models:
        port = model.get("port")
        if port in ports:
            rep.check(False, f"{alias}: port {port} claimed by both '{ports[port]}' and '{model['slug']}'")
        elif isinstance(port, int):
            ports[port] = model["slug"]

    litellm_port = hostvars.get("litellm_port", 4000)
    rep.check(
        litellm_port not in ports,
        f"{alias}: engine port {litellm_port} collides with the LiteLLM gateway port",
    )

    # T0.6 / T0.13 — refuse to ship a default set that cannot fit.
    budget = hostvars.get("vram_budget_gib")
    if budget is not None and active_models:
        total = sum(m.get("vram_estimate_gib", 0) for m in active_models)
        rep.check(
            total <= budget,
            f"{alias}: active set needs ~{total} GiB but vram_budget_gib is {budget} "
            f"({', '.join(f'{m['slug']}={m.get('vram_estimate_gib')}' for m in active_models)})",
        )

    # T0.8 — LiteLLM silently shadows duplicate model_name entries.
    seen: dict[str, str] = {}
    host_aliases: set[str] = set()
    for model in active_models:
        for name in aliases_of(model):
            if name in seen:
                rep.check(
                    False,
                    f"{alias}: LiteLLM alias '{name}' exposed by both '{seen[name]}' and '{model['slug']}'",
                )
            seen[name] = model["slug"]
            host_aliases.add(name)

    return {"alias": alias, "aliases": host_aliases, "active": active}


def validate_parity(root: Path, hosts: list[dict], rep: Report) -> None:
    """T0.11 — control-host config must not care which engine served the model."""
    parity_path = root / "tests" / "parity.yml"
    if not parity_path.is_file():
        return
    spec = load_yaml(parity_path)
    required = spec.get("required_common_aliases") or []
    want_hosts = spec.get("hosts") or []
    by_alias = {h["alias"]: h for h in hosts}

    for host_alias in want_hosts:
        host = by_alias.get(host_alias)
        if not rep.check(host is not None, f"parity.yml lists unknown host '{host_alias}'"):
            continue
        for name in required:
            rep.check(
                name in host["aliases"],
                f"parity: host '{host_alias}' does not expose the required common "
                f"alias '{name}' (exposes: {sorted(host['aliases']) or 'nothing'})",
            )


def validate_pi_extensions(root: Path, hosts: list[dict], rep: Report) -> None:
    """T0.10 — pi advertises models the host must actually serve."""
    ext_dir = root / "pi-config" / "extensions"
    if not ext_dir.is_dir():
        return
    all_aliases = {a for h in hosts for a in h["aliases"]}
    if not all_aliases:
        return

    # Matches both `id: "x"` on its own line and inline `{ id: "x", … }`.
    # The lookbehind stops it firing on `model_id:` or `uuid:`.
    id_pattern = re.compile(r'(?<![\w$])id:\s*"([^"]+)"')

    for ext in sorted(ext_dir.glob("*.ts")):
        for model_id in id_pattern.findall(ext.read_text()):
            rep.check(
                model_id in all_aliases,
                f"pi-config/{ext.name}: advertises model id '{model_id}', which no "
                f"host exposes as a LiteLLM alias",
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=REPO_ROOT, help="repository root to validate")
    parser.add_argument(
        "--state",
        type=Path,
        default=Path.home() / ".lmstack",
        help="per-role state directory whose <alias>/vars.yml overrides the tracked "
        "defaults, matching what `make up` passes to Ansible with -e",
    )
    parser.add_argument(
        "--no-state",
        action="store_true",
        help="validate the tracked defaults only, ignoring any local overrides",
    )
    parser.add_argument("--quiet", action="store_true", help="only print on failure")
    args = parser.parse_args()
    state = None if args.no_state else args.state

    rep = Report()
    host_dirs = discover_hosts(args.root)

    if not host_dirs:
        print(f"validate_models: no hosts found under {args.root}/hosts — nothing to validate")
        return 0

    hosts = [validate_host(d, rep, state) for d in host_dirs]
    validate_parity(args.root, hosts, rep)
    validate_pi_extensions(args.root, hosts, rep)

    for warning in rep.warnings:
        print(f"  WARN  {warning}")
    for error in rep.errors:
        print(f"  FAIL  {error}")

    if rep.errors:
        print(f"\n{len(rep.errors)} error(s), {len(rep.warnings)} warning(s) across {rep.checks} checks")
        return 1

    if not args.quiet:
        hosts_desc = ", ".join(f"{h['alias']}({len(h['active'])})" for h in hosts)
        print(f"  PASS  {rep.checks} checks across {len(hosts)} host(s): {hosts_desc}")
        if rep.warnings:
            print(f"        {len(rep.warnings)} warning(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
