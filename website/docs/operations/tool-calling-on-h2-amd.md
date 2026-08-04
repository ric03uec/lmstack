# Tool calling on h2-amd (llama.cpp)

Why `h2-amd` serves Hermes 3 for tool-calling workloads instead of Qwen 2.5 Coder,
and every path I tried before landing there. If you go looking to "fix" this by
putting a coder model back on the h2 default, read this first.

## Setup

- Host: `h2-amd` (AMD Radeon 860M iGPU on a Krackan APU, Ubuntu 26.04)
- Engine: `llama.cpp` `server-vulkan` image, single-slot, `--flash-attn on`
- Client: `pi` (Earendil coding agent), default tool set, tools enabled

The pi harness in the ancestor `ric03uec/system` stack ran tools fine on this
exact box. lmstack didn't, out of the box, despite being nearly the same code.
Chasing that gap ended in the model swap documented here.

## What worked

**Hermes 3 Llama 3.1 8B, Q4_K_M, 32k context, custom `chatml-tools.jinja`
template.** pi issues `bash`/`read`/`write`/`edit` tool calls, llama-server's
chat parser extracts them, tools execute, model reads the tool responses back,
final answer arrives. Same combination the ancestor system stack uses.

Concretely:

```
extra_args:
  - --chat-template-file
  - /templates/chatml-tools.jinja
  - --flash-attn
  - "on"
```

The template file is the standard Qwen ChatML tool-priming block (works for
Hermes too — it's the *priming instruction* that matters, not the model
identity in the fallback string). Priming tells the model:

> For each function call, return a json object with function name and arguments
> within `<tool_call></tool_call>` XML tags.

llama.cpp's chat parser looks for that exact tag shape. Hermes obeys it.

## What did not work

Every attempt below was against Qwen 2.5 Coder 7B, which was the original
default on this host.

### 1. Q4_K_M @ 16k context, `--jinja` (default embedded template)

- pi's default tool set includes `@narumitw/pi-goal`, whose tool schemas use
  `Type.String({minLength, maxLength})` and `Type.Integer({minimum})`.
  llama-server's own `json-schema-to-grammar` emits a GBNF construct that
  llama-server's GBNF parser then refuses (`failed to parse grammar`).
- Bisected pi's extensions one at a time to identify pi-goal as the offender.
  Removing pi-goal (`pi remove npm:@narumitw/pi-goal`) makes the grammar
  compile.
- With the grammar compiling, next wall: pi's combined system prompt + tool
  schemas run ~17 000 input tokens, 16k context clamps every tools-mode
  response to zero or one output token (`stopReason: length`, `output: 1`).

### 2. Q4_K_M @ 32k context, `--jinja`

Grammar compiles, request fits. Model emits tool calls but wraps them in a
markdown fence:

    ```json
    {"name": "bash", "arguments": {"command": "uname -r"}}
    ```

llama-server's chat parser only extracts `<tool_call>…</tool_call>` shapes.
The whole blob lands in `message.content` as text; pi renders it as a
suggestion, tool never runs.

### 3. Q6_K @ 32k context, `--jinja`

The model YAML notes for the original Qwen setup predicted this would fix
tool-call adherence. It didn't. Same ```json fence, same failure mode. Q6_K
also runs prompt processing measurably slower on this iGPU (~100 tok/s at Q6
vs ~130 at Q4), so a 17k-token pi prompt takes ~170 s of prompt eval alone.

### 4. Q4_K_M @ 32k, custom `chatml-tools.jinja` (Qwen-primed)

Template loaded (verified: `cacheRead: 17656`, so the whole primed prompt
was applied and cached). Same ```json fence in the response. Qwen 2.5 Coder
is fine-tuned on code, and its trained instinct to fence code-shaped output
overrides the priming instruction. This is when I stopped trying to make
Qwen work.

### 5. Not tried, unlikely to help

- Aggressive `--append-system-prompt` overriding fence habits: partially
  attempted, hard to iterate on this hardware because each pi call takes
  ~90 s at Q4_K_M / 32k / 17k prompt. Even if it partially works, the model
  reverts under distribution shift, and the tool-call contract needs to be
  reliable, not statistically OK.
- Q8_0: strictly larger and slower than Q6_K, no reason to think it changes
  what Q4→Q6 didn't.
- A LiteLLM-side post-processor that rewrites fenced calls into
  `<tool_call>` before the response reaches the client: real engineering,
  ships a bug-shaped workaround, would need matching logic for streaming and
  for multi-call turns. Model swap is cheaper.

## The invariant this bends

`AGENTS.md` invariant #3 says alias parity: `qwen2.5-coder-7b` should mean the
same thing on every host that serves it. h2-amd no longer serves that alias;
it serves `hermes-3-llama-3.1-8b` instead. `tests/parity.yml` was reduced to
an empty `required_common_aliases: []` list with a comment linking here.

Restore parity if either happens:
- We find a coder-family model that emits `<tool_call>` cleanly under
  llama.cpp on this hardware.
- We ship a LiteLLM (or client-side) parser that reliably extracts fenced
  tool calls back into a `tool_calls` array.

Until then, the split is deliberate: **h1-nvidia → Qwen 2.5 Coder under vLLM
(xgrammar handles the schema-constrained decoding server-side, no fencing
issue), h2-amd → Hermes 3 under llama.cpp**.

## pi will show tool calls but not run them until the directory is trusted

Independent of everything above — pi auto-approves tool execution only in
directories listed in `~/.pi/agent/trust.json`. If tool calls render in the
UI as `bash "…"` but nothing runs, the stack is working and pi is refusing to
execute for a permissions reason:

```bash
jq '. + {"/full/path/to/your/project": true}' ~/.pi/agent/trust.json \
  | sponge ~/.pi/agent/trust.json
# or, per-run:
pi --approve --provider lmstack-h2 …
```

This tripped an entire debugging session ("system stack works, lmstack
doesn't, same box, same model") because the system directory was trusted and
the lmstack directory wasn't.

## If you're debugging this on your own box

- `pi --provider lmstack-h2 --mode json -p "call bash with 'uname -r'"` and
  inspect the `assistantMessageEvent.type=="text_end"` payload — if it's a
  fenced JSON blob, you're seeing exactly the failure this doc is about.
- `docker logs llama-hermes-3-llama-3.1-8b | grep -i tool_call` — if the
  chat parser is extracting successfully you'll see references to tool call
  handling in the srv logs.
- `docker inspect llama-hermes-3-llama-3.1-8b --format '{{range .Config.Cmd}}{{.}} {{end}}'`
  should include `--chat-template-file /templates/chatml-tools.jinja`. If
  `--jinja` shows up instead, the model YAML got mangled during a rebuild.
