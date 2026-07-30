# h3-template

A host skeleton to copy. It is not a host: `make validate` and the render tests
skip any directory under `hosts/` whose name ends in `-template`, so this one
being unfinished cannot fail `make test`.

It is shaped for **vLLM on an NVIDIA GPU**, because that is the engine you are
most likely to be adding a second box of. If your new host is AMD, copy
`hosts/h2-amd` instead — it is the same skeleton with the llama.cpp engine
block, and the checklist below applies unchanged.

## Instantiate

```bash
cp -r hosts/h3-template hosts/h3-nvidia
grep -rn CHANGE_ME_ hosts/h3-nvidia
```

Every placeholder is one of three:

| Token | Where | What to put |
|---|---|---|
| `CHANGE_ME_HOST` | `ansible/*.yml`, `vllm/env/stack.env.example` | The inventory alias, e.g. `h3-nvidia`. Must match the name you use in `inventory/hosts.ini` and the directory name. |
| `CHANGE_ME_VRAM_BUDGET_GIB` | `ansible/vars.yml` | An integer. What the card actually has. |
| `active_models: []` | `ansible/vars.yml` | At least one model slug, with a matching file in `vllm/models/`. |

Then add the host to your inventory:

```ini
[h3_nvidia]
h3-nvidia ansible_host=192.168.1.101
```

and to the `gpu_hosts:children` group below it.

Nothing else needs editing. The playbooks resolve everything from `vars.yml`.

## Add a model

The one decision the template cannot make for you, which is why
`active_models` ships empty. Start from a model that is already working:

```bash
cp hosts/h1-nvidia/vllm/models/qwen2.5-coder-7b.yml hosts/h3-nvidia/vllm/models/
```

Then list its slug in `active_models` and run `make validate`. The schema, the
VRAM budget, and the alias collision check all run before Ansible connects to
anything. See docs: models/adding-a-model.

## Verify before you deploy

```bash
make validate            # your host is now a real host, and is checked
make check HOST=h3-nvidia   # dry-run the whole thing, --check --diff
```

`make validate` will complain about a leftover `CHANGE_ME_VRAM_BUDGET_GIB`
(it is a string, not an integer) and about an empty `active_models`. Those two
errors are the template telling you it is not finished.

## Running it

```bash
make deps                       # once: ansible collections, on your machine
make bootstrap HOST=h3-nvidia   # once: docker, nvidia toolkit, firewall
make up        HOST=h3-nvidia   # render, pull, start, health-gate
make verify    HOST=h3-nvidia   # endpoint conformance
```

`make site HOST=h3-nvidia` runs all three. Everything is re-runnable.

## Alias parity

If you want your editor configuration to work against this host without
changing which model it asks for, expose the same alias the other hosts do —
`qwen2.5-coder-7b` — and add the host to `tests/parity.yml` so the validator
enforces it. That is the whole point of the generic aliases: which box answered
should not be something your config knows about.

## Assumptions

- The GPU **driver** is already installed. Bootstrap checks `nvidia-smi` and
  stops if it is missing rather than guessing at your kernel.
- The install root is `~/.lmstack` on the target. Nothing lands in `/etc` or
  `/var/lib`, and there is no systemd unit — containers come back after a reboot
  because of `restart: unless-stopped`.
- Root is used for exactly two things: installing packages during bootstrap, and
  the one UFW rule. `10-stack.yml` and `20-verify.yml` need none.

## Keeping this file honest

`tests/template_test.sh` copies this directory, fills the placeholders, and runs
the validator against the result. It also asserts that the `.j2` files here are
identical to `hosts/h1-nvidia`'s apart from comments — so if someone improves
the real host's compose template, this one has to follow or the suite goes red.
A template nobody exercises is worse than no template.
