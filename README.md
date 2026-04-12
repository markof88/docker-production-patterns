# docker-production-patterns

> Production-grade Docker patterns demonstrated through a minimal Go HTTP API.
> Part of a [DevOps portfolio](https://github.com/markof88) targeting real-world, operator-level practices.

---

## Why this exists

Most Docker tutorials stop at `docker run`. This repo shows what happens *after* — when you care about image size, attack surface, reproducibility, secrets, and supply chain integrity.

The Go app is intentionally small. It's a vehicle, not the point. The point is everything around it.

---

## Patterns covered

| Pattern | What it demonstrates |
|---|---|
| Multi-stage build | Separate build and runtime environments; minimal final image |
| Distroless base image | No shell, no package manager — reduced attack surface |
| Non-root user | Principle of least privilege inside the container |
| `.dockerignore` | Build context hygiene — don't leak secrets or bloat layers |
| Docker Compose (dev) | Local development ergonomics with override pattern |
| Health checks | Liveness and readiness separation (`/healthz`, `/readyz`) |
| Secret handling | Environment-based config, no hardcoded values, no secrets in image layers |
| Trivy scanning | Vulnerability scanning in CI — blocks on HIGH/CRITICAL |
| Image signing (cosign) | Supply chain integrity via keyless signing (Sigstore) |
| Makefile interface | Reproducible developer commands — no tribal knowledge required |

---

## Architecture

```
┌─────────────────────────────────────────────┐
│  GitHub Actions CI/CD                        │
│                                              │
│  push → build → test → trivy scan           │
│       → push to ghcr.io → cosign sign       │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
         ghcr.io/markof88/
         docker-production-patterns:sha-abc123
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  Container (distroless/nonroot)              │
│                                              │
│  GET /healthz  → liveness probe             │
│  GET /readyz   → readiness probe            │
│  GET /         → "Hello from container"     │
│                                             │
│  Listens on PORT (default: 8080)            │
└─────────────────────────────────────────────┘
```

---

## Local development

**Prerequisites:** Docker, Docker Compose, Go 1.22+, Make

```bash
# Build the image
make build

# Run with Docker Compose (dev mode with live reload via Air)
make dev

# Run production image locally
make run

# Scan for vulnerabilities
make scan

# Run tests
make test

# See all available commands
make help
```

---

## Image size comparison

| Stage | Base image | Size |
|---|---|---|
| Builder | `golang:1.22-alpine` | ~250 MB |
| Final | `gcr.io/distroless/static-debian12:nonroot` | ~4 MB |

The final image contains only the compiled binary and necessary CA certificates. No shell. No `apt`. No `wget`.

---

## Security properties

- **No shell**: `docker exec` into this container won't give you a shell — there isn't one
- **Non-root**: process runs as UID 65532 (distroless `nonroot` user)
- **Read-only filesystem**: enforced in Docker Compose and documented for Kubernetes
- **No secrets in layers**: all configuration via environment variables, no build-time secrets baked in
- **Signed image**: every pushed image is signed with cosign keyless signing (Sigstore OIDC)

Verify a signature:
```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/markof88/docker-production-patterns" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/markof88/docker-production-patterns:latest
```

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8080` | Port the server listens on |
| `APP_ENV` | `production` | Environment name (shown in /healthz response) |
| `LOG_LEVEL` | `info` | Log verbosity (`debug`, `info`, `warn`, `error`) |

---

## CI/CD pipeline

The GitHub Actions workflow (`.github/workflows/docker.yml`) runs on every push and pull request:

1. **Build** — multi-stage Docker build
2. **Test** — `go test ./...`
3. **Scan** — Trivy vulnerability scan (fails on HIGH or CRITICAL)
4. **Push** — to `ghcr.io/markof88/docker-production-patterns` (main branch only)
5. **Sign** — keyless cosign signature attached to the image manifest

---

## What I learned / decisions made

- **Distroless over Alpine**: Alpine has a shell and `apk`. Distroless has neither. For a compiled Go binary, there's no reason to include them.
- **Keyless signing**: No private key to rotate or leak. Sigstore ties the signature to the GitHub Actions OIDC token — the identity is the workflow, not a person.
- **`.dockerignore` matters**: Without it, `go.sum`, `.git`, and any local `.env` files end up in the build context. That's a potential secret leak and a slow build.
- **Override pattern for Compose**: `docker-compose.yml` is production-like. `docker-compose.override.yml` adds dev conveniences (volume mounts, debug env). This mirrors how teams manage environment-specific config.

---

## Project structure

```
docker-production-patterns/
├── .dockerignore
├── .github/
│   └── workflows/
│       └── docker.yml
├── Dockerfile
├── Makefile
├── README.md
├── docker-compose.yml
├── docker-compose.override.yml
├── trivy.yaml
├── go.mod
├── go.sum
└── main.go
```

---

## Part of a larger portfolio

This is Project 1 of 6 in a DevOps portfolio series:

| # | Repo | Focus |
|---|---|---|
| 1 | **docker-production-patterns** (this) | Container image hygiene, security, supply chain |
| 2 | `cicd-pipeline-templates` | GitHub Actions, semantic versioning, SBOM |
| 3 | `kubernetes-production-patterns` | Cluster design, RBAC, network policies, HPA |
| 4 | `gitops-platform` | Argo CD, App-of-Apps, image promotion |
| 5 | `observability-stack` | Prometheus, Grafana, Loki, SLOs |
| 6 | `internal-developer-platform` | Crossplane, Backstage, golden path templates |
