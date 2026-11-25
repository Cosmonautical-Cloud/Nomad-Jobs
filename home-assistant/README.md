# home-assistant

The Home Assistant stack as one job, `home-assistant`, with five groups.
Each group can land on a different node:

| Group | Tasks | Placement |
|---|---|---|
| `mqtt` | `mosquitto` (`eclipse-mosquitto:2.0.23`, container) | any cosmonautical node |
| `zigbee2mqtt` | `zigbee2mqtt` 2.14.3 (raw_exec, Node 24 from nodejs.org) | `iot` inventory-group hosts that publish a Zigbee adapter in node meta |
| `home-assistant` | `home-assistant` (`ghcr.io/home-assistant/home-assistant:2026.11.2`, container) at `casa.cosmonautical.cloud` | any cosmonautical node |
| `node-red` | `node-red` (`nodered/node-red:5.0.10`, container) at `node-red.cosmonautical.cloud` | any cosmonautical node |
| `esphome` | `esphome` (ESPHome Device Builder 1.28.1 + ESPHome 2026.11.0, raw_exec) at `esphome.cosmonautical.cloud` | any Apple silicon cosmonautical node |

**Startup order.** mqtt comes first. zigbee2mqtt and home-assistant both
wait for it, and node-red waits for home-assistant. esphome depends on nothing and starts right away. Nomad starts a job's
groups in parallel, so each downstream group has a `wait-for-*` prestart
task. It polls the local Consul agent until the upstream service (`mqtt` or
`home-assistant`) has a passing health check. If a group is rescheduled later, only that group restarts.

Persistent state is on the NFS share under
`/Volumes/Cosmonautical/home-assistant/`, in `config/`, `mosquitto/`,
`node-red/` and `esphome/`, so those groups can move between nodes.
zigbee2mqtt is the exception: it only runs on the host with the USB adapter,
so its state stays on that host's disk at
`/Users/violet/zigbee2mqtt-local/data`, and that host doesn't need the NFS
share.

**Finding the broker.** Mosquitto isn't pinned to a node. Its port is
static (1883) so that a Consul DNS lookup, which returns only an address, is
enough to reach it. Home Assistant and Node-RED use `mqtt.service.consul:1883`,
and their containers resolve it through the host's `/etc/resolver/consul`.
zigbee2mqtt gets the broker's address and port from a Consul template
instead, and restarts if Mosquitto moves. Home Assistant's
recorder history goes to the shared Postgres cluster (database
`homeassistant`) rather than SQLite, because SQLite over NFS isn't safe to
lock.

## Why zigbee2mqtt runs on the host

Apple's `container` runs each container in its own VM, with no USB
passthrough, and it only runs on Apple silicon. zigbee2mqtt has to open the
adapter's serial device, so it runs natively under `raw_exec`, which also
lets it run on an Intel Mac. The `prepare` prestart task downloads Node
(`node_version`, the `darwin-x64` or `darwin-arm64` build to match the host)
from nodejs.org, checks it against `SHASUMS256.txt`, and `npm install`s
zigbee2mqtt into the alloc dir. Nothing from Homebrew is needed.

zigbee2mqtt connects to Mosquitto over the LAN. `raw_exec` tasks inherit the
`nomad` binary's macOS Local Network permission, so approve `nomad`'s prompt
on that host's screen when it first joins the cluster.

zigbee2mqtt takes its whole configuration from `ZIGBEE2MQTT_CONFIG_*` env
vars and writes it into `configuration.yaml` in its data dir on start. The
Zigbee network key and PAN IDs are `GENERATE`d on the first start and
persisted there. **Don't delete that file.** Losing the network key means
re-pairing every device. It's on hubble's local disk, not NFS, so it's only
backed up if hubble is: copy `configuration.yaml` and `database.db`
somewhere safe after pairing. Its frontend is LAN-only (no Traefik route), at the
`zigbee2mqtt` Consul service's address. It's protected by
`ZIGBEE2MQTT_FRONTEND_TOKEN`. Pairing can also be started from Home
Assistant's "Permit join" switch, which zigbee2mqtt exposes over MQTT
discovery.

## ESPHome

The dashboard is ESPHome Device Builder. As of ESPHome 2026.11,
`esphome dashboard` only prints a pointer to it, so the `prepare` prestart
task creates a venv in the alloc dir with Homebrew's `python@3.14` and
`pip install`s both pinned packages (`esphome_version` and
`esphome_device_builder_version`). It names `python@3.14` explicitly
because that's the version Patroni's venv already uses on every host, and
the install was tested with it. Homebrew's default `python3` is now 3.15.

It runs under `raw_exec` rather than the `ghcr.io/esphome/esphome` image
because the container VM's NAT hides mDNS. Natively, the dashboard can see
which devices are online and push OTA updates to `<name>.local` without
every device needing a static IP or `use_address`. Firmware also compiles
natively, on the host's own CPU. The constraint keeps it on Apple silicon,
because the task uses Homebrew's `/opt/homebrew` paths.

- **Device YAMLs** (and `secrets.yaml` for Wi-Fi credentials) live on NFS
  under `esphome/`, so the group can move between nodes.
- **Build output** goes to `ESPHOME_DATA_DIR` in the alloc dir. It's only a
  cache, so the first compile after a reschedule is slower. PlatformIO's
  toolchains download once per host into `~/.platformio`.
- **Login** is the dashboard's own: user `admin`, password
  `home-assistant/ESPHOME_PASSWORD`. Device Builder has no SSO. Anyone who
  gets in can flash firmware onto every device, so use a strong password.
