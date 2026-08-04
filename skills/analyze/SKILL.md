---
name: analyze
description: Work out whether a machine can run a local model stack, and which one. Probes the hardware — locally or over SSH — and reports the GPU, the memory arithmetic, and the models that fit. Use when the user asks what their GPU can run, wants to check a box before installing lmstack, or asks for hardware analysis of a potential inference host. Read-only: installs nothing.
---

# analyze

Answer one question: **can this machine put its GPU to work, and with what?**

Read-only. You install nothing, you change nothing on the target, and you write
exactly one file on the control host. If the answer is no, say no — a wrong yes
costs the user an hour of bring-up before they find out.

## Ground rules

1. **Never run a sudo command yourself.** Nothing here needs one; if you find
   yourself reaching for it, you have gone past the boundary of this skill.
2. **Do not guess hardware. Use the right tool per vendor, and never assume.**
   Every number comes from the probe. Never substitute a specification you
   looked up, a number the user remembers, or anything the machine's model
   name "should" imply.

   The right tool per vendor — the probe already uses these; the rule is here
   so a reader who suspects the probe knows what to check:

   | Case | Authoritative source |
   |---|---|
   | NVIDIA discrete | `nvidia-smi --query-gpu=memory.total` (MiB) |
   | NVIDIA unified (Grace Blackwell, Grace Hopper, Jetson) | CUDA `cuMemGetInfo` via `libcuda.so` — nvidia-smi returns `N/A` on these parts and is not usable |
   | AMD dGPU | `/sys/class/drm/card*/device/mem_info_vram_total` (bytes) |
   | AMD APU | `/sys/class/drm/card*/device/mem_info_gtt_total` (bytes) — `vram_total` is a small carve-out and is the wrong number |

   `null` is a finding, and its meaning depends on whether a GPU was detected:
   - **`vendor: none`** — hardware absent or invisible to the kernel. Report and
     stop.
   - **Vendor set, `vram_gib: null`** — the probe found the GPU but the tool it
     asked did not answer. That is a probe bug, not a hardware verdict. Report
     which tool failed and stop; do not invent a number, and do not fall back
     to reasoning from the GPU model name.
3. **Do not second-guess the arithmetic.** `lmstack-classify` is a pure function
   of the probe and the model catalog. If its verdict looks wrong, the fix is a
   code change with a test, not an override in conversation.
4. **Stop on an unsupported host.** Explain why and what would change the
   verdict. Never fall back to CPU inference: it is slow enough to look broken,
   and the user will conclude the project is broken rather than their hardware.

## Step 1 — Target

`$ARGUMENTS` may already name one. Otherwise ask, and accept either:

- `localhost` / "this machine"
- an SSH target — `user@host`, or a `~/.ssh/config` alias

Ask nothing else. Do not ask how much VRAM they have; that is what the probe is
for, and users misremember it.

## Step 2 — Probe

`lmstack-probe` is on your PATH. It is read-only, needs no privileges, and works
on a host with no docker, no jq and no python.

```bash
# local
lmstack-probe > /tmp/lmstack-probe.json

# remote — the script is self-contained, so piping it over stdin means nothing
# has to be installed on the target first and nothing is left behind
ssh "$TARGET" 'bash -s' < "$(command -v lmstack-probe)" > /tmp/lmstack-probe.json
```

If SSH fails, **that is the finding.** Report the exact error. Do not retry with
different options and do not suggest disabling host key checking.

Read `${CLAUDE_PLUGIN_ROOT}/references/hardware-probe.md` if a field is missing
or looks implausible.

## Step 3 — Classify

```bash
lmstack-classify --probe /tmp/lmstack-probe.json
```

Present all four of these to the user:

- The host role it chose — `h1-nvidia` or `h2-amd` — and why.
- **The arithmetic, in full.** The `arithmetic` array exists so the user can
  check the sizing rather than trust it. Reproduce every line.
- Every `warnings` entry.
- The recommended model list.

The AMD APU case is the one worth calling out explicitly when it occurs: the
card reports a token VRAM carve-out and maps the rest through GTT, so the honest
budget is the GTT figure. The classifier already accounts for this, but a user
who knows their machine "has 512 MB of VRAM" will not believe the verdict unless
you show them that line.

If `supported` is `false`, relay `reason` and `remedy`, log the failure, and
**stop**. Do not offer a workaround.

## Step 4 — Record and hand off

Write the probe where install will find it. This is the only file this skill
creates:

```bash
mkdir -p "$HOME/.lmstack/<role>"
cp /tmp/lmstack-probe.json "$HOME/.lmstack/<role>/probe.json"
```

Then log it:

```bash
lmstack-log --host "<role>" --event probe --action host.classified --status ok \
  --hw '{"gpu":"...","vram_gib":N}' --models "slug-a,slug-b"
```

`--hw` takes the GPU model and memory only. The probe also holds the kernel
version and the OS build, which are fine to log. It does not contain a serial
number, and you should not add one.

End by telling the user what happens next — `/lmstack:install` — and what it
will do. Do not start installing. A user who asked "can this run?" has not yet
agreed to "install it".

## Logging

Every step writes one line through `lmstack-log`, which redacts before it
writes. `${CLAUDE_PLUGIN_ROOT}/references/stacklog-schema.md` has the field list.

- `--host` is the **inventory alias**, never an IP or hostname. The writer
  rejects anything with a dot in it.
- Log failures too. A log containing only successes cannot answer the question
  it exists for.

## References

| File | Read it when |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}/references/hardware-probe.md` | Interpreting probe output, or it reported something odd |
| `${CLAUDE_PLUGIN_ROOT}/references/model-catalog.md` | The user wants a model that is not in the catalog |
| `${CLAUDE_PLUGIN_ROOT}/references/stacklog-schema.md` | Writing a log line |
