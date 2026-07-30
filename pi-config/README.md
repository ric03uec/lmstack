# Control-host configuration

This is the machine you write code on. It does not need a GPU. It needs to know
where your lmstack hosts are and what they serve.

```bash
./sync.sh install
$EDITOR ~/.pi/agent/extensions/.env    # host URL + LiteLLM key
pi --list-models                       # lmstack-h1 / lmstack-h2 appear here
```

`sync.sh` merges into your existing pi configuration rather than replacing it.
If you already use pi, your packages list keeps everything in it and gains three
entries. `./sync.sh dump` captures changes back, taking only the entries this
repo owns.

## What gets installed

| File | Purpose |
|---|---|
| `extensions/lmstack-h1.ts` | Registers the `lmstack-h1` provider (vLLM host) |
| `extensions/lmstack-h2.ts` | Registers the `lmstack-h2` provider (llama.cpp host) |
| `extensions/.env` | Your host URLs and LiteLLM keys. Created 0600, never overwritten, never captured by `dump` |
| `settings.json` | The three package entries, merged into yours |
| `npm/package.json` | One npm extension, merged into yours |
| `pi-statusline.json` | Status line layout |
| `bin/lmstack-ask` | One-shot bridge for Claude Code and opencode |

The status line shows context and token counts and omits cost. A 16k window is
the binding constraint when you are serving your own model, and the cost is
zero — displaying `$0.00` on every turn is just noise.

## Both hosts serve the same alias

`qwen2.5-coder-7b` is exposed by `h1-nvidia` and `h2-amd` alike, so moving
between them is a `--provider` change and nothing else. `tests/parity.yml`
enforces it, and `make validate` (T0.10) fails if an extension here advertises
a model id no host actually serves.

That last check is the reason to edit these files rather than hand-editing
`~/.pi/agent/`: adding a model to a host's `active_models` and forgetting to
advertise it — or advertising one you never deployed — is caught offline
instead of at the first request.

## Using it from Claude Code or opencode

Neither can point its own model at an OpenAI-compatible endpoint, but both can
run a command. `bin/lmstack-ask` is that command.

```bash
cp bin/lmstack-ask ~/bin/          # or add this directory to PATH

lmstack-ask "what does this do?" < internal/parse.go
lmstack-ask -P lmstack-h1 "write a table test for Parse"
```

It picks a host by asking which LiteLLM answers — loopback first — and prints
the choice to stderr. Pin one with `-P`, or export `LMSTACK_PROVIDER`.

Tools are off by default. A 7B model handed shell and edit tools inside another
agent's session is a liability; `-t` opts in when you want it.

opencode can also talk to LiteLLM directly, since it accepts OpenAI-compatible
providers — see `bridges/opencode.json` for the fragment to merge into
`~/.config/opencode/opencode.json`.

## Adding a model

1. Add the model YAML under `hosts/<host>/<engine>/models/`.
2. Add its slug to that host's `active_models`.
3. Add an entry to the matching extension here, with `id` set to the LiteLLM
   alias and `contextWindow` set to what the model YAML declares.
4. `make validate` — step 3 is not optional, and this is what says so.