- **Behind Traefik**, the WebSocket `Origin` check passes because Traefik
  forwards the public `Host` header, so `--trusted-domains` isn't needed.
  HTTPS also lets the browser's Web Serial "plug into this computer" flash
  a new board over USB.
- **Local Network permission** works the same way as zigbee2mqtt: the task
  inherits `nomad`'s. A rolling Nomad restart cuts off running raw_exec
  tasks' LAN access, so restart this task afterwards if OTA uploads start
  failing with `no route to host`.

Each device then shows up in Home Assistant through the **ESPHome**
integration, which talks to the device directly (not through this
dashboard). Home Assistant's container can't see mDNS, so add each device
there by IP.

## Host prerequisites (Nomadable)

No host qualifies for the `zigbee2mqtt` group yet, so that group stays
unplaced until one does. It's meant for `hubble`, the 2012 Intel Mac mini
(macOS Sequoia). It runs only Consul and a client-only Nomad agent: no
`server`, and no `container`, `docker` or `podman` driver, so Nomad never
places the container groups there. It doesn't need the NFS share or
Homebrew's `node`. Nomadintosh still installs Consul and Nomad through
Homebrew, which goes in `/usr/local` on Intel, so set
`homebrew_dir: /usr/local` in hubble's host vars. On the Mac with the Zigbee
coordinator plugged in:

1. **Put it in an `iot` inventory group** (Semaphore's static inventory too).
   Nomadintosh publishes inventory groups as `meta.inventory_groups`. The
   cosmonautical hosts don't publish that key yet, so they need a Nomadable
   run on a Nomadintosh version that does.
2. **Publish the adapter in node meta** through that host's vars:

   ```yaml
   nomad_client_meta__zigbee:
     zigbee_adapter: /dev/cu.usbserial-XXXX   # ls /dev/cu.* with it plugged in
     zigbee_adapter_type: ezsp                # ember | ezsp | zstack | deconz | zigate | zboss
     zigbee_adapter_baudrate: "57600"         # usually 115200
   ```

   `zigbee_adapter_type` is zigbee2mqtt's `serial.adapter` and
   `zigbee_adapter_baudrate` its `serial.baudrate`. For example, Sonoff's
   ZBDongle-E is `ember` at 115200 and its ZBDongle-P is `zstack` at 115200.

   **hubble's coordinator is a Nortek HUSBZB-1** (Zigbee + Z-Wave combo,
   Silicon Labs `10c4:8a2a`). Its Zigbee radio is an EM3581, whose firmware
   stops before EmberZNet 7.4, so `ember` can't drive it. It uses the
   deprecated `ezsp` driver (still in zigbee-herdsman 11.2, which logs a
   deprecation warning on start) at 57600 baud. macOS's built-in Silicon
   Labs driver doesn't match its product ID, so hubble needs Silicon Labs'
   CP210x VCP driver, approved in System Settings, before a `/dev/cu.*`
   device appears. Use the ZigBee interface's device, not the Z-Wave one.
   **The stick's stock firmware (EmberZNet 5.4.1, EZSP v4) is too old for
   zigbee-herdsman**: startup fails at `clearTransientLinkKeys` while forming
   the network. hubble's stick was flashed to EmberZNet 6.7.8 (EZSP v8) on
   2026-11-24 with `ncp.py flash -f ncp-uart-sw-6.7.8.ebl` from
   [walthowd/husbzb-firmware](https://github.com/walthowd/husbzb-firmware),
   which keeps 57600 baud and software flow control. A replacement HUSBZB-1
   needs the same flash. Stop zigbee2mqtt first (scale the group to 0), and
   skip `ncp.py scan`, which hangs probing the Z-Wave port on macOS.
   If `ezsp` is ever removed, the way forward is a newer EFR32-based
   coordinator on `ember`.

Until all three are in place, the `zigbee2mqtt` group shows as a placement
failure. The other groups run normally, but the job's deployment won't go
healthy.

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

**HTTP settings are UI-owned.** Since 2026.11, Home Assistant reads `http:`
from `configuration.yaml` only once, imports it, and ignores it afterwards.
The reverse-proxy settings live under **Settings > System > Network > HTTP
server**: `X-Forwarded-For` on, trusted proxies `10.10.37.0/24` and
`192.168.64.0/24`. Traefik reaches the container through the host's
published port, so requests arrive from the LAN or from the Apple container
network's gateway (`192.168.64.1`, `bridge100`). An HTTP change is applied as
a trial after a restart and reverts after 5 minutes unless you confirm it in
the UI, so open the site through Traefik to confirm it.

Everything else, including Home Assistant's `.storage/`, `automations.yaml`,
`scripts.yaml`, `scenes.yaml`, and Node-RED's flows and credentials, is
created once if missing and then left to the apps.

## After the first deploy

1. Open `casa.cosmonautical.cloud`, complete onboarding (it creates the local
   owner account), then add the **MQTT** integration with broker
   `mqtt.service.consul`, port `1883`, user `homeassistant`, password
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
| `home-assistant/ZIGBEE_NETWORK_KEY` | Zigbee network key, a JSON array of 16 bytes. **Changing it, or `ZIGBEE_PAN_ID`/`ZIGBEE_EXT_PAN_ID`, means re-pairing every device.** |
| `home-assistant/ZIGBEE_PAN_ID` | Zigbee PAN ID, decimal |
| `home-assistant/ZIGBEE_EXT_PAN_ID` | Zigbee extended PAN ID, a JSON array of 8 bytes |
| `home-assistant/NODE_RED_OIDC_CLIENT_SECRET` | Keycloak `node-red` client secret |
| `home-assistant/ESPHOME_PASSWORD` | ESPHome dashboard password for user `admin` |
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
