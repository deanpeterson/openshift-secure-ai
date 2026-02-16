#!/usr/bin/env bash
#
# verify-supply-chain.sh — Verify supply chain security for a pipeline-built artifact
#
# Usage: bash scripts/verify-supply-chain.sh --namespace <ns> --pipeline-run <name>
#        bash scripts/verify-supply-chain.sh --image <image>@<digest>
#

set -euo pipefail

# Colors
if [ -t 1 ]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
    NC='\033[0m'; BOLD='\033[1m'
else
    GREEN=''; RED=''; YELLOW=''; NC=''; BOLD=''
fi

NAMESPACE=""
PIPELINE_RUN=""
IMAGE=""
DIGEST=""
PASS=0
FAIL=0
WARN=0

usage() {
    echo "Usage:"
    echo "  $0 --namespace <ns> --pipeline-run <run-name>"
    echo "  $0 --image <image>@<digest>"
    exit 1
}

check_pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); }
check_fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL++)); }
check_warn() { echo -e "  ${YELLOW}!${NC} $1"; ((WARN++)); }

while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace|-n) NAMESPACE="$2"; shift 2 ;;
        --pipeline-run|-p) PIPELINE_RUN="$2"; shift 2 ;;
        --image|-i)
            if [[ "$2" == *"@"* ]]; then
                IMAGE="${2%%@*}"
                DIGEST="${2#*@}"
            else
                IMAGE="$2"
            fi
            shift 2 ;;
        --digest|-d) DIGEST="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Get image from pipeline run if not provided directly
