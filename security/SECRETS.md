# Secrets

The harness needs a few secrets. They are never written in the repository, never shown on screen or in a log, and no
model can read them: the scripts fetch each one when a service starts and hand it to that service only.

| Name | What it is | Made by |
|---|---|---|
| `WEBUI_SECRET_KEY` | signs Open WebUI's sessions | random, 32 bytes (`openssl rand -hex 32`) |
| `N8N_ENCRYPTION_KEY` | encrypts the credentials stored in n8n | random, 32 bytes |
| `WEBUI_ADMIN_EMAIL` | the administrator account of Open WebUI | you |
| `WEBUI_ADMIN_PASSWORD` | its password, 12 characters or more | you |
| `OAUTH_CLIENT_ID`, `OAUTH_CLIENT_SECRET` | only with sign-in through an OpenID Connect provider (`ALICE_OIDC_PROVIDER_URL`) | the provider |

The installer asks where they live (`ALICE_SECRET_STORE` in `machine.env`).

## A protected file (simplest)

The installer creates the file (`ALICE_SECRETS_FILE`, root only), generates the random keys and asks for the
administrator account. Nothing else to do. To add or change a secret later: `sudo bash security/secrets.sh set NAME`.

Open WebUI reads `WEBUI_ADMIN_EMAIL` and `WEBUI_ADMIN_PASSWORD` only to create the administrator on its first start. To
change them later, change them first in Open WebUI (Settings → Account), then in the secret store, so that the scripts
can still sign in. `N8N_ENCRYPTION_KEY` must never change once n8n holds credentials.

## A vault you already run (OpenBao or HashiCorp Vault)

Put the four secrets in a key/value (version 2) secret, for example at `secret/alice-harness`, from a shell logged in to
the vault:

```bash
bao kv put secret/alice-harness \
  WEBUI_SECRET_KEY="$(openssl rand -hex 32)" N8N_ENCRYPTION_KEY="$(openssl rand -hex 32)" \
  WEBUI_ADMIN_EMAIL="you@example.com" WEBUI_ADMIN_PASSWORD="$(read -rsp 'Password: ' p; echo "$p")"
```

(`vault kv put` with HashiCorp Vault.) Then give the installer the vault's address and that path. The installer and
the doctor run as root and read the secrets with the vault's own client (`bao`, or `vault`): root must be logged in to the vault, or have
a token allowed to read that path. The key/value engine: https://openbao.org/docs/secrets/kv/kv-v2/

A vault starts sealed after a reboot: the services wait until you unseal it on the machine. With the phone alerts set
up, the harness tells you when it is waiting (https://openbao.org/docs/concepts/seal/).

## Installing OpenBao

Follow https://openbao.org/docs/install/ to install it as a service on this machine, initialise it (keep the unseal
keys and the root token somewhere safe, off this machine), unseal it, enable a key/value version 2 engine at `secret/`,
then put the secrets as above and run `sudo ./install.sh` again.

## Another secret store

Any store with a command line works: the harness runs one command per secret, with `{name}` standing for the secret's
name, and takes what it prints. For example, in `machine.env`:

```bash
ALICE_SECRET_STORE=command
# pass, the standard Unix password manager, with the secrets under alice/
ALICE_SECRET_COMMAND="pass show alice/{name}"
# or 1Password, with one item per secret in a vault named Alice
ALICE_SECRET_COMMAND="op read op://Alice/{name}/password"
```

The command runs as root, so the store must be usable by root without a prompt.
