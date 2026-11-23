# mlx

Runs [`mlx_lm.server`](https://github.com/ml-explore/mlx-lm) `0.32.2`, an
OpenAI-compatible API on Apple's MLX, on port `11435`. Pinned to
`taurus.cosmonautical.cloud` while we try it out next to
[`ollama`](../ollama). [`open-webui`](../open-webui) reaches it at
`http://mlx.service.consul:11435/v1`.

Notable pieces:

- **Nothing to install on the host.** The `install` prestart task fetches
  uv and the mlx-lm wheel from PyPI with go-getter (both checksum-pinned),
  builds a Python 3.12 venv in the alloc dir, and installs the wheel.
  uv downloads its own Python and keeps a cache under `~/.local/share/uv`
  and `~/Library/Caches/uv`, so later allocs build in seconds.
- **Models** live in the Hugging Face cache on the external drive
  (`HF_HOME=/Volumes/WD Black/huggingface`). The `fetch-models` poststart
  task downloads everything in `MODELS`, and finishes right away when they're
  already cached. Use `mlx-community/*` repos.
- **One model is loaded at a time.** Each request names its model, and the
  server swaps when it changes. `/v1/models` lists cached repos that ship a
  `model.safetensors.index.json`. A single-file model won't show up in the
  list but still works if requested by name. You can add it to the
  connection's model IDs in Open WebUI.
- `--max-tokens=8192`. The server defaults to 512, which truncates chat
  replies whenever the client doesn't send `max_tokens`.
- mlx-lm 0.32.2 doesn't support `gemma4_unified` models (e.g.
  `mlx-community/gemma-4-12B-4bit`), only `gemma4`/`gemma4_text`.

## Consul KV keys

None — no `template`/`{{ key ... }}` references in this job's spec.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
