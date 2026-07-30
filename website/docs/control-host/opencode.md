---
sidebar_position: 3
title: opencode
---

# opencode

opencode accepts OpenAI-compatible providers, and LiteLLM is one, so it talks to
the gateway directly — no intermediary, and the local model is selectable like
any other.

## Merging the provider

`pi-config/bridges/opencode.json` is a fragment, not a whole config. Overwriting
yours would drop everything else you have set up.

```bash
jq -s '.[0] * {provider: ((.[0].provider // {}) + .[1].provider)}' \
  ~/.config/opencode/opencode.json pi-config/bridges/opencode.json \
  > /tmp/opencode.json && mv /tmp/opencode.json ~/.config/opencode/opencode.json
```

It registers two providers:

```json
{
  "provider": {
    "lmstack-h2": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "lmstack h2-amd (llama.cpp)",
      "options": {
        "baseURL": "http://127.0.0.1:4000/v1",
        "apiKey": "{env:LMSTACK_H2_KEY}"
      },
      "models": {
        "qwen2.5-coder-7b": {
          "name": "Qwen2.5 Coder 7B (lmstack)",
          "limit": { "context": 16384, "output": 4096 }
        }
      }
    }
  }
}
```

## The key

`{env:LMSTACK_H2_KEY}` is substituted from the environment, so the key stays out
of the config file:

```bash
export LMSTACK_H2_KEY=$(grep ^LITELLM_MASTER_KEY ~/.lmstack/env/stack.env | cut -d= -f2)
```

For a remote host, read it over SSH rather than copying it into your shell rc.

## Keep `limit.context` honest

`context` and `output` must match what the model YAML declares. Setting them
higher does not give you more context — it gives you requests the server
truncates or rejects, and the failure surfaces as the model ignoring the start
of your file.

Unlike the pi extensions, nothing validates this fragment against the catalog.
`make validate` covers `pi-config/extensions/`; this file is a copy-paste
starting point, so when you change a host's models, change it here too.

## Or use the skill from opencode

`make skill-install AGENT=opencode` installs the same interactive installer that
Claude Code gets. Setting a host up and using it as a provider are independent —
you can do either, or both.
