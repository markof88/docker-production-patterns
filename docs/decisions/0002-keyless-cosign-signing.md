# ADR-0002: Use keyless cosign signing via Sigstore instead of traditional key-based signing

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

Container image signing proves that a given image was produced by a specific, trusted process — and has not been tampered with between publication and deployment. Without signing, an attacker who compromises a registry could substitute a malicious image and consumers would have no way to detect it.

There are two main approaches to signing container images:

- **Key-based signing**: A private key is used to sign images. The public key is distributed to verifiers. Common tools: Docker Content Trust (Notary), cosign with generated key pairs.
- **Keyless signing** (Sigstore / OIDC-based): No long-lived private key exists. Instead, the signer proves their identity via a short-lived OIDC token (e.g. from GitHub Actions), and the signature is tied to that identity. The Sigstore transparency log (Rekor) provides an auditable record.

---

## Decision

Use cosign keyless signing with the Sigstore public infrastructure (Fulcio CA + Rekor transparency log). No private key is generated, stored, or managed.

---

## Rationale

### The private key problem
Key-based signing shifts the security problem rather than solving it. A private key must be:
- Generated securely
- Stored securely (typically as a CI secret)
- Rotated when compromised or on a schedule
- Revoked and re-signed if leaked

Each of these steps is a failure opportunity. CI secrets can be exfiltrated via malicious PRs, supply chain attacks on workflow dependencies, or misconfiguration. A leaked signing key silently invalidates all past and future signing guarantees.

### Keyless signing ties identity to the workflow, not a key
With keyless signing, the signature asserts: *"this image was signed by a GitHub Actions workflow run at `https://github.com/markof88/docker-production-patterns/.github/workflows/docker.yml`, triggered by a push to `main`."*

This is verifiable by anyone:

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/markof88/docker-production-patterns" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/markof88/docker-production-patterns:latest
```

The identity is the CI system itself — not a secret that can be stolen.

### Transparency log provides non-repudiation
Every signature is recorded in Rekor, a public, append-only transparency log. This means:
- Signatures can be audited independently of the registry
- Compromised signatures can be detected even if the registry is tampered with
- There is a verifiable, timestamped record of when each image was signed

### Zero operational overhead
No key rotation schedule. No secret management. No revocation procedure. The GitHub Actions OIDC token is ephemeral — it exists only for the duration of the workflow run and is useless afterward.

---

## Consequences

**Positive:**
- No private key to manage, rotate, or lose
- Signatures are cryptographically tied to the specific workflow and branch that produced them
- Verification is self-contained and doesn't require distributing a public key
- Sigstore is a CNCF project with broad ecosystem adoption (used by Kubernetes, Tekton, and others)

**Negative / Trade-offs:**
- Requires network access to Sigstore public infrastructure (Fulcio, Rekor) during signing — not suitable for fully air-gapped environments
- For air-gapped environments, a self-hosted Sigstore stack (or key-based signing) would be required
- The Sigstore public infrastructure is a trusted third party — though the transparency log means any tampering would be publicly detectable

---

## Alternatives considered

| Option | Rejected because |
|---|---|
| cosign with generated key pair | Requires private key management — the problem we're trying to avoid |
| Docker Content Trust (Notary v1) | Legacy, complex key hierarchy, poor CI integration |
| Notary v2 | Still maturing, less tooling ecosystem than cosign |
| No signing | Acceptable for experiments; not acceptable for production-grade portfolio demonstration |
