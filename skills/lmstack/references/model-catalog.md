# Adding a model to the catalog

Models are data. One YAML file at `hosts/<role>/<engine>/models/<slug>.yml`
drives the compose file, the LiteLLM routing table, and the VRAM budget check.
There is no code to change.

The authoritative field list is in the repo-root `AGENTS.md`. This file is about
the judgement calls the schema cannot make for you.

## Before adding one

Check the catalog first — `make validate` prints what is there. A user asking
for "a bigger coding model" on a 24 GiB card usually wants a catalog entry that
does not exist yet, and adding it is a five-line file.

## Sizing

`vram_estimate_gib` is a promise the budget check enforces. Get it wrong and the
stack passes validation and then OOMs.

**vLLM.** `gpu_memory_utilization` is a fraction of *total* card memory and the
weights come out of that same allowance. It is not headroom on top of the model.
Weights plus KV cache plus activation scratch must fit under
`gpu_memory_utilization × total`. Raising `max_model_len` on a small card causes
preemption and thrashing, not an error message.

**llama.cpp.** Weights are the GGUF file size on disk, near enough. KV cache is
roughly `context × layers × 2 × kv_heads × head_dim × 2 bytes`, which for a 7B at
16k lands around 1.3 GiB. Add the two, round up.

## Quantization and tool calling interact

This is the failure that costs the most time to diagnose, because nothing logs
an error.

At Q4, a model that handles tool calls correctly at higher precision starts
improvising wrappers — `<xml>` tags, ```json fences — that the chat parser does
not recognise. The call lands in `message.content` as prose. Every agent loop
breaks. The endpoint looks healthy and `/v1/models` lists the alias.

`20-verify.yml` T3.4 tests exactly this. If it fails:

1. Confirm the engine has the right parser. vLLM needs `--tool-call-parser`
   matching the chat template (`hermes` for Qwen2.5). llama.cpp needs `--jinja`
   so it uses the GGUF's embedded template.
2. Then raise the quantization — Q4_K_M to Q6_K restored adherence on the
   deployment this repo was ported from.
3. Only then look at the chat template.

Do not put a model behind an agent loop without running T3.4 against it.

## Aliases and parity

`virtual_models` is a list of names LiteLLM will serve, all backed by the same
loaded weights. Two uses:

- **Parity.** `qwen2.5-coder-7b` means the same thing on the NVIDIA host and the
  AMD host, so the editor configuration does not change when the user switches.
  `tests/parity.yml` enforces this for models marked `mandatory: true`.
- **Aliasing an upstream name.** Serving both `qwen2.5-coder-7b` and
  `Qwen2.5-Coder-7B-Instruct` means a tool that hardcodes the HuggingFace name
  works without configuration.

Alias collisions are silent in LiteLLM — it keeps one and drops the other. The
validator (T0.8) and T3.2 both check for this.

## Tiers

`tier` is `8g`, `24g` or `48g`, and the model must fit inside its tier's ceiling.
It is what `classify.py` uses to avoid putting a 24 GiB model on an 8 GiB card.
A model whose `vram_estimate_gib` exceeds its tier ceiling fails validation.

`mandatory: true` means every host must serve it. Use it only for the parity
alias; a second mandatory model makes the 8 GiB floor impossible.

## After adding

```bash
make validate                 # schema, budget, ports, aliases, parity
make test                     # plus a full offline render against the goldens
BLESS=1 tests/render_test.sh  # if the render legitimately changed
```

Adding a model to the catalog does not activate it. `active_models` in the
host's `vars.yml` decides what runs.
