# Hermes Profile Env Templates

These templates are documentation examples for the host-managed profile env
directories:

- `/var/lib/hermes-agent/profiles/pa/env.d/`
- `/var/lib/hermes-agent/profiles/coder/env.d/`
- `/var/lib/hermes-agent/profiles/orchestrator/env.d/`

Files must use systemd `EnvironmentFile` syntax:

```sh
KEY=value
QUOTED_KEY="value with spaces"
```

Do not include `export`. Put real secrets only in `/var/lib/hermes-agent/...`,
not in this repository.

Recommended file split:

- `00-model.env`: LLM provider credentials and advertised API model name.
- `10-api.env`: profile API server and webhook secrets.
- `20-telegram.env`: Telegram bot access for that profile. Prefer enabling
  Telegram on `orchestrator` first, because it owns the shared Kanban board.
- `30-github.env`: GitHub access, coder only unless another profile needs it.
- `30-google-workspace.env` or `40-google-workspace.env`: optional Google API
  keys for Gemini/auxiliary use. Gmail and Calendar OAuth state is stored as
  profile-local JSON files, not env vars.

Copy the examples into the live host env directory without the `.example`
suffix:

```sh
sudo install -m 0600 docs/hermes/env-templates/orchestrator/00-model.env.example \
  /var/lib/hermes-agent/profiles/orchestrator/env.d/00-model.env
```

Host-side live env directories:

```text
/var/lib/hermes-agent/profiles/orchestrator/env.d/
/var/lib/hermes-agent/profiles/coder/env.d/
/var/lib/hermes-agent/profiles/pa/env.d/
```

Useful starter copies:

```sh
sudo install -m 0600 docs/hermes/env-templates/orchestrator/00-model.env.example \
  /var/lib/hermes-agent/profiles/orchestrator/env.d/00-model.env
sudo install -m 0600 docs/hermes/env-templates/orchestrator/30-github.env.example \
  /var/lib/hermes-agent/profiles/orchestrator/env.d/30-github.env
sudo install -m 0600 docs/hermes/env-templates/orchestrator/40-google-workspace.env.example \
  /var/lib/hermes-agent/profiles/orchestrator/env.d/40-google-workspace.env

sudo install -m 0600 docs/hermes/env-templates/coder/00-model.env.example \
  /var/lib/hermes-agent/profiles/coder/env.d/00-model.env
sudo install -m 0600 docs/hermes/env-templates/coder/30-github.env.example \
  /var/lib/hermes-agent/profiles/coder/env.d/30-github.env

sudo install -m 0600 docs/hermes/env-templates/pa/00-model.env.example \
  /var/lib/hermes-agent/profiles/pa/env.d/00-model.env
sudo install -m 0600 docs/hermes/env-templates/pa/30-google-workspace.env.example \
  /var/lib/hermes-agent/profiles/pa/env.d/30-google-workspace.env
```

The orchestrator profile uses `/var/lib/hermes` as `HERMES_HOME`, so its
Kanban database lives at `/var/lib/hermes/kanban.db`. The `pa` and `coder`
profiles live under `/var/lib/hermes/profiles/` and can be used as Kanban
assignees.

At activation/service start, the live host env files are merged into both
`$HERMES_HOME/.env` and `$HOME/.env`. For `orchestrator`, that means both
`/var/lib/hermes/.env` and `/var/lib/hermes/home/.env`; the latter exists for
tools that search relative to the Unix home directory.

Codex auth is normally created by `hermes-codex-login <profile>` and stored
in the profile-specific `HERMES_HOME/auth.json`; it usually does not need an
env var. You can also run profile-scoped commands directly with
`hermes-container <profile> hermes auth status openai-codex`.
If you intentionally use API-key auth, set `OPENAI_API_KEY` in `00-model.env`.

AWS config/auth for `orchestrator` and `coder` is managed with
`hermes-aws-login <profile> configure` or `hermes-aws-login <profile> login`.
Both run normal access-key based `aws configure`. If you use IAM Identity
Center/SSO instead, use `sso-configure`, `sso-login`, and `sso-logout`.
The AWS CLI state is stored under each profile-specific `HOME` in `.aws/`.

Google Workspace Gmail/Calendar OAuth uses these guest-side files:

```text
/var/lib/hermes/google_client_secret.json
/var/lib/hermes/google_token.json
/var/lib/hermes/profiles/coder/google_client_secret.json
/var/lib/hermes/profiles/coder/google_token.json
/var/lib/hermes/profiles/pa/google_client_secret.json
/var/lib/hermes/profiles/pa/google_token.json
```

The coder profile intentionally creates generic workspace buckets such as
`repos`, `requests`, and `scratch`. Clone or create actual project directories
inside those buckets at runtime instead of adding project names to Nix.

The profile skills include a baked `one-three-one-rule` communication skill.
If you prefer to use the upstream optional skill instead, replace the baked
copy with `hermes skills install official/communication/one-three-one-rule`
inside each profile home.

After changing host env files, restart the VM profile service so `host.env` and
the active profile `.env` are regenerated. The generated `.env` is the
concatenation of `host.env` followed by the profile-local `local.env`, so
guest-side edits and temporary overrides belong in `local.env`.
