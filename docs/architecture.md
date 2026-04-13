# Architecture

## Overview

This repository demonstrates production-grade Docker patterns using a minimal Go HTTP API as the vehicle. The application itself is intentionally simple — the architectural interest is in the image build pipeline, security posture, and CI/CD flow surrounding it.

---

## Component diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  Developer workstation                                           │
│                                                                  │
│  $ make build       → builds multi-stage image locally          │
│  $ make dev         → starts docker-compose (override applied)  │
│  $ make scan        → runs trivy against local image            │
│  $ make ci          → full local pipeline (tidy/test/build/scan)│
└──────────────────────────┬──────────────────────────────────────┘
                           │ git push
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Actions — .github/workflows/docker.yml                  │
│                                                                  │
│  ┌─────────┐    ┌──────────────────────────────────────────┐   │
│  │  test   │    │  build                                    │   │
│  │         │    │                                           │   │
│  │ go test │───▶│ 1. go mod tidy  (generate go.sum)        │   │
│  │  -race  │    │ 2. docker buildx build (multi-platform)  │   │
│  └─────────┘    │    linux/amd64 + linux/arm64             │   │
│                 │ 3. push → ghcr.io (main branch only)     │   │
│                 │ 4. trivy scan → GitHub Security tab      │   │
│                 │ 5. cosign sign (keyless, OIDC)           │   │
│                 └──────────────────────┬──────────────────┘   │
└────────────────────────────────────────┼────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Container Registry (ghcr.io)                            │
│                                                                  │
│  ghcr.io/markof88/docker-production-patterns                    │
│    :latest          → most recent main branch build             │
│    :main            → main branch (same as latest)              │
│    :sha-<short>     → immutable reference by commit SHA         │
│    :v1.2.3          → semver tag (on git tag push)              │
│    :buildcache      → BuildKit layer cache (not a runnable image│
└─────────────────────────────────────────────────────────────────┘
```

---

## Image build — multi-stage detail

```
Dockerfile
│
├── Stage 1: builder (golang:1.22-alpine)
│   │
│   ├── apk add ca-certificates tzdata
│   ├── COPY go.mod go.sum          ← layer cached until deps change
│   ├── go mod download             ← cached unless go.mod/go.sum change
│   ├── COPY . .                    ← invalidated on any source change
│   └── go build (CGO_ENABLED=0)   ← static binary, ~8 MB
│       -trimpath                   ← reproducible, no path leakage
│       -ldflags "-s -w"            ← strip debug info, ~30% smaller
│
└── Stage 2: final (distroless/static-debian13:nonroot)
    │
    ├── COPY ca-certificates        ← from builder
    ├── COPY /app                   ← binary only, nothing else
    ├── USER nonroot:nonroot        ← UID 65532, no privilege escalation
    └── ENTRYPOINT ["/app"]

Final image contents:
  - /app                  (the Go binary)
  - /etc/ssl/certs/       (CA certificates for HTTPS)
  - distroless base       (~2 MB, no shell, no package manager)

Total image size: ~4–5 MB
```

---

## Security layers

| Layer | Mechanism | What it prevents |
|---|---|---|
| No shell in image | Distroless base | Post-exploitation foothold |
| Non-root user | UID 65532 (`nonroot`) | Privilege escalation inside container |
| Read-only filesystem | `read_only: true` in Compose | Malicious writes at runtime |
| Dropped capabilities | `cap_drop: ALL` | Linux kernel exploit surface |
| No new privileges | `no-new-privileges:true` | setuid binary exploitation |
| Static binary | `CGO_ENABLED=0` | No dynamic linker dependency |
| Vulnerability scanning | Trivy in CI | Known CVE detection before deployment |
| Image signing | cosign keyless | Supply chain tampering detection |
| SBOM generation | BuildKit + syft | Dependency inventory and audit trail |

---

## Local development vs production

The Compose override pattern keeps the two configurations cleanly separated:

```
docker-compose.yml              docker-compose.override.yml
(production-like baseline)      (dev conveniences, auto-merged)
─────────────────────────       ──────────────────────────────
read_only: true                 read_only: false
LOG_LEVEL: info                 LOG_LEVEL: debug
APP_ENV: production             APP_ENV: development
cap_drop: ALL                   (inherited)
image from registry             build from local source
port 8080                       port 8080 + 6060 (pprof)
```

Run production-like locally:
```bash
docker compose -f docker-compose.yml up
```

Run dev mode (override auto-applied):
```bash
docker compose up
```

---

## API endpoints

| Endpoint | Method | Purpose | Used by |
|---|---|---|---|
| `/healthz` | GET | Liveness probe — is the process alive? | Kubernetes liveness probe, Docker HEALTHCHECK |
| `/readyz` | GET | Readiness probe — is it ready for traffic? | Kubernetes readiness probe, load balancer health check |
| `/` | GET | Application endpoint | Clients |

Response format: JSON. Structured logging via `log/slog` (JSON output in production).

---

## CI/CD pipeline — job dependency

```
   prepare ─┐
             ├──▶ scan-source ──▶ build ──▶ publish
   test    ─┘
```

| Job | Runs on | What it does |
|---|---|---|
| `prepare` | all events | Computes image tags/labels from GitHub context. No checkout needed. |
| `test` | all events | `go mod tidy && git diff --exit-code`, then `go test -race` |
| `scan-source` | after prepare + test | Trivy filesystem scan on source and config files. Blocks on HIGH/CRITICAL. |
| `build` | after scan-source | **PR:** builds `linux/amd64` with `--load`, scans local image with Trivy. **Push:** builds multi-arch (no push) to validate the build. |
| `publish` | push to main/tags only | Rebuilds multi-arch, pushes to ghcr.io, scans the exact pushed digest, signs with cosign. |

**PR vs push behaviour:**
- PRs scan a locally loaded image — no registry write, no `packages: write` permission on PRs.
- Push events trigger two builds (build + publish). This is deliberate — see [ADR-005](decisions/ADR-005-pr-image-scanning.md).
- The publish job always scans the digest (not the tag) — digests are immutable, tags are not.

---

## Further reading

- [ADR-0001](decisions/0001-distroless-over-alpine.md) — Why distroless over Alpine
- [ADR-0002](decisions/0002-keyless-cosign-signing.md) — Why keyless cosign signing
- [ADR-0003](decisions/0003-compose-override-pattern.md) — Why the Compose override pattern
- [ADR-0004](decisions/0004-multi-stage-build.md) — Why multi-stage builds
- [ADR-005](decisions/ADR-005-pr-image-scanning.md) — Why PRs scan locally (--load) and push triggers two builds
- [Runbook](runbook.md) — Day-2 operations