if [[ -n "$PIPELINE_RUN" && -n "$NAMESPACE" && -z "$IMAGE" ]]; then
    echo -e "${BOLD}Extracting image from pipeline run ${PIPELINE_RUN}...${NC}"
    IMAGE=$(oc get pipelinerun "${PIPELINE_RUN}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.results[?(@.name=="IMAGE_URL")].value}' 2>/dev/null || true)
    DIGEST=$(oc get pipelinerun "${PIPELINE_RUN}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.results[?(@.name=="IMAGE_DIGEST")].value}' 2>/dev/null || true)
fi

if [[ -z "$IMAGE" ]]; then
    echo "Error: Could not determine image. Provide --image or --namespace + --pipeline-run"
    usage
fi

echo -e "${BOLD}═══════════════════════════════════════════${NC}"
echo -e "${BOLD} Supply Chain Verification${NC}"
echo -e "${BOLD}═══════════════════════════════════════════${NC}"
echo ""
echo "  Image:  ${IMAGE}"
echo "  Digest: ${DIGEST:-unknown}"
echo ""

# --- 1. Pipeline Run Status ---
if [[ -n "$PIPELINE_RUN" && -n "$NAMESPACE" ]]; then
    echo -e "${BOLD}[1/5] Pipeline Run${NC}"

    STATUS=$(oc get pipelinerun "${PIPELINE_RUN}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "NotFound")

    if [[ "$STATUS" == "True" ]]; then
        check_pass "Pipeline run completed successfully"
    elif [[ "$STATUS" == "NotFound" ]]; then
        check_fail "Pipeline run not found"
    else
        check_fail "Pipeline run status: ${STATUS}"
    fi

    # Show task list
    TASKS=$(oc get pipelinerun "${PIPELINE_RUN}" -n "${NAMESPACE}" \
        -o jsonpath='{range .status.childReferences[*]}{.pipelineTaskName} {end}' 2>/dev/null || echo "")
    if [[ -n "$TASKS" ]]; then
        echo "    Tasks: ${TASKS}"
    fi
    echo ""
else
    echo -e "${BOLD}[1/5] Pipeline Run${NC}"
    check_warn "No pipeline run specified — skipping"
    echo ""
fi

# --- 2. Signature Verification ---
echo -e "${BOLD}[2/5] Artifact Signature${NC}"

REKOR_HOST=$(oc get route -n trusted-artifact-signer rekor-server -o jsonpath='{.spec.host}' 2>/dev/null || true)

if [[ -z "$REKOR_HOST" ]]; then
    check_warn "TAS Rekor route not found — cannot verify signature"
elif ! command -v cosign &>/dev/null; then
    check_warn "cosign not installed — cannot verify signature"
elif [[ -z "$DIGEST" ]]; then
    check_warn "No digest available — cannot verify signature"
else
    REKOR_URL="https://${REKOR_HOST}"
    if cosign verify \
        --rekor-url="${REKOR_URL}" \
        --certificate-identity-regexp=".*" \
        --certificate-oidc-issuer-regexp=".*" \
        "${IMAGE}@${DIGEST}" &>/dev/null; then
        check_pass "Image signature verified via cosign"
    else
        check_fail "Image signature verification FAILED"
    fi

    # Check Rekor entry
    if command -v rekor-cli &>/dev/null; then
        ENTRY_COUNT=$(rekor-cli search --rekor_server="${REKOR_URL}" --sha="${DIGEST#sha256:}" 2>/dev/null | wc -l || echo "0")
        if [[ "$ENTRY_COUNT" -gt 0 ]]; then
            check_pass "Found ${ENTRY_COUNT} entries in Rekor transparency log"
        else
            check_warn "No Rekor transparency log entries found"
        fi
    fi
fi
echo ""

# --- 3. SBOM Verification ---
echo -e "${BOLD}[3/5] SBOM (Software Bill of Materials)${NC}"

if command -v cosign &>/dev/null && [[ -n "$DIGEST" ]]; then
    SBOM_OUTPUT=$(cosign download attestation "${IMAGE}@${DIGEST}" 2>/dev/null || true)
    if [[ -n "$SBOM_OUTPUT" ]]; then
        COMPONENT_COUNT=$(echo "$SBOM_OUTPUT" | jq -r '.payload' 2>/dev/null | base64 -d 2>/dev/null \
            | jq '.predicate.components // .predicate.materials | length' 2>/dev/null || echo "0")
        if [[ "$COMPONENT_COUNT" -gt 0 ]]; then
            check_pass "SBOM attestation found (${COMPONENT_COUNT} components)"
        else
            check_pass "SBOM attestation exists (could not parse component count)"
        fi
    else
        check_warn "No SBOM attestation found for this image"
    fi
else
    check_warn "Cannot check SBOM (cosign not available or no digest)"
fi

# Check TPA for vulnerability analysis
TPA_HOST=$(oc get route -n trustification vexination-api -o jsonpath='{.spec.host}' 2>/dev/null || \
    oc get route -n trustification bombastic-api -o jsonpath='{.spec.host}' 2>/dev/null || true)

if [[ -n "$TPA_HOST" && -n "$DIGEST" ]]; then
    VEX_RESULT=$(curl -s --max-time 5 "https://${TPA_HOST}/api/v1/vex?advisory=${DIGEST}" 2>/dev/null || true)
    if [[ -n "$VEX_RESULT" && "$VEX_RESULT" != *"error"* ]]; then
        VULN_COUNT=$(echo "$VEX_RESULT" | jq '.vulnerabilities | length' 2>/dev/null || echo "unknown")
        check_pass "TPA analysis available (${VULN_COUNT} vulnerabilities reported)"
    else
        check_warn "TPA analysis not available for this digest"
    fi
elif [[ -z "$TPA_HOST" ]]; then
    check_warn "TPA route not found — vulnerability analysis unavailable"
fi
echo ""

# --- 4. Tekton Chains Attestation ---
echo -e "${BOLD}[4/5] Tekton Chains Attestation${NC}"

if [[ -n "$PIPELINE_RUN" && -n "$NAMESPACE" ]]; then
    SIGNED_TASKS=0
    TOTAL_TASKS=0

    while IFS= read -r line; do
        TASK_NAME=$(echo "$line" | awk '{print $1}')
        SIGNED=$(echo "$line" | awk '{print $2}')
        ((TOTAL_TASKS++))
        if [[ "$SIGNED" == "true" ]]; then
            ((SIGNED_TASKS++))
        fi
    done < <(oc get taskrun -n "${NAMESPACE}" -l "tekton.dev/pipelineRun=${PIPELINE_RUN}" \
        -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.annotations.chains\.tekton\.dev/signed}{"\n"}{end}' 2>/dev/null || true)

    if [[ $TOTAL_TASKS -eq 0 ]]; then
        check_warn "No task runs found for this pipeline run"
    elif [[ $SIGNED_TASKS -eq $TOTAL_TASKS ]]; then
        check_pass "All ${TOTAL_TASKS} task runs signed by Tekton Chains"
    elif [[ $SIGNED_TASKS -gt 0 ]]; then
        check_warn "${SIGNED_TASKS}/${TOTAL_TASKS} task runs signed"
    else
        check_fail "No task runs signed by Tekton Chains"
    fi
else
    check_warn "No pipeline run specified — skipping Chains verification"
fi
echo ""

# --- 5. Enterprise Contract ---
echo -e "${BOLD}[5/5] Enterprise Contract Policy${NC}"

if command -v ec &>/dev/null && [[ -n "$IMAGE" && -n "$DIGEST" ]]; then
    if ec validate image --image "${IMAGE}@${DIGEST}" \
        --policy "oci::quay.io/enterprise-contract/config:latest" \
        --rekor-url "https://${REKOR_HOST}" 2>/dev/null; then
        check_pass "Enterprise Contract policies passed"
    else
        check_fail "Enterprise Contract validation failed"
    fi
elif ! command -v ec &>/dev/null; then
    check_warn "ec CLI not installed — skipping Enterprise Contract check"
else
    check_warn "Missing image/digest — skipping Enterprise Contract check"
fi
echo ""

# --- Summary ---
echo -e "${BOLD}═══════════════════════════════════════════${NC}"
TOTAL=$((PASS + FAIL + WARN))
echo -e " Results: ${GREEN}${PASS} passed${NC} · ${RED}${FAIL} failed${NC} · ${YELLOW}${WARN} warnings${NC}"

if [[ $FAIL -eq 0 ]]; then
    echo -e " ${GREEN}${BOLD}Supply chain verification: PASSED${NC}"
else
    echo -e " ${RED}${BOLD}Supply chain verification: FAILED${NC}"
fi
echo -e "${BOLD}═══════════════════════════════════════════${NC}"

exit $FAIL
