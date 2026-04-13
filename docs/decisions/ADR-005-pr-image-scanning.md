# ADR-005: Scan the built image on PRs before pushing to registry

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

The pipeline needs to scan the Docker image for vulnerabilities before merging a PR. Two approaches are possible:

1. **Push to registry on PR, scan the pushed image** — simple scan step, but requires writing to the registry on every PR.
2. **Build locally (--load), scan the local daemon image** — no registry write on PR, but requires two separate builds on push (one here, one in publish).

---

## Decision

Use `--load` on PRs to pull the image into the local Docker daemon and scan it without pushing. On push to main/tags, the `publish` job performs the real build, push, and digest scan independently.

This means push events trigger **two builds**: one in `build` (multi-arch validation, no push) and one in `publish` (multi-arch, push + scan digest + sign).

---

## Rationale

### No registry writes on PRs

PRs are untrusted code. Writing to the registry on every PR — even untagged — increases the registry's attack surface and makes cleanup harder. With `--load`, nothing leaves the runner.

### Minimal permissions on PRs

The `build` job does not need `packages: write`. Keeping `packages: write` out of the PR path means a compromised PR workflow cannot push to the registry. The `publish` job, which has `packages: write`, only runs on `push` events (main/tags), never on PRs.

### Scan amd64 only on PRs

`--load` requires a single platform (Docker daemon is single-arch). PRs scan `linux/amd64` only. This is an acceptable trade-off:

- The Go binary is architecture-independent in terms of vulnerability surface (CVEs come from the base image layers, which are the same across arches from the same manifest)
- The distroless base image digest is pinned — the same digest is used for both arches
- Full multi-arch scanning happens in `publish` (scans the exact pushed digest)

### Double build on push is a deliberate trade-off

The `build` job validates the multi-arch build succeeds before `publish` runs. If `build` passes but `publish` fails (e.g., registry is down), we have not signed a broken image. The registry cache (`buildcache` tag, `mode=max`) means the second build is mostly a cache hit — the actual build time cost is small.

---

## Consequences

**Positive:**
- PRs never write to the registry
- `packages: write` is scoped only to the `publish` job
- Image vulnerabilities block PRs before any registry interaction
- Push path scans the exact digest that was pushed (tags are mutable, digests are not)

**Negative / Trade-offs:**
- Push events trigger two builds (build + publish)
- PR scan is amd64 only — arm64-specific vulnerabilities in the base image would not be caught until publish
- Slightly more complex pipeline than a single build-and-push job

---

## Alternatives considered

| Option | Rejected because |
|---|---|
| Push to registry on PR (untagged), scan, delete | Requires `packages: write` on PRs; cleanup is fragile |
| Skip image scan on PRs, only scan on push | CVEs in merged code are caught too late — after merge |
| Single build-push-scan-sign job | Cannot separate PR and push behavior; permissions cannot be scoped |
