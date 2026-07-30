<!-- .slide: class="title" -->

# LMStack

## A development stack for local LLMs

<p class="subtitle">Devashish Meena · AI Tinkerers Seattle · Aug 4, 2026</p>

Note:
5 minutes. Slide 2 is the anchor — spend the most time there. Slide 4 is the demo.

---

<!-- .slide: class="stack" -->

## Dev stack with cloud models

<pre><code class="language-text">
User
  │
  ▼
Claude Code  ─── plugins, memory, generic prompts
  │
  ├── + project context
  │
  ▼
Claude Cloud
</code></pre>

Four boxes. It just works. This is what most of us have.

Note:
Deliberately underwhelming. The point of this slide is the visual contrast with the next one.

---

<!-- .slide: class="stack" -->

## Dev stack with local models

<pre><code class="language-text">
User
  │
  ├── user context
  ├── project context
  ├── harness system prompt
  │
  ▼
LiteLLM              ── model router
  │
  ▼
vLLM · llama.cpp     ── model runtime
  │
  ├── model params        context window, temp, top-p
  ├── runtime config      num_sequences, MTP, KV cache
  │
  ▼
DGX Spark            ── 1 PF FP4 · GB10 unified memory
                        on-desk · air-gapped · no rate limits
</code></pre>

Note:
This slide IS the talk. Don't rush.
Call out three layers: router, runtime config, hardware.
Let the density of the slide carry the argument — you don't have to explain every line.

---

## Why bother?

- **Constraints force creative solutions** — you can't just throw a bigger model at it
- **Cost is becoming a problem** — token bills scale with agent usage, and agents are getting hungrier
- **Learning local unlocks new possibilities** — on-device agents, air-gapped work, fine-tuning loops the cloud won't let you run

Note:
45 seconds. One sentence per bullet, then move on.

---

## Demo

> Real task, real hardware, no cloud.

Note:
Screen recording preferred over live.
Show the agent hitting the local endpoint with observability visible so it's obvious this is local.
Have a backup screenshot in case A/V fails.

---

<!-- .slide: class="closer" -->

# github.com/ric03uec/lmstack

<img src="https://api.qrserver.com/v1/create-qr-code/?size=320x320&data=https://github.com/ric03uec/lmstack" alt="QR to lmstack repo" />

<div class="links">
Apache-2.0 · contributions welcome · @ric03uec
</div>
