# open-webui

The chat UI in front of [`ollama`](../ollama) (`ollama.service.consul`),
routed at `ai.jellify.app` (see [`jellyfin`](../jellyfin)'s README for why a
cosmonautical job serves a `jellify.app` domain), pinned to
`taurus.cosmonautical.cloud` alongside the Ollama instance it talks to.

Auth is Keycloak OIDC (`ENABLE_LOGIN_FORM = false` — SSO-only, no local
password login), accounts merged by email. Backed by its own database on the
shared [`postgres`](../postgres) cluster.

## Consul KV keys

| Key | Used for |
|---|---|
| `open-webui/DB_PASSWORD` | Postgres role password |
| `open-webui/OAUTH_CLIENT_SECRET` | Keycloak OIDC client secret |
| `open-webui/WEBUI_SECRET_KEY` | Session/cookie signing key |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
