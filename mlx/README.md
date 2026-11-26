# mlx

Runs [`mlx_lm.server`](https://github.com/ml-explore/mlx-lm) `0.32.2`, an
OpenAI-compatible API on Apple's MLX, on port `11435`. One model is split
across two Macs cabled together with Thunderbolt 5: `taurus` (rank 0, serves
the API) and `orion` (rank 1). [`open-webui`](../open-webui) reaches it at
`http://mlx.service.consul:11435/v1`, as an OpenAI API connection (not an
Ollama one).

Notable pieces:

- **Nothing to install on the host.** The `install` prestart task fetches
  uv and the mlx-lm wheel from PyPI with go-getter (both checksum-pinned),
  builds a Python 3.12 venv in the alloc dir, and installs the wheel.
  uv downloads its own Python and keeps a cache under `~/.local/share/uv`
  and `~/Library/Caches/uv`, so later allocs build in seconds.
- **Models** live in each host's Hugging Face cache: the external drive
  on taurus (`/Volumes/WD Black/huggingface`), `~/.cache/huggingface` on
  orion. Each host downloads only its own half of the weights. Nothing is downloaded at
  deploy time: the server fetches a model the first time a request names
  it. To add one, put its repo ID (e.g. `mlx-community/Qwen3.5-9B-4bit`) in
  Open WebUI's Model IDs for the MLX connection and start a chat. The first
  reply waits for the download. Use `mlx-community/*` repos.
- **Distributed over RDMA.** The ranks talk over MLX's `jaccl` backend
  across the cable, configured by env vars instead of `mlx.launch` (which
  would start orion's half over SSH, outside Nomad): `MLX_RANK`,
  `MLX_JACCL_COORDINATOR` (rank 0's link address + the `coordinator` port)
  and `MLX_IBV_DEVICES` (a JSON file; row `i` lists the RDMA device rank `i`
  uses to reach each other rank). Each host needs, before this job can run:
  - RDMA enabled from Recovery (`rdma_ctl enable`). `ibv_devices` should
    list `rdma_enN`.
  - Nomadintosh's `thunderbolt_link` role, which puts `172.31.250.1`
    (taurus) / `172.31.250.2` (orion) on the cabled port. The `rdma_enN`
    names in the job's `ibv_devices.json` must match those ports.
  - macOS Local Network permission for the venv's Python, like any new
    binary that dials the LAN.
- **The two halves fail together.** If rank 1 dies, rank 0's generation
  thread fails, `/health` returns 503, and `check_restart` restarts it.
  `/health` is served on its own thread and only reports whether the
  generation thread is alive, so a long reply doesn't fail it. Rank 1 has no
  HTTP server and doesn't exit when rank 0 dies: it stays up at 100% CPU,
  holding a dead coordinator connection, and no new rank 0 can join it. So
  rank 1 registers `mlx-rank1` with a script check that curls rank 0's
  `/health` across the link (`172.31.250.1:11435`), and `check_restart`
  restarts it once rank 0 has been down for a minute. Its 5-minute grace
  covers rank 0 waiting for it and both loading the model. Both groups
  restart in `delay` mode, so neither gives up while the other is down.
- **Memory.** Each host holds half the model. Rank 1 reserves only 2 GB in
  Nomad, since Nomad has little of orion left to hand out. raw_exec memory isn't enforced on macOS, and orion
  has far more free in practice.
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
