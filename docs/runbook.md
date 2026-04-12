# Runbook

Day-2 operations for `docker-production-patterns`.

---

## Local development

### Start dev environment
```bash
make dev
```
Docker Compose automatically merges `docker-compose.override.yml` — debug logging, writable filesystem, pprof port exposed.

### Run production-like locally
```bash
make build
make run
```

### Run tests
```bash
make test
```

### Full local CI pipeline
```bash
make ci
```
Runs: `go mod tidy` → `go test` → `docker build` → `trivy scan`

---

## Image operations

### Pull the latest image
```bash
docker pull ghcr.io/markof88/docker-production-patterns:latest
```

### Verify the cosign signature
```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/markof88/docker-production-patterns" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/markof88/docker-production-patterns:latest
```
Expected output: `Verified OK` with the signing workflow details.

### Check image layers and labels
```bash
docker inspect ghcr.io/markof88/docker-production-patterns:latest
```

---

## Updating the base image

When a new Debian or Go version is released:

1. Update `Dockerfile`:
   - Builder: `FROM golang:X.Y.Z-alpineA.B AS builder`
   - Final: `FROM gcr.io/distroless/static-debianNN:nonroot`

2. Update `go.mod`:
   ```
   go X.Y
   ```

3. Update the badge in `README.md`.

4. Update references in `docs/decisions/0004-multi-stage-build.md`.

5. Push — CI will build, scan, and sign the updated image automatically.

### Pinning to a digest (recommended for production)

After updating the base image, get the exact digest and pin it:

```bash
docker pull golang:1.26.2-alpine3.23
docker inspect --format='{{index .RepoDigests 0}}' golang:1.26.2-alpine3.23
# → golang@sha256:<digest>

docker pull gcr.io/distroless/static-debian13:nonroot
docker inspect --format='{{index .RepoDigests 0}}' gcr.io/distroless/static-debian13:nonroot
# → gcr.io/distroless/static-debian13@sha256:<digest>
```

Then update `Dockerfile`:
```dockerfile
FROM golang:1.26.2-alpine3.23@sha256:<digest> AS builder
FROM gcr.io/distroless/static-debian13:nonroot@sha256:<digest>
```

---

## Vulnerability management

### Scan the image locally
```bash
make scan
```

### Review findings in GitHub
Go to **Security → Code scanning** in the GitHub repo. Trivy uploads SARIF results on every push to main.

### Ignoring a CVE

If a CVE has no fix available and you've assessed the risk:

1. Add it to `.trivyignore` (create if it doesn't exist):
   ```
   # CVE-YYYY-NNNNN — <reason: no fix available / mitigated by network policy / etc>
   CVE-YYYY-NNNNN
   ```

2. Reference `.trivyignore` in `trivy.yaml`:
   ```yaml
   ignorefile: .trivyignore
   ```

3. Commit with a clear message explaining the accepted risk.

---

## Releasing a new version

1. Tag the commit:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. CI automatically:
   - Builds the image
   - Tags it `:1.0.0`, `:1.0`, `:1`, `:latest`
   - Signs it with cosign
   - Uploads Trivy results to the Security tab

---

## Troubleshooting

### Container won't start

Check if the binary is the right architecture:
```bash
docker run --rm --entrypoint="" ghcr.io/markof88/docker-production-patterns:latest \
  /bin/sh -c "file /app"
# Will fail — distroless has no shell. Use the builder stage instead:
docker build --target builder -t debug-builder .
docker run --rm debug-builder file /app
```

### Health check failing

The binary itself acts as the health check client:
```bash
# Test the health endpoint directly
curl http://localhost:8080/healthz
```

Expected response:
```json
{"status":"ok","env":"production","version":"v1.0.0"}
```

### Viewing logs

The application logs in JSON format. Use `jq` to pretty-print:
```bash
docker logs <container-id> | jq .
```

### Debugging without a shell

Since distroless has no shell, use Kubernetes ephemeral debug containers for production debugging:
```bash
kubectl debug -it <pod-name> --image=busybox --target=app
```
