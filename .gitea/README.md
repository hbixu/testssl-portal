# Gitea Workflows

These workflows run only on Gitea and **are not synced** to GitHub.

## Sync to GitHub (`workflows/sync-to-github.yaml`)

Syncs the repository to GitHub on every **push to the `main`** branch:

- Pushes the `main` branch to GitHub (excluding the `.gitea` and `internal/` folders).
- Pushes tags that start with `release-*` to GitHub.

### Gitea configuration

In the repository **Settings → Secrets and Variables**:

| Type       | Name                 | Description |
|------------|----------------------|-------------|
| **Secret** | `SYNC_GITHUB_TOKEN`  | GitHub Personal Access Token with `repo` scope. |
| **Variable** | `SYNC_GITHUB_REPO`     | GitHub repository in the form `owner/repo-name` (e.g. `myuser/testssl-portal`). |

Note: Gitea does not allow secret/variable names starting with `GITEA_` or `GITHUB_`.

### GitHub token notes

- **Permissions**
  - **Classic PAT:** scope `repo` (or `public_repo` if the GitHub repo is public).
  - **Fine-grained PAT (recommended):** Repository access = this repository only; **Contents** = Read and write. You can add other repositories to the same token later if needed.

- **Expiration**
  - Not required for classic PATs (you can choose "No expiration"), but setting an expiration (e.g. 1 year) is recommended. Fine-grained PATs must have an expiration (max 1 year).
  - Before the token expires: create a new token on GitHub, update the `SYNC_GITHUB_TOKEN` secret in Gitea, then revoke the old token on GitHub.
