# GitHub Repository Settings

Manual configuration that lives in the GitHub UI, not in the repository.
Document it here so it survives a fork or recreation.

---

## Branch Protection — `main`

Configure at: **Settings → Branches → Branch protection rules → main**

### Required status checks

The following jobs must pass before a PR can merge:

| Check | Workflow job |
|---|---|
| `Test` | `test` |
| `Scan source` | `scan-source` |
| `Build image` | `build` |

**Strict mode enabled** — the branch must be up to date with `main` before merging. This prevents a PR that passed checks against a stale base from merging after another PR lands.

### Pull request rules

| Setting | Value |
|---|---|
| Required approvals | 1 |
| Dismiss stale reviews on new push | Enabled |
| Require conversation resolution before merge | Enabled |
| Allow bypassing rules (including admins) | **Disabled** |

Admins bypassing protection defeats the purpose. Every change, including hotfixes, goes through the pipeline.

### Push rules

| Setting | Value |
|---|---|
| Force pushes | Disabled |
| Branch deletions | Disabled |

---

## Why these are not in code

Branch protection rules, repository settings, and webhook configurations live in GitHub's API — not in the repository itself. They disappear on repo recreation and are invisible to `git clone`.

They *can* be managed programmatically via:
- The [Terraform GitHub provider](https://registry.terraform.io/providers/integrations/github/latest/docs) (`github_branch_protection` resource)
- The [GitHub API](https://docs.github.com/en/rest/branches/branch-protection)

For a single portfolio repository, Terraform adds tooling overhead that isn't warranted. The correct trade-off here is documentation.

For a multi-repo platform context, the Terraform approach is the right call — settings are versioned, reviewed, and automatically applied. This is the approach taken in Project 3 (`kubernetes-production-patterns`).

See [ADR-0006](decisions/0006-github-settings-manual.md) for the full decision record.

---

## CODEOWNERS

`CODEOWNERS` is stored at the root of the repository (`/CODEOWNERS`) and is enforced by GitHub automatically. It requires a code owner to approve any PR touching files they own.

Current configuration: `@markof88` owns all files (`*`).

On a team this would be broken out by area — platform team owns `.github/workflows/`, security team owns `Dockerfile`, etc.
