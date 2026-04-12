# ADR-0003: Use Docker Compose override pattern for environment-specific configuration

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

Local development and production environments have legitimately different requirements:

- **Production**: read-only filesystem, minimal capabilities, no debug ports, structured JSON logging, image pulled from registry
- **Development**: writable filesystem (for profiling output), verbose logging, debug ports exposed, image built from local source

A common anti-pattern is to maintain a single `docker-compose.yml` that tries to serve both purposes — either hardcoding dev conveniences that shouldn't exist in production-like validation, or making local development awkward to match a production-like spec.

---

## Decision

Maintain two Compose files:

- `docker-compose.yml` — production-like baseline. Describes the service as it would run in production: read-only filesystem, dropped capabilities, non-root user, production log level.
- `docker-compose.override.yml` — development overrides. Automatically merged by Docker Compose when no `-f` flag is specified. Adds dev conveniences without modifying the baseline.

---

## Rationale

### Docker Compose merges override files automatically
Running `docker compose up` without arguments causes Docker Compose to automatically merge `docker-compose.yml` and `docker-compose.override.yml`. This means:
- Developers get a good experience with zero extra flags
- The production-like baseline is tested by explicitly running `docker compose -f docker-compose.yml up`
- CI can validate the production configuration directly

### Separation of concerns
The baseline file is the contract: "this is how this service runs." The override file is developer ergonomics: "this is how I work on it locally." Keeping them separate makes both easier to reason about and review.

### Mirrors how Kubernetes handles environment differences
Kubernetes uses kustomize overlays or Helm values files to manage the same concern — a base spec and environment-specific patches. The Compose override pattern teaches the same mental model at a smaller scale and makes the transition to Kubernetes config management intuitive.

### Enables production-parity testing locally
A developer can validate how their service behaves under production constraints at any time:

```bash
# Dev mode (override applied automatically)
docker compose up

# Production-like validation (no override)
docker compose -f docker-compose.yml up
```

---

## Consequences

**Positive:**
- `docker-compose.yml` stays clean and reviewable as a production spec
- New developers get a working local environment with `docker compose up` and no additional setup
- The pattern is idiomatic and well-documented in Docker's official docs
- Production-like testing is one command away

**Negative / Trade-offs:**
- Two files to maintain instead of one — though the override file is typically short and stable
- Developers unfamiliar with the override pattern may not realise the two files are being merged, which can cause confusion when debugging

---

## Alternatives considered

| Option | Rejected because |
|---|---|
| Single `docker-compose.yml` with all config | Mixes production and dev concerns; production-like validation becomes difficult |
| Separate named files (`docker-compose.dev.yml`, `docker-compose.prod.yml`) | Requires explicit `-f` flags for every command; no automatic merge for dev workflow |
| Environment variables only | Doesn't cover structural differences (e.g. volume mounts, capability drops) that go beyond simple config values |
