# A.L.I.C.E. Harness

**A self-hosted, local-first AI assistant: one window, some swappable modules.**

<sub>A.L.I.C.E.: Artificial Labile Intelligent Cybernated Existence</sub>

A.L.I.C.E. Harness assembles proven open-source pieces into a personal assistant that remembers you and acts for you, **with your approval**. Everyone you give an account to uses it from a browser. It chats with local language models, reads your documents, creates images, and can grow with any module you plug in. Everything runs on your own machine, at your own accord.

---

## Why

Most "personal AI" stacks grow into a pile of glue code that nobody can maintain. A.L.I.C.E. Harness takes the opposite
route: *less is more*.

- **One core**: [Open WebUI](https://github.com/open-webui/open-webui) (window, accounts, memory, tools, approvals)
  and [Ollama](https://github.com/ollama/ollama) (language models).
- **Modules around it**: image generation, speech, document reading, or anything you want to plug in. Each module is
  a separate container that speaks a standard API (OpenAI-compatible, MCP and others). Replacing a model or an engine
  means editing one `openwebui.conf`, and adding a capability means adding one module. Nothing else moves.
- **Configuration over code**: upstream projects are used as published; the custom code is a small decision-model
  adapter, the glue that connects each person to their own workspace and tools, an hourly health alert, and a
  four-line patch to Open WebUI's approval logic.
- **Security outside the model**: no security rule relies on the model behaving well.

## Features

| Capability | How |
|---|---|
| Multi-user chat | Open WebUI accounts; private memory, chats and files for each person |
| Proactive memory | The assistant saves durable facts on its own (only from what the person said, never from documents) |
| Web search | Open WebUI's built-in search, results cited |
| Documents and photos | Apache Tika with OCR (photos of paper included) |
| Office files, charts, code | A personal workspace for each person ([Open Terminal](https://github.com/open-webui/open-terminal)) in a gVisor sandbox with no internet; files dropped in the chat land there, results are previewed in the chat |
| Images | Generation and editing through an OpenAI-compatible image server |
| Voice | Speech-to-text and text-to-speech modules (a browser only opens the microphone over HTTPS: reach Open WebUI through your reverse proxy or tunnel) |
| Automations | Open WebUI scheduled tasks for each person; n8n (each person's own account, through n8n's MCP server) builds workflows that stay unpublished until approved |
| Approval before action | Auto mode judged by a local decision model, with a deterministic allow-list floor |
| Phone alerts | ntfy |

## Architecture

```
  browser          ──► Open WebUI ──────────────► Ollama (chat models)
                          │  │  │
                          │  │  └── one workspace per person (Open Terminal, gVisor, no internet)
                          │  └───── modules: images · stt · tts · ocr · decision
                          └──────── approval gate ──► decision adapter ──► decision model
  background: n8n · ntfy · Home Assistant · egress proxy · secret store
```

### Approval gate

Every tool call goes through a gate before it runs:

1. **Allow-list first.** Only listed tools can run without asking. Anything else (sending, paying, publishing, or
   any tool added later) always asks you first. This rule is plain code; no model can change it.
2. **The wall instead of a judge where it suffices.** Work in your workspace (files, commands, code) and reads of
   your own data run straight away: the workspace has no internet and no access to the rest of the server, and with
   the backup module its files are saved every night.
3. **A small decision model judges what reaches outside.** Searching the web, opening a page, saving a memory,
   automations, the calendar, n8n and Home Assistant: a local decision model looks at the exact call and its
   arguments and asks for approval when something looks risky.
4. **Fail safe.** If the decision model is slow, unreachable or unsure, the gate asks you.
5. **No hidden bypass.** Opening a web page passes without approval only when you named that site yourself, so a link
   planted in a document cannot quietly send your data out. Open WebUI's per-chat "full access" mode, which would skip
   every approval, is disabled by a small patch checked against the upstream file.

## Requirements

- Linux host with Docker and a GPU usable through Vulkan, ROCm or CUDA (CPU-only works for some modules, slowly)
- Enough memory for your chosen models
- Ollama on the host: the onboarding installs and sets up the pinned version (direct GPU access, no container
  layer), or uses an Ollama you already run
- ufw enabled with incoming traffic denied (the harness adds its rules there); `curl`, `python3`, `openssl`, `patch`,
  `sha256sum`, `ss`, `setsid`
- [gVisor](https://gvisor.dev/docs/user_guide/install/) (`runsc`) for the workspaces

Tested on one machine, the reference for every figure quoted in the modules' notes: AMD Ryzen AI Max+ 395, 128 GB of
unified memory, Vulkan. The other backends (ROCm, CUDA, CPU) and machines with a separate GPU are expected to need
adjustments: the module images are built for Vulkan, and the memory check counts the whole RAM as GPU memory.

The installation is a base to start from: models, modules, the assistant's soul, the voice and the allow-list are yours
to change (see Configuration, and each module's notes). A model can come from the Ollama library or straight from Hugging
Face (`hf.co/user/repo:quantisation`); one of the Qwen 3.5 family gets Ollama's own Qwen 3.5 format rather than the
file's chat template, which misses some tool calls, and Qwen's recommended sampling.

## Quick start

```bash
sudo git clone https://github.com/Alexandre-Caby/alice-harness.git /srv/alice-harness
cd /srv/alice-harness
sudo ./install.sh
```

`install.sh` is a terminal onboarding (drawn with [gum](https://github.com/charmbracelet/gum), downloaded once and
checked by its hash). It gets to know the machine on its own (system, memory, GPU, Docker, gVisor, an existing secret
vault), then asks only what it cannot guess: where the secrets live, the soul and the models, the modules to install,
and who will use it (just you, people from a file, or typed in). It installs everything under one progress bar, the
details going to a log, runs the checks and shows only what failed, then gives the addresses and offers to set up the
phone alerts. People added from a file get their accounts at once, with temporary passwords written to a root-only
file, never shown.

On a machine where it is installed, `sudo ./install.sh` shows the state and asks what to do; the same can be typed
directly:

| Command | What it does |
|---|---|
| `sudo ./install.sh update` | Pulls the pinned versions from `versions.lock`, rebuilds what changed, keeps your settings, runs the checks |
| `sudo ./install.sh modules` | Adds or removes modules |
| `sudo ./install.sh module NAME` | Rebuilds and restarts one module (and Open WebUI when it changes its settings), then checks it |
| `sudo ./install.sh people` | Adds people, from a file or typed in |
| `sudo ./install.sh assistant` | Changes the soul or the models |
| `sudo ./install.sh alerts` | Sets up the phone alerts |
| `sudo ./install.sh check` | Runs the checks (also `sudo bash doctor/doctor.sh [test...]`) |
| `sudo ./install.sh uninstall` | Removes the containers, networks and firewall rules; asks before touching your data |

**Health alerts.** With the phone alerts set up, a timer runs the checks that load no model every hour and pushes to
your ntfy topic only when something breaks, then once when it is fixed. With a vault, a boot alert says when it waits
to be unsealed (unsealing remains a manual step on the machine).

## Configuration

| File | Purpose |
|---|---|
| `versions.lock` | The reference set of versions tested together (container images, source commits, model checksums) |
| `machine.env.example` | Template for your machine's settings (compute backend, memory, data paths); the onboarding fills in your own copy, which stays out of the repository |
| `modules/<name>/openwebui.conf` | What Open WebUI needs to reach a module (address, model name); no secret, nothing machine-specific |

### Soul

The assistant's character and rules live in `core/soul/SOUL.md`, a generic soul in English (the assistant answers in
the language it is spoken to). The onboarding lets you write your own, or point `ALICE_SOUL_FILE` in `machine.env` to
a file of yours; the presets carry whichever soul is set.

### Secrets

Secrets (accounts, API tokens, keys) are never stored in the repository and never shown to a model.
The onboarding asks where to keep them:

| Store | For whom |
|---|---|
| **Local secrets file** (default) | Everyone. A root-only file outside the repository; each container receives the secrets it needs when it starts |
| **OpenBao** (optional) | If you already run an OpenBao or HashiCorp Vault server: secrets are read from it when the services start |
| **Any other store** | A command that prints one secret (pass, 1Password, …) |

Which secrets, and how to set up each store (installing OpenBao included): `security/SECRETS.md`.

## Modules

The harness ships with a set of ready-made modules, listed below. Each of them can be replaced, removed, or
complemented by your own: any service that speaks a standard API can become a module.

Every module follows the same contract:

```
modules/<name>/
  openwebui.conf address and model exposed to Open WebUI; the only file to edit to swap the module
  build.sh       builds the container from a pinned source and fetches its model files; not needed when run.sh
                 only starts a published image
  run.sh         starts it: unprivileged, limited network
  test.py        end-to-end check, prints "PASS" or the reason it failed
  ORIGIN.md      upstream source, commit or digest, license, measured memory and latency
```

| Module | Default implementation | API |
|---|---|---|
| `images` | stable-diffusion.cpp server with FLUX 3 Image Klein | OpenAI images |
| `stt` | NVIDIA Nemotron 3.5 Transcribe, with a custom vocabulary | OpenAI transcriptions |
| `tts` | Qwen3-TTS (C engine) | OpenAI speech |
| `ocr` | Apache Tika 4.2 with Tesseract | Tika |
| `decision` | llama.cpp server with a decision model, behind the decision adapter | Decisions (adapter) |
| `workspace` | Open Terminal, one container per person, in a gVisor sandbox | Open Terminal |
| `home-assistant` | Home Assistant, with its own interface; its MCP server is connected afterwards (below) | MCP |
| `n8n` | n8n | n8n API |
| `ntfy` | ntfy server | ntfy |
| `backup` | restic, every night, to a local repository (see `modules/backup/ORIGIN.md`) | — |

**Adding your own module.** Create a folder under `modules/` with these files, point `openwebui.conf` at your service, and run `sudo ./install.sh modules`. A module is a
theme: one module holds every tool of its theme (all the image tools, for example), whatever model serves them.

### Connecting MCP servers

MCP servers (GitHub, a mail server, the MCP servers of n8n and Home Assistant…) are not part of the harness: connect
them in Open WebUI's admin settings, with their own token, and grant each one to the accounts that should use it. They
are kept across updates; every other Open WebUI setting belongs to the harness and is set again at each update.

| Service of the harness | MCP address inside the harness | Token |
|---|---|---|
| n8n | `http://n8n:5678/mcp-server/http` | each person's own key, from n8n's MCP settings |
| Home Assistant | `http://home-assistant:8123/api/mcp/assist` | a long-lived token of a non-administrator user |

The approval gate judges, without asking, the tools of any connected server whose names say they read (`*_get_*`,
`*_list_*`, `*_search_*`, `*_read_*`), plus the few n8n and Home Assistant tools listed in
`modules/decision/allowlist.txt`; every other tool asks first. Add a line there to let another tool be judged instead
of always asking.

## Repository layout

```
alice-harness/
  install.sh            interactive onboarding: install, update, reconfigure, uninstall
  versions.lock         pinned versions
  machine.env.example   template for machine-specific settings
  core/
    open-webui/         run script, settings, approval patch and upstream hash
    ollama/             service settings (loaded models, parallelism, context)
    soul/               the assistant's system prompt and the presets that carry it
  modules/              one folder per module (contract above)
  security/             networks, firewall rules, egress proxy, secret store (local file or OpenBao), test of the walls
  doctor/               health check (doctor.sh), its hourly alert and the boot unlock alert (health.sh, systemd units)
  lib/                  shared shell helpers (settings, secrets, verified downloads)
  tests/                Open WebUI test client and the end-to-end approval test
```

## Security model

- Code runs only in a person's workspace: gVisor sandbox, unprivileged user, no internet, memory and process limits;
  its network is shared only with Open WebUI and the speech, voice, OCR and image services;
  each workspace is granted to one account only.
- Each network flow is opened to a single sender; no workspace can reach the model server.
- n8n, where the workflows the assistant writes run, goes out only through the egress proxy and its list of sites;
  Open WebUI (reading the web) and Home Assistant (local devices) keep a direct exit, explained in
  `security/egress/ORIGIN.md`.
- External content (web pages, mail, documents) is data, never instructions; memory is written only from what the
  user said.
- Outbound actions always require approval, enforced outside the model.
- Secrets stay in the secret store (local file or OpenBao); models never see them.

## License

A.L.I.C.E. Harness is released under the [MIT License](LICENSE).

It installs and orchestrates third-party software and models that keep their own licenses. Model weights are
downloaded from their publishers and are never redistributed by this repository. Check each license before use,
especially for commercial use.

| Component | License |
|---|---|
| [Open WebUI](https://github.com/open-webui/open-webui) | Open WebUI License (BSD-3-Clause based, with a branding clause) |
| [Ollama](https://github.com/ollama/ollama) | MIT |
| [llama.cpp](https://github.com/ggml-org/llama.cpp) | MIT |
| [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) | MIT |
| [Apache Tika](https://github.com/apache/tika) | Apache-2.0 |
| [gVisor](https://github.com/google/gvisor) | Apache-2.0 |
| [Open Terminal](https://github.com/open-webui/open-terminal) | MIT |
| [Home Assistant](https://github.com/home-assistant/core) | Apache-2.0 |
| [Squid](https://www.squid-cache.org/) | GPL-2.0 |
| [qwen3-tts (C engine)](https://github.com/gabriele-mastrapasqua/qwen3-tts) | MIT |
| [ntfy](https://github.com/binwiederhier/ntfy) | Apache-2.0 / GPL-2.0 (dual) |
| [restic](https://github.com/restic/restic) | BSD-2-Clause |
| [n8n](https://github.com/n8n-io/n8n) | Sustainable Use License (fair-code, not OSI-approved) |
| Qwen3-TTS weights | Apache-2.0 |
| NVIDIA Nemotron 3.5 Transcribe weights | OpenMDW-1.1 |
| FLUX 3 Image Klein weights | FLUX Kommunity License |
| BGE-M3 embeddings | MIT |
| Decision model weights (default) | depends on the model chosen; the current default is CC BY-NC 4.0 (non-commercial) |
| Chat models | depend on the models you pull (e.g. Gemma, Qwen) |
