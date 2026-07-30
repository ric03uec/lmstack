# Bridges

Two ways to reach an lmstack host from an agent that is not pi.

## opencode — direct

opencode accepts OpenAI-compatible providers, and LiteLLM is one, so it can talk
to the gateway with no intermediary. Merge `opencode.json` into
`~/.config/opencode/opencode.json` — it is a fragment, not a whole file, and
overwriting yours would drop everything else you have configured.

```bash
jq -s '.[0] * {provider: ((.[0].provider // {}) + .[1].provider)}' \
  ~/.config/opencode/opencode.json pi-config/bridges/opencode.json \
  > /tmp/opencode.json && mv /tmp/opencode.json ~/.config/opencode/opencode.json
```

Then export the key opencode substitutes into `{env:LMSTACK_H2_KEY}`:

```bash
export LMSTACK_H2_KEY=$(grep ^LITELLM_MASTER_KEY ~/.lmstack/env/stack.env | cut -d= -f2)
```

Keep `limit.context` in step with the model YAML. Setting it higher does not
give you more context; it gives you requests the server truncates.

## Claude Code — via `lmstack-ask`

Claude Code drives Anthropic models and cannot be pointed at an OpenAI endpoint,
so the bridge is a command it runs rather than a provider it registers:

```bash
lmstack-ask "summarise the error handling here" < internal/parse.go
```

That is a real delegation — the local model does the work and Claude Code reads
the result — and it costs nothing. It is worth it for bulk, mechanical work over
large amounts of text. It is not worth it for anything where the 7B's answer
would need checking more carefully than doing the task directly.
