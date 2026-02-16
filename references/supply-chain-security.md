# Supply Chain Security Reference

## Overview

The Trusted Software Supply Chain (TSSC) on this cluster provides:
- **Trusted Artifact Signer (TAS)** — Sigstore-based artifact signing (cosign, Rekor, Fulcio)
- **Trusted Profile Analyzer (TPA)** — SBOM analysis, vulnerability scanning, VEX advisories
- **Tekton Chains** — Automatic pipeline attestation and provenance
- **Enterprise Contract** — Policy-as-code for supply chain compliance

Together these deliver **SLSA Level 3** compliance out of the box.

## Architecture

```
Developer Hub scaffold
  → Tekton Pipeline builds container image
    → Tekton Chains creates SLSA provenance attestation
      → TAS signs the image + attestation (cosign + Rekor transparency log)
        → TPA analyzes SBOM for vulnerabilities
          → Enterprise Contract verifies all policies pass
            → ArgoCD deploys (only if all checks pass)
```

## Trusted Artifact Signer (TAS)

**Namespace:** `trusted-artifact-signer` (or `rhtas-operator`)

TAS deploys the full Sigstore stack on-cluster:
- **Fulcio** — Certificate authority for keyless signing
- **Rekor** — Transparency log (tamper-proof audit trail)
- **CTLog** — Certificate Transparency log
- **TUF** — Trust root distribution

### Check TAS Health

```bash
# All TAS pods
oc get pods -n trusted-artifact-signer

# Check Securesign CR
oc get securesign -n trusted-artifact-signer -o jsonpath='{.items[0].status.conditions[*].type}={.items[0].status.conditions[*].status}'

# Get Rekor and Fulcio routes
oc get routes -n trusted-artifact-signer -o custom-columns='NAME:.metadata.name,HOST:.spec.host'
```

### Sign an Image Manually

```bash
REKOR_URL="https://$(oc get route -n trusted-artifact-signer rekor-server -o jsonpath='{.spec.host}')"
FULCIO_URL="https://$(oc get route -n trusted-artifact-signer fulcio-server -o jsonpath='{.spec.host}')"

# Keyless signing (uses OIDC identity)
cosign sign --rekor-url="${REKOR_URL}" \
  --fulcio-url="${FULCIO_URL}" \
  --oidc-issuer="https://oauth-openshift.apps.salamander.aimlworkbench.com" \
  <image>@<digest>
```

### Verify a Signature

```bash
cosign verify \
  --rekor-url="${REKOR_URL}" \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  <image>@<digest>
```

### Check Rekor Transparency Log

```bash
# Search for entries by image digest
rekor-cli search --rekor_server="${REKOR_URL}" --sha="${DIGEST}"

# Get entry details
rekor-cli get --rekor_server="${REKOR_URL}" --uuid=<entry-uuid> --format=json | jq .
```

## Trusted Profile Analyzer (TPA)

**Namespace:** `trustification` (or `tpa`)

TPA provides:
- SBOM ingestion and storage
- Vulnerability matching against Red Hat security data
- VEX (Vulnerability Exploitability eXchange) advisories
- Package provenance analysis

### Check TPA Health

```bash
oc get pods -n trustification

# Check TPA routes
oc get routes -n trustification -o custom-columns='NAME:.metadata.name,HOST:.spec.host'
```

### Query Vulnerabilities

```bash
TPA_URL="https://$(oc get route -n trustification vexination-api -o jsonpath='{.spec.host}' 2>/dev/null || echo 'TPA_NOT_FOUND')"

# Search for CVEs affecting a package
curl -s "${TPA_URL}/api/v1/vex?cve=CVE-2024-1234" | jq '.vulnerabilities'

# Get SBOM for an image
BOMBASTIC_URL="https://$(oc get route -n trustification bombastic-api -o jsonpath='{.spec.host}')"
curl -s "${BOMBASTIC_URL}/api/v1/sbom?purl=pkg:oci/myapp@sha256:abc123" | jq '.components | length'
```

### Upload an SBOM

```bash
# Generate SBOM with syft
syft <image> -o cyclonedx-json > sbom.json

# Upload to TPA
curl -X POST "${BOMBASTIC_URL}/api/v1/sbom" \
  -H "Content-Type: application/json" \
  -d @sbom.json
```

## Tekton Chains

Tekton Chains automatically signs TaskRun results and generates SLSA provenance attestations.

### Check Chains Configuration

```bash
# Verify Chains is enabled
oc get tektonconfig -o jsonpath='{.items[0].spec.chain}' | jq .

# Check Chains controller
oc get pods -n openshift-pipelines -l app=tekton-chains-controller

# Check signing configuration
oc get configmap -n openshift-pipelines chains-config -o yaml
```

### Verify Pipeline Attestations

