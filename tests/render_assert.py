#!/usr/bin/env python3
"""T1.3-T1.5 assertions against a rendered host directory.

Reads tests/.render/<host>/ and the host's model YAML, then checks the
exposure invariant and the LiteLLM routing table. Prints one line per check
and exits non-zero on any failure.

    python3 tests/render_assert.py h1-nvidia
"""

import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent

GREEN, RED, RESET = "\033[32m", "\033[31m", "\033[0m"

failures: list[str] = []


def ok(msg: str) -> None:
    print(f"  {GREEN}PASS{RESET} {msg}")


def bad(msg: str) -> None:
    print(f"  {RED}FAIL{RESET} {msg}")
    failures.append(msg)


def load(path: Path):
    with path.open() as fh:
        return yaml.safe_load(fh)


def published_ports(service: dict) -> list[str]:
    """Compose accepts short strings and long-form mappings; normalise both."""
    out = []
    for entry in service.get("ports", []) or []:
        if isinstance(entry, dict):
            host_ip = entry.get("host_ip", "")
            published = entry.get("published", "")
            out.append(f"{host_ip}:{published}" if host_ip else str(published))
        else:
            out.append(str(entry))
    return out


def check_exposure(compose: dict) -> None:
    """T1.3 — engines bind loopback. T1.4 — postgres publishes nothing."""
    for name, service in (compose.get("services") or {}).items():
        ports = published_ports(service)

        if name == "postgres":
            if ports:
                bad(f"T1.4 postgres publishes ports: {ports}")
            else:
                ok("T1.4 postgres publishes no ports")
            continue

        if name == "litellm":
            # The gateway is the one service allowed off-loopback.
            ok(f"T1.3 litellm gateway publishes {ports or ['(none)']}")
            continue

        if not ports:
            bad(f"T1.3 engine '{name}' publishes no port at all")
        for spec in ports:
            if spec.startswith("127.0.0.1:"):
                ok(f"T1.3 engine '{name}' bound to {spec}")
            else:
                bad(f"T1.3 engine '{name}' is reachable off-localhost: {spec}")


def check_litellm(config: dict, expected_aliases: set[str]) -> None:
    """T1.5 — the routing table is valid YAML with exactly the aliases we declared.

    Guards the Jinja whitespace regression the source repo hit, where list items
    collapsed onto one line and the alias count silently dropped.
    """
    entries = config.get("model_list") or []
    rendered = [e.get("model_name") for e in entries]

    if len(rendered) != len(set(rendered)):
        bad(f"T1.5 duplicate aliases in rendered config: {rendered}")
    elif set(rendered) != expected_aliases:
        missing = sorted(expected_aliases - set(rendered))
        extra = sorted(set(rendered) - expected_aliases)
        bad(f"T1.5 alias mismatch (missing={missing} extra={extra})")
    else:
        ok(f"T1.5 {len(rendered)} alias(es) rendered, matching the model YAML")


def expected_aliases_for(host: str) -> set[str]:
    host_dir = REPO / "hosts" / host
    hostvars = load(host_dir / "ansible" / "vars.yml")
    engine = hostvars["engine"]

    aliases = set()
    for slug in hostvars["active_models"]:
        model = load(host_dir / engine / "models" / f"{slug}.yml")
        aliases.add(model["slug"])
        for vm in model.get("virtual_models") or []:
            aliases.add(vm["name"])
    return aliases


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2

    host = sys.argv[1]
    render_dir = REPO / "tests" / ".render" / host
    if not render_dir.is_dir():
        print(f"no rendered output at {render_dir}")
        return 2

    compose_path = render_dir / "docker-compose.yml"
    if compose_path.exists():
        check_exposure(load(compose_path))
    else:
        bad(f"T1.3/T1.4 no rendered compose file at {compose_path}")

    litellm_path = render_dir / "litellm" / "config.yaml"
    if litellm_path.exists():
        check_litellm(load(litellm_path), expected_aliases_for(host))
    else:
        bad(f"T1.5 no rendered LiteLLM config at {litellm_path}")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
