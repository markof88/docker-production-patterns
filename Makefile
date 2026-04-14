# Makefile — developer interface for docker-production-patterns
#
# Philosophy: every operation someone might run is a make target.
# No tribal knowledge. New team member runs `make help` and knows everything.
#
# Requirements: Docker, Docker Compose, Go 1.22+, trivy, cosign (for signing)

REGISTRY   := ghcr.io
OWNER      := markof88
IMAGE_NAME := docker-production-patterns
IMAGE      := $(REGISTRY)/$(OWNER)/$(IMAGE_NAME)

# Derive version from git. Falls back to "dev" outside a git repo.
VERSION    := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
# Short SHA for tagging — useful for immutable image references.
SHORT_SHA  := $(shell git rev-parse --short HEAD 2>/dev/null || echo 0000000)

# Platform to build for. Override with: make build PLATFORM=linux/arm64
PLATFORM   := linux/amd64

.DEFAULT_GOAL := help

# ─────────────────────────────────────────────
# Help target — auto-generates from ## comments
# ─────────────────────────────────────────────
.PHONY: help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ─────────────────────────────────────────────
# Go targets
# ─────────────────────────────────────────────
.PHONY: tidy
tidy: ## Tidy and verify Go modules
	go mod tidy
	go mod verify

.PHONY: test
test: ## Run Go tests with race detector
	go test -race -count=1 ./...

.PHONY: lint
lint: ## Run golangci-lint (requires golangci-lint installed)
	golangci-lint run ./...

.PHONY: lint-dockerfile
lint-dockerfile: ## Lint Dockerfile with hadolint (uses Docker — no local install needed)
	docker run --rm \
		-v $(PWD):/work -w /work \
		hadolint/hadolint hadolint --config .hadolint.yaml Dockerfile

# ─────────────────────────────────────────────
# Docker targets
# ─────────────────────────────────────────────
.PHONY: build
build: ## Build the Docker image (multi-stage, distroless)
	docker build \
		--platform $(PLATFORM) \
		--pull \
		--build-arg BUILDKIT_INLINE_CACHE=1 \
		--build-arg VERSION=$(VERSION) \
		--label "org.opencontainers.image.version=$(VERSION)" \
		--label "org.opencontainers.image.revision=$(SHORT_SHA)" \
		--label "org.opencontainers.image.source=https://github.com/$(OWNER)/$(IMAGE_NAME)" \
		-t $(IMAGE):$(SHORT_SHA) \
		-t $(IMAGE):latest \
		.
	@echo ""
	@echo "Built: $(IMAGE):$(SHORT_SHA)"
	@docker images $(IMAGE) --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

.PHONY: run
run: ## Run the production image locally
	docker run --rm \
		--read-only \
		--cap-drop ALL \
		--security-opt no-new-privileges:true \
		-p 8080:8080 \
		-e APP_ENV=local \
		$(IMAGE):latest

.PHONY: dev
dev: ## Start local dev environment with Docker Compose (auto-merges override)
	docker compose up --build

.PHONY: dev-down
dev-down: ## Stop local dev environment
	docker compose down

.PHONY: shell
shell: ## Open a shell in the BUILDER stage (distroless has no shell)
	docker run --rm -it \
		--entrypoint /bin/sh \
		$(shell docker build -q --target builder .)

# ─────────────────────────────────────────────
# Security targets
# ─────────────────────────────────────────────
.PHONY: scan
scan: ## Scan the image for vulnerabilities with Trivy
	trivy image \
		--config trivy.yaml \
		$(IMAGE):latest

.PHONY: scan-sarif
scan-sarif: ## Scan and output SARIF report (for GitHub Security tab)
	trivy image \
		--config trivy.yaml \
		--format sarif \
		--output trivy-results.sarif \
		$(IMAGE):latest

.PHONY: sign
sign: ## Sign the image with cosign (keyless — requires OIDC context)
	cosign sign --yes $(IMAGE):$(SHORT_SHA)

.PHONY: verify
verify: ## Verify the cosign signature on the latest image
	cosign verify \
		--certificate-identity-regexp="https://github.com/$(OWNER)/$(IMAGE_NAME)" \
		--certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
		$(IMAGE):latest

# ─────────────────────────────────────────────
# CI/Release targets
# ─────────────────────────────────────────────
.PHONY: push
push: ## Push image to registry (requires docker login)
	docker push $(IMAGE):$(SHORT_SHA)
	docker push $(IMAGE):latest

.PHONY: ci
ci: tidy test build scan ## Full CI pipeline locally (tidy → test → build → scan)
	@echo ""
	@echo "Local CI passed. Image: $(IMAGE):$(SHORT_SHA)"

# ─────────────────────────────────────────────
# Utility
# ─────────────────────────────────────────────
.PHONY: version
version: ## Print the current version/SHA
	@echo "Version: $(VERSION)"
	@echo "SHA:     $(SHORT_SHA)"
	@echo "Image:   $(IMAGE):$(SHORT_SHA)"

.PHONY: clean
clean: ## Remove local build artifacts and dangling images
	docker image prune -f
	rm -f trivy-results.sarif
