# Workspace module

A personal workspace for each person listed in `ALICE_WORKSPACE_USERS`: files, a shell, Python, Node, C, Rust, git,
LibreOffice and the Office libraries. It is [Open Terminal](https://github.com/open-webui/open-terminal), Open WebUI's
own terminal server, used as published, one container per person, so the separation between people comes from the
containers, not from code. Each container runs under gVisor (`runsc`), as an unprivileged user, on the internal
network only (no internet), with a read-only root filesystem and memory and process limits.

Open WebUI connects each workspace to its person's account only. Files attached in the chat are written into the
workspace (`chat_uploads: filesystem`), where the assistant edits them; the result shows in the chat and in the file
browser. Browser and desktop control are turned off. A last workspace, granted to the `workspace-tests` group, serves
the tests, which join it with temporary accounts.

| Part | Source | License |
|---|---|---|
| Open Terminal 0.17.8 (image pinned by digest in `versions.lock`) | [open-webui/open-terminal](https://github.com/open-webui/open-terminal) | MIT |
| Rust, pytest | Debian packages, PyPI (`Dockerfile`) | MIT / Apache-2.0 |
| Sandbox | [gVisor](https://github.com/google/gvisor) | Apache-2.0 |
| Glue | `connections.py`, `run.sh`, this repository | MIT |

Open Terminal's own multi-user mode keeps people in one container and does not isolate them (its README says so);
its per-user orchestrator needs an Open WebUI Enterprise license. One container per person costs about 120 MB of
memory at rest each, plus what the person's code uses within the limits.

Adding a person: create their Open WebUI account, add their e-mail to `ALICE_WORKSPACE_USERS`, then
`./install.sh` → *Update one module* → `workspace`.

## Shared folder, read-only

A folder mounted read-only on this machine, a network drive for example, appears in every workspace as `~/shared`
(`ALICE_SHARED_NAME` gives it another name),
read-only again; the assistant searches and reads it with the workspace's own tools, and nothing it runs can change it.
Mount it once on the machine, read-only, for example in `/etc/fstab`:

```
# NFS
files.example.lan:/export/share  /mnt/shared  nfs   ro,nosuid,nodev,noexec  0 0
# SMB, credentials in a root-only file
//files.example.lan/share        /mnt/shared  cifs  ro,nosuid,nodev,noexec,credentials=/root/.share-credentials  0 0
```

then set `ALICE_SHARED_PATH=/mnt/shared` and update the module. `run.sh` refuses a folder that is not mounted read-only.
