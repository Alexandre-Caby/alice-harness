# Home Assistant module

[Home Assistant](https://github.com/home-assistant/core) (Apache-2.0), used as published (image pinned by digest in
`versions.lock`), with its own web interface for setting up devices. It runs without Linux capabilities, on the
internal network with a fixed address and on the egress network to reach devices and integrations (automatic
discovery of devices on the local network is therefore not available; devices are added by address).

The assistant uses Home Assistant's own MCP server through its **Device control** URL (`/api/mcp/assist`): it only
sees and controls the entities exposed to voice assistants, chosen in Home Assistant. Reading states and turning
things on or off are on the decision allow-list (judged); broadcasting, cancelling timers and removing items always
ask. Who gets the connection is chosen when it is added in Open WebUI.

Setup, once:
1. Open the interface: expose `http://<core network>.90:8123` through your reverse proxy, tunnel or VPN; create the
   owner account. Behind a proxy, trust the gateway `<core network>.1` (Settings → System → Network).
2. Settings → Devices & services → Add integration → **Model Context Protocol Server**.
3. Create a non-administrator user for the assistant, sign in as it, and create a long-lived access token (profile →
   Security), and use it as the Bearer key of the MCP connection in Open WebUI (see the README).
4. Add your devices (through their integrations), expose the ones the assistant may use (Settings → Voice
   assistants → Expose), then `./install.sh` → *Update one module* → `home-assistant`.
