# Egress proxy

[Squid](https://www.squid-cache.org/) (GPL-2.0), the Debian package on the pinned Python base image. It is n8n's only
way out: n8n is not on the egress network, so it reaches the internet only through the proxy, only the sites listed in
`ALICE_EGRESS_N8N` (a leading dot includes subdomains), and never a private or internal address, this machine and the
harness networks included. Workflows written by the assistant run in n8n: the list bounds where their data can go.

Some services keep a direct exit, on purpose:
- **Open WebUI** reads the web for people: the pages it opens cannot be listed in advance. Its own protection against
  internal addresses checks each connection, and Open WebUI's code notes that this check is bypassed when traffic goes
  through a proxy. The approval gate guards the rest (a page is opened without approval only on a site the person
  named).
- **Home Assistant** talks to devices on the local network with their own protocols, not through an HTTP proxy.
