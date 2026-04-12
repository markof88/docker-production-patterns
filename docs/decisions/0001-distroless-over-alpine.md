# ADR-0001: Use distroless base image instead of Alpine for the final stage

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

When building a container image for a compiled Go binary, the final stage base image is one of the most consequential choices. The two most common options in production are:

- **Alpine Linux** (`alpine:3.x`) — a minimal Linux distribution with a package manager (`apk`) and a shell (`/bin/sh`)
- **Distroless** (`gcr.io/distroless/static-debian13`) — a Google-maintained base with no shell, no package manager, and only the bare minimum OS libraries

A compiled Go binary with `CGO_ENABLED=0` produces a fully static executable that has no runtime dependencies on shared libraries. It does not need a shell, a package manager, or any OS utilities to run.

---

## Decision

Use `gcr.io/distroless/static-debian13:nonroot` as the base image for the final stage.

---

## Rationale

### Attack surface reduction
Alpine's shell and package manager exist so humans and scripts can interact with the OS. In a production container, this is unnecessary — and dangerous. If an attacker achieves remote code execution inside a container, a shell gives them a powerful foothold. Distroless removes that entirely.

### CVE exposure
Every package in a container image is a potential source of CVEs. Alpine, even at minimal size, includes busybox, musl libc, and apk tooling. Each of these can carry vulnerabilities. Distroless's static variant contains essentially nothing except CA certificates and timezone data — dramatically reducing the vulnerability surface Trivy and other scanners need to track.

### Image size
| Base image | Approximate size |
|---|---|
| `alpine:3.x` | ~7 MB |
| `gcr.io/distroless/static-debian13:nonroot` | ~2 MB |

The final application image (binary + distroless base) is approximately 4–5 MB.

### Principle of least privilege — at the image level
The `:nonroot` tag runs the process as UID 65532 by default, with no capability to escalate privileges. There is no `sudo`, no `su`, no setuid binaries.

### Supply chain trust
Distroless images are built and signed by Google, with published provenance. The digest pinning in `FROM gcr.io/distroless/static-debian13:nonroot@sha256:...` (used in production deployments) ensures the exact layer contents are verified at pull time.

---

## Consequences

**Positive:**
- Trivy scans report significantly fewer CVEs — mostly zero for the final image
- No shell means `docker exec -it <container> /bin/sh` fails by design
- Image size is minimized
- Passes strict CIS benchmark and NSA/CISA Kubernetes hardening checks for container image hygiene

**Negative / Trade-offs:**
- Debugging is harder — you cannot exec into the container and poke around. This is by design, but requires teams to rely on logs and external tooling (e.g. ephemeral debug containers in Kubernetes via `kubectl debug`)
- The builder stage still uses Alpine (for `apk add ca-certificates`) — this is intentional and acceptable since the builder stage never runs in production

---

## Alternatives considered

| Option | Rejected because |
|---|---|
| `scratch` | No CA certificates included — HTTPS calls fail without manual copy |
| `alpine:3.x` final stage | Shell and package manager present — unnecessary attack surface |
| `debian:slim` | Larger than distroless, includes apt and shell |
| `chainguard/static` | Viable alternative with similar properties, but distroless has broader adoption and documentation |
