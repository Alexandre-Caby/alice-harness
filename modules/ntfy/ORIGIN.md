# ntfy module

Push notifications to phones (Android app, F-Droid or Play). The server denies everything by default; each person
gets an account and a token. Phones reach it through your reverse proxy or tunnel (`ALICE_NTFY_URL`); if that proxy
asks for authentication, the Android app (1.21.1 or later) can send a token in its custom headers.

| Part | Source | License |
|---|---|---|
| ntfy | [binwiederhier/ntfy](https://github.com/binwiederhier/ntfy) 2.37.2, image pinned in `versions.lock` | Apache-2.0 / GPL-2.0 |
