# home-assistant

The Home Assistant stack as one job, `home-assistant`, with three groups.
Each group can land on a different node:

| Group | Tasks | Placement |
|---|---|---|
| `mqtt` | `mosquitto` (`eclipse-mosquitto:2.0.22`, container), `zigbee2mqtt` 2.14.2 (raw_exec, Homebrew `node@24`) | `iot` inventory-group hosts that publish a Zigbee adapter in node meta |
| `home-assistant` | `home-assistant` (`ghcr.io/home-assistant/home-assistant:2026.9.4`, container) at `casa.cosmonautical.cloud` | any cosmonautical node |
| `node-red` | `node-red` (`nodered/node-red:5.0.7`, container) at `node-red.cosmonautical.cloud` | any cosmonautical node |

**Startup order.** The order is mqtt, then home-assistant, then node-red.
Nomad starts a job's groups in parallel, so each downstream group has a
`wait-for-*` prestart task. It polls the local Consul agent until the
upstream service (`mqtt` or `home-assistant`) has a passing health check. On
a fresh deploy Home Assistant waits for the broker, and Node-RED waits for
Home Assistant. If a group is rescheduled later, only that group restarts.

All persistent state is on the NFS share under
`/Volumes/Cosmonautical/home-assistant/`, in `config/`, `mosquitto/`,
`zigbee2mqtt/` and `node-red/`. A group can therefore move between nodes,
except `mqtt`, which stays on the host with the USB adapter. Home Assistant's
recorder history goes to the shared Postgres cluster (database
`homeassistant`) rather than SQLite, because SQLite over NFS isn't safe to
lock.

## Why zigbee2mqtt runs on the host

Apple's `container` runs each container in its own VM, with no USB
passthrough. zigbee2mqtt has to open the adapter's serial device, so it runs
natively under `raw_exec`. The `prepare` prestart task `npm install`s it into
the alloc dir. Mosquitto is a normal container, and zigbee2mqtt reaches it
on `127.0.0.1:1883`. That works because published container ports listen on
every host interface, and a loopback address keeps Homebrew's `node` clear of
macOS's Local Network permission prompt.

zigbee2mqtt takes its whole configuration from `ZIGBEE2MQTT_CONFIG_*` env
vars and writes it into `zigbee2mqtt/configuration.yaml` on start. The
Zigbee network key and PAN IDs are `GENERATE`d on the first start and
persisted there. **Don't delete that file.** Losing the network key means
re-pairing every device. Its frontend is LAN-only (no Traefik route), at the
`zigbee2mqtt` Consul service's address. It's protected by
`ZIGBEE2MQTT_FRONTEND_TOKEN`. Pairing can also be started from Home
Assistant's "Permit join" switch, which zigbee2mqtt exposes over MQTT
discovery.

## Host prerequisites (Nomadable)

No host qualifies for the `mqtt` group yet, so that group stays unplaced
until one does. On the Mac with the Zigbee coordinator plugged in:

1. **Put it in an `iot` inventory group** (Semaphore's static inventory too).
   Nomadintosh publishes inventory groups as `meta.inventory_groups`. The
   cosmonautical hosts don't publish that key yet, so they need a Nomadable
   run on a Nomadintosh version that does.
2. **Install `node@24`** for that group. zigbee2mqtt 2.14 supports Node
   22, 24 and up to 26.2, but Homebrew's unversioned `node` is already newer
   than that. Add `group_vars/iot.yml`:

   ```yaml
   additional_homebrew_packages__iot:
     - node@24
   ```

3. **Publish the adapter in node meta** through that host's vars:

   ```yaml
   nomad_client_meta__zigbee:
     zigbee_adapter: /dev/cu.usbserial-XXXX   # ls /dev/cu.* with it plugged in
     zigbee_adapter_type: ember               # ember | zstack | deconz | zigate | zboss
   ```

   `zigbee_adapter_type` is zigbee2mqtt's `serial.adapter`. For example,
   Sonoff's ZBDongle-E is `ember` and its ZBDongle-P is `zstack`.

Until those three are in place, the `mqtt` group shows as a placement
failure, and `home-assistant`/`node-red` sit in their `wait-for-*` prestart
tasks. That's harmless, but the job's deployment won't go healthy.

## Auth

**Home Assistant: LDAP, `cn=Admins` only.** The first auth provider is
`command_line`, labeled "Cosmonautical" on the login page. It runs
`config/ldap-auth/ldap_auth.py`, which does the following:

- Simple-binds to OpenLDAP as `cn=<username>,ou=users,dc=cosmonautical,dc=cloud`.
- Requires that DN to be a `member` of `cn=Admins,ou=groups,...`.
- Logs the user in as a Home Assistant administrator.

Empty passwords are rejected, because slapd treats them as an anonymous bind.
The Home Assistant image has no LDAP client, so the `ensure-config` prestart
uses the host's Homebrew Python to `pip install` the pure-Python `ldap3`
next to the script.

The second provider is Home Assistant's own `homeassistant` provider.
Onboarding creates the owner account with it, and it remains as a
break-glass login.

**`cn=Admins` is empty right now.** It only holds the
`empty-membership-placeholder`, so nobody can log in through LDAP until
someone is added to it. Add members through Keycloak, which owns writes to
`ou=groups`.

**Node-RED: Keycloak SSO, admins only.** The editor's only login is the
OIDC button **"Sign in with Cosmonautical"**: the `label` set in the
managed `settings.js`. It uses `passport-openidconnect`, which the task
`npm install`s into `/data` at startup along with
`node-red-contrib-home-assistant-websocket`. Node-RED nodes run arbitrary
code, so only users whose ID token has `Admins` (or `/Admins`) in its
`groups` claim get in. Everyone else is refused.

Keycloak client `node-red` (realm `cosmonautical`, confidential):

- Redirect URI `https://node-red.cosmonautical.cloud/auth/strategy/callback`
- A **Group Membership** mapper with claim name `groups`, added to the ID
  token. Either full-path setting works.

## Managed vs. UI-owned files

These are overwritten on every deploy, so edit them here and not on disk:

- `config/configuration.yaml`. Add extra YAML as `config/packages/<name>.yaml`.
- `config/ldap-auth/ldap_auth.py`
- `node-red/settings.js`

Everything else, including Home Assistant's `.storage/`, `automations.yaml`,
`scripts.yaml`, `scenes.yaml`, and Node-RED's flows and credentials, is
created once if missing and then left to the apps.

## After the first deploy

1. Open `casa.cosmonautical.cloud`, complete onboarding (it creates the local
   owner account), then add the **MQTT** integration with broker = the
   `mqtt` group's host address, port `1883`, user `homeassistant`, password
   `home-assistant/MQTT_HOMEASSISTANT_PASSWORD`. Zigbee devices then appear
   through MQTT discovery.
2. In Home Assistant, create a long-lived access token. Then, in Node-RED,
   add a Home Assistant server node with base URL
   `https://casa.cosmonautical.cloud` and that token.

Containers here sit behind the VM's NAT, so Home Assistant's LAN discovery
(mDNS/SSDP/HomeKit) won't see devices on its own. Add those integrations
manually by IP.

## Consul KV keys

| Key | Used for |
|---|---|
| `home-assistant/DB_PASSWORD` | `homeassistant` Postgres role password (recorder) |
| `home-assistant/MQTT_HOMEASSISTANT_PASSWORD` | Mosquitto user `homeassistant`, entered in Home Assistant's MQTT integration |
| `home-assistant/MQTT_ZIGBEE2MQTT_PASSWORD` | Mosquitto user `zigbee2mqtt` |
| `home-assistant/MQTT_NODERED_PASSWORD` | Mosquitto user `nodered`, for any MQTT nodes in Node-RED flows |
| `home-assistant/ZIGBEE2MQTT_FRONTEND_TOKEN` | zigbee2mqtt frontend auth token |
| `home-assistant/NODE_RED_OIDC_CLIENT_SECRET` | Keycloak `node-red` client secret |
| `home-assistant/NODE_RED_CREDENTIAL_SECRET` | Encrypts Node-RED's `flows_cred.json`. **Changing it makes existing flow credentials unreadable.** |
| `postgres/PATRONI_SUPERUSER_PASSWORD` | Bootstrap: creating the `homeassistant` role/database |

Generated values are hex (`python3 -c "import secrets; print(secrets.token_hex(24))"`),
because `DB_PASSWORD` is embedded unescaped in the recorder's `postgresql://` URL.

## Nomad Variables

Path `nomad/jobs/home-assistant`:

```sh
curl -X PUT 127.0.0.1:4646/v1/var/nomad/jobs/home-assistant -d '{
  "Items": {
    "HOME_ASSISTANT_URL": "https://casa.cosmonautical.cloud",
    "NODE_RED_URL": "https://node-red.cosmonautical.cloud",
    "OIDC_ISSUER": "https://auth.cosmonautical.cloud/realms/cosmonautical"
  }
}'
```

| Item | Used for |
|---|---|
| `HOME_ASSISTANT_URL` | Home Assistant's `external_url` |
| `NODE_RED_URL` | Base of Node-RED's OIDC callback URL |
| `OIDC_ISSUER` | Keycloak realm issuer. It must match the token's `iss` exactly (no trailing slash). |

The Traefik `Host()` rules are still hardcoded in the service tags, because
service tags can't read Nomad Variables.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
