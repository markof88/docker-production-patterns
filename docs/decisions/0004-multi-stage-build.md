# ADR-0004: Use multi-stage Docker builds to separate build and runtime environments

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

A naive Dockerfile installs build tools (Go compiler, git, make), compiles the application, and ships everything in a single image layer. This results in images that are hundreds of megabytes in size and contain tools that have no role at runtime — every one of which is a potential attack vector and a source of CVEs.

---

## Decision

Use a two-stage Dockerfile:

1. **Builder stage** (`golang:1.26.2-alpine3.23`): Contains the full Go toolchain. Compiles a fully static binary with `CGO_ENABLED=0`.
2. **Final stage** (`gcr.io/distroless/static-debian13:nonroot`): Contains only the compiled binary and CA certificates. The Go toolchain is discarded entirely.

---

## Rationale

### The final image contains only what runs in production
The Go compiler, `apk`, `git`, and all build-time tooling exist only in the builder stage. Docker's multi-stage build discards every layer from previous stages that isn't explicitly copied forward. The final image contains:

- The compiled binary (~8 MB)
- CA certificates (for outbound HTTPS calls)
- Distroless base (~2 MB)

Nothing else.

### Layer caching strategy maximises build speed
Dependencies change less often than application code. The Dockerfile is ordered to exploit this:

```dockerfile
COPY go.mod go.sum ./   # invalidated only when dependencies change
RUN go mod download     # cached unless go.mod/go.sum change

COPY . .                # invalidated on any source change
RUN go build ...        # only re-runs when source changes
```

This means a typical code change triggers only the last two layers — `go mod download` and the base image pull are served from cache.

### Static binary enables distroless
`CGO_ENABLED=0` produces a binary with no dependency on the host's C library. This is what allows the final stage to use a distroless base with no libc — the binary carries everything it needs.

`-trimpath` removes references to the build machine's filesystem paths from the binary, making builds reproducible across different machines and preventing path leakage in stack traces.

`-ldflags="-s -w"` strips the symbol table and DWARF debug information, reducing binary size by approximately 30% with no impact on runtime behavior.

---

## Consequences

**Positive:**
- Final image is ~4–5 MB instead of ~350 MB (with full Go toolchain)
- Build tools are provably absent from the production image — verifiable with `docker inspect`
- Trivy scans the final image only, not the build environment
- Build times remain fast due to layer caching on dependency installation

**Negative / Trade-offs:**
- Slightly more complex Dockerfile than a single-stage build
- Debugging requires targeting the builder stage explicitly: `docker build --target builder` and execing into it
- The builder stage uses Alpine (which has a shell) — this is acceptable because the builder stage is never deployed

---

## Alternatives considered

| Option | Rejected because |
|---|---|
| Single-stage with `golang:alpine` | Ships the Go toolchain in the production image — ~350 MB and high CVE surface |
| Single-stage with `scratch` | No CA certificates — outbound HTTPS fails without manual management |
| Build binary outside Docker, `COPY` into image | Breaks reproducibility — the build environment is not containerised or version-controlled |
