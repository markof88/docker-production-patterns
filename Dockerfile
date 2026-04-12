# syntax=docker/dockerfile:1
# ─────────────────────────────────────────────
# Stage 1: Build
# Uses the full Go toolchain. Nothing from this
# stage ends up in the final image.
# ─────────────────────────────────────────────
FROM golang:1.22-alpine AS builder

# Install ca-certificates so we can copy them to the final image.
# The distroless image includes them, but being explicit is clearer.
RUN apk add --no-cache ca-certificates tzdata

WORKDIR /build

# Copy dependency files first — Docker layer caching means this layer
# is only invalidated when go.mod or go.sum changes, not on every code change.
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build.
# CGO_ENABLED=0   → fully static binary (no libc dependency)
# -trimpath       → remove local filesystem paths from the binary
# -ldflags        → strip debug info (-s -w) and inject version
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -trimpath \
    -ldflags="-s -w -X main.appVersion=$(git describe --tags --always --dirty 2>/dev/null || echo dev)" \
    -o /app \
    ./...

# ─────────────────────────────────────────────
# Stage 2: Final image
# gcr.io/distroless/static-debian12:nonroot
#   • No shell, no package manager, no libc
#   • Runs as UID 65532 (nonroot) by default
#   • ~4 MB total image size
# ─────────────────────────────────────────────
FROM gcr.io/distroless/static-debian12:nonroot

# Copy only what the binary needs at runtime.
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app /app

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
