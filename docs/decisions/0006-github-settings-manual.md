# ADR-0006: GitHub repository settings managed manually, not via Terraform

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Branch protection rules, repository settings, and webhook configurations live in GitHub's API — not in the repository itself. They are invisible to `git clone`, disappear on repository recreation, and cannot be audited through code review.

They can be managed programmatically via:
- The [Terraform GitHub provider](https://registry.terraform.io/providers/integrations/github/latest/docs) (`github_branch_protection`, `github_repository` resources)
- The [GitHub API](https://docs.github.com/en/rest/branches/branch-protection) directly

---

## Decision

For this project, GitHub settings are documented in [`docs/github-settings.md`](../github-settings.md) rather than managed via Terraform. The settings are applied manually once and kept in sync through documentation.

---

## Rationale

This is a single portfolio repository, not a platform managing dozens of repos. Introducing Terraform for GitHub settings would require:

- A Terraform state backend (S3, GCS, or Terraform Cloud)
- A GitHub personal access token or GitHub App with admin scope stored as a secret
- A separate apply pipeline or local apply workflow
- State drift detection

The operational overhead is not proportional to the benefit for a single repo.

The documentation approach is a deliberate, understood trade-off — not an oversight.

---

## Consequences

**Positive:**
- No additional tooling or secrets required
- Settings are human-readable and reviewable in the repository
- New contributors understand the configuration without needing Terraform knowledge

**Negative:**
- Settings are not automatically applied on repository recreation
- Drift between documentation and actual GitHub configuration is possible and not automatically detected
- Does not scale to a multi-repository platform

---

## Future consideration

For a multi-repository platform — managing tens or hundreds of repositories with consistent branch protection, rulesets, and webhook configuration — the Terraform GitHub provider is the correct approach. Settings become versioned, peer-reviewed infrastructure, applied automatically via CI.

This is the approach demonstrated in Project 3 (`kubernetes-production-patterns`), where platform-level configuration is managed as code from the start.
