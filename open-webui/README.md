# open-webui

Runs Open WebUI `0.13.4`, the chat UI in front of [`mlx`](../mlx)
(`mlx.service.consul:11435`, OpenAI-compatible) and
[`ollama`](../ollama) (`ollama.service.consul`). It's routed at
`ai.jellify.app`. See [`jellyfin`](../jellyfin)'s README for why a
cosmonautical job serves a `jellify.app` domain. It can run on any
cosmonautical node.

Auth is Keycloak OIDC (`ENABLE_LOGIN_FORM = false` — SSO-only, no local
password login), accounts merged by email. Backed by its own database on the
shared [`postgres`](../postgres) cluster.

Notable pieces:

- **Nothing to install on the host.** The `install` prestart task fetches
  uv and the Open WebUI wheel from PyPI with go-getter (both
  checksum-pinned), builds a Python 3.12 venv in the alloc dir, and installs
  the wheel. Open WebUI needs Python `>=3.11,<3.13`. uv downloads its own
  Python and keeps a cache under `~/.local/share/uv` and
  `~/Library/Caches/uv`, so later allocs on the same host build quickly. A
  version bump is just the wheel URL and checksum.
- **Uploads go to S3** (`STORAGE_PROVIDER = s3`): the `open-webui` bucket
  on [`seaweedfs-filer`](../seaweedfs)'s S3 gateway. The `ensure-bucket`
  prestart creates it, same as `slskd`'s. File rows in Postgres hold
  `s3://open-webui/<id>_<name>` paths, so they work from any node.
- **`DATA_DIR` is on the alloc's sticky, migrating ephemeral disk**
  (`alloc/data/open-webui`). That holds the Chroma vector DB and model
  caches (embedding, whisper). Nomad carries it to the replacement alloc,
  including across nodes while the old node is up. If it's ever lost,
  caches re-download, and attached documents need re-indexing (Admin
  Settings > Documents > Reindex).
- **Connections are persisted in the database**, not read from env.
  `OLLAMA_BASE_URL` here only matters on a fresh database. The MLX
  connection is set in Admin Settings > Connections > OpenAI API
  (`openai.*` keys in the `config` table).

## Consul KV keys

| Key | Used for |
|---|---|
| `open-webui/DB_PASSWORD` | Postgres role password |
| `open-webui/OAUTH_CLIENT_SECRET` | Keycloak OIDC client secret |
| `open-webui/WEBUI_SECRET_KEY` | Session/cookie signing key |
| `seaweedfs-s3/ACCESS_KEY` | Upload storage (S3) credentials |
| `seaweedfs-s3/SECRET_KEY` | Upload storage (S3) credentials |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