```bash
# Check if taskruns are signed
oc get taskrun -n <namespace> -l tekton.dev/pipelineRun=<run-name> \
  -o jsonpath='{range .items[*]}{.metadata.name}: signed={.metadata.annotations.chains\.tekton\.dev/signed}{"\n"}{end}'

# Get the attestation payload
oc get taskrun <taskrun-name> -n <namespace> \
  -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/payload-taskrun-*}' | base64 -d | jq .

# Verify the signature
oc get taskrun <taskrun-name> -n <namespace> \
  -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signature-taskrun-*}' > sig.base64
```

### Pipeline Results to Check

After a TSSC pipeline run, verify these results:

```bash
oc get pipelinerun <name> -n <ns> -o json | jq '.status.results[] | {name: .name, value: .value}'
```

Expected results:
| Result | Description |
|---|---|
| `IMAGE_URL` | Built container image URL |
| `IMAGE_DIGEST` | Image digest (sha256) |
| `CHAINS-GIT_URL` | Source repository |
| `CHAINS-GIT_COMMIT` | Source commit SHA |
| `SBOM_BLOB_URL` | SBOM storage location |

## Enterprise Contract

Enterprise Contract validates that artifacts meet organizational policies before deployment.

```bash
# Check EC policy
oc get enterprisecontractpolicy -A

# Run EC verification manually
ec validate image --image <image>@<digest> \
  --policy "oci::quay.io/enterprise-contract/config:latest" \
  --rekor-url "${REKOR_URL}" \
  --public-key k8s://openshift-pipelines/signing-secrets
```

## Full Verification Workflow

Complete verification of a pipeline-built artifact:

```bash
# 1. Get image details from pipeline run
PIPELINERUN="<run-name>"
NAMESPACE="<namespace>"

IMAGE=$(oc get pipelinerun ${PIPELINERUN} -n ${NAMESPACE} \
  -o jsonpath='{.status.results[?(@.name=="IMAGE_URL")].value}')
DIGEST=$(oc get pipelinerun ${PIPELINERUN} -n ${NAMESPACE} \
  -o jsonpath='{.status.results[?(@.name=="IMAGE_DIGEST")].value}')

echo "Image: ${IMAGE}@${DIGEST}"

# 2. Verify signature
echo "--- Signature Verification ---"
cosign verify --rekor-url="${REKOR_URL}" \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  "${IMAGE}@${DIGEST}" 2>&1 | head -5

# 3. Check attestation
echo "--- Attestation ---"
cosign verify-attestation --rekor-url="${REKOR_URL}" \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  --type slsaprovenance "${IMAGE}@${DIGEST}" 2>&1 | head -5

# 4. Download and inspect SBOM
echo "--- SBOM ---"
cosign download attestation "${IMAGE}@${DIGEST}" \
  | jq -r '.payload' | base64 -d \
  | jq '{predicateType: .predicateType, components: (.predicate.components // .predicate.materials | length)}'

# 5. Check Tekton Chains signed the taskruns
echo "--- Chains Attestation ---"
oc get taskrun -n ${NAMESPACE} -l tekton.dev/pipelineRun=${PIPELINERUN} \
  -o jsonpath='{range .items[*]}{.metadata.name}: {.metadata.annotations.chains\.tekton\.dev/signed}{"\n"}{end}'
```

## SLSA Compliance Levels

| Level | What It Means | How We Meet It |
|---|---|---|
| SLSA 1 | Documented build process | Tekton pipeline definition in git |
| SLSA 2 | Hosted, authenticated build service | Tekton runs on OpenShift with RBAC |
| SLSA 3 | Hardened builds, provenance attestation | Tekton Chains + TAS signing + Rekor log |
| SLSA 4 | Hermetic, reproducible builds | Requires additional pipeline hardening |

## Pre-Sales Talking Points

- **"We need to comply with EO 14028 / NIST SSDF"** — TSSC templates produce SLSA Level 3 artifacts with signed provenance, SBOM, and a transparency log. This is exactly what the executive order requires.
- **"How do we know our container images haven't been tampered with?"** — Every image is signed with cosign via your on-cluster Sigstore instance. The signature is recorded in an immutable transparency log (Rekor). Verification is one command.
- **"What about vulnerabilities in our dependencies?"** — TPA continuously analyzes SBOMs against Red Hat's security data. You get real-time vulnerability alerts with VEX context — not just CVE numbers, but whether they actually affect your deployment.
- **"This sounds like it'll slow developers down"** — It's all automatic. The developer pushes code, the pipeline handles everything. They don't even know signing is happening unless they look. Zero friction, full compliance.
- **"Can we enforce this across all teams?"** — Enterprise Contract provides policy-as-code. If an artifact isn't signed, doesn't have an SBOM, or fails a policy check — it doesn't deploy. Period.
