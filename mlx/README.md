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
  (`HF_HOME=/Volumes/WD Black/huggingface`). Nothing is downloaded at
  deploy time: the server fetches a model the first time a request names
  it. To add one, put its repo ID (e.g. `mlx-community/Qwen3.5-9B-4bit`) in
  Open WebUI's Model IDs for the MLX connection and start a chat. The first
  reply waits for the download. Use `mlx-community/*` repos.
- **One model is loaded at a time.** Each request names its model, and the
  server swaps when it changes. `/v1/models` lists only cached repos that
  ship a `model.safetensors.index.json`. Open WebUI ignores that list once
  the connection has Model IDs set, so list every model there.
- `--max-tokens=8192`. The server defaults to 512, which truncates chat
  replies whenever the client doesn't send `max_tokens`.
- mlx-lm 0.32.2 doesn't support `gemma4_unified` models (e.g.
  `mlx-community/gemma-4-12B-4bit`), only `gemma4`/`gemma4_text`.

## Consul KV keys

None — no `template`/`{{ key ... }}` references in this job's spec.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
