# ollama

Runs `ollama serve` (Homebrew) pinned to `taurus.cosmonautical.cloud`,
models stored on an external drive (`/Volumes/WD Black/ollama-models`).
Consumed by [`open-webui`](../open-webui) via the `ollama` Consul service
name.

Single instance today. A multi-instance setup (an additional Ollama on one
or more of jellify's Mac minis, to keep more models warm at once via Open
WebUI's multi-connection support) was discussed 2026-09-30 but not
implemented as part of this migration — see `.agents/AGENTS.md` if picking
that up later; it needs a Consul service rename first (`ollama-cosmonautical`
etc.) since two instances can't both register as plain `ollama` without
Consul DNS round-robining between them.

## Consul KV keys

None — no `template`/`{{ key ... }}` references in this job's spec.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
