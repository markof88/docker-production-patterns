# syntax=docker/dockerfile:1
# ─────────────────────────────────────────────
# Stage 1: Build
# Uses the full Go toolchain. Nothing from this
# stage ends up in the final image.
#
# Digest pinning: for maximum supply chain integrity, pin both stages
# to their exact digest using @sha256:<digest>. Get the digest with:
#   docker pull golang:1.26.2-alpine3.23
#   docker inspect --format='{{index .RepoDigests 0}}' golang:1.26.2-alpine3.23
# Then replace the FROM line with the digest-pinned version.
# ─────────────────────────────────────────────
FROM golang:1.26.2-alpine3.23 AS builder

# Install ca-certificates so we can copy them to the final image.
# The distroless image includes them, but being explicit is clearer.
RUN apk add --no-cache ca-certificates tzdata

WORKDIR /build

# Copy dependency files first — Docker layer caching means this layer
# is only invalidated when go.mod or go.sum changes, not on every code change.
COPY go.mod go.sum ./
RUN go mod download

# VERSION is injected by CI via --build-arg. Falls back to "dev" for local builds.
# Using a build arg instead of git describe avoids issues with shallow CI clones.
ARG VERSION=dev

# Copy source and build.
# CGO_ENABLED=0   → fully static binary (no libc dependency)
# -trimpath       → remove local filesystem paths from the binary
# -ldflags        → strip debug info (-s -w) and inject version
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -trimpath \
    -ldflags="-s -w -X main.appVersion=${VERSION}" \
    -o /app \
    ./...

# ─────────────────────────────────────────────
# Stage 2: Final image
# gcr.io/distroless/static-debian13:nonroot
#   • No shell, no package manager
#   • Runs as UID 65532 (nonroot) by default
#   • ~4 MB total image size
#   • Debian 13 (Trixie) — newer packages, fewer CVEs than debian12
# ─────────────────────────────────────────────
FROM gcr.io/distroless/static-debian13:nonroot@sha256:e3f945647ffb95b5839c07038d64f9811adf17308b9121d8a2b87b6a22a80a39

# Copy only what the binary needs at runtime.
# --chown makes ownership explicit and auditable.
COPY --from=builder --chown=65532:65532 /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder --chown=65532:65532 /app /app

# Document the port (does not publish it — that's done at runtime).
EXPOSE 8080

# Distroless nonroot already sets USER to 65532.
# Being explicit here makes it visible in the Dockerfile and auditable.
USER nonroot:nonroot

# Health check — Kubernetes will use its own probes, but this is useful
# for `docker run` and docker-compose environments.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/app", "-healthcheck"]

ENTRYPOINT ["/app"]
