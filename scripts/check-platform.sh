#!/usr/bin/env bash
#
# check-platform.sh — Verify all platform components are healthy and ready for demo
#
# Usage: bash scripts/check-platform.sh
#
# Checks:
#   1. Developer Hub (rhdh-test)
#   2. OpenShift AI operator and components
#   3. OpenShift Pipelines / Tekton Chains
#   4. Trusted Artifact Signer (TAS)
#   5. Trusted Profile Analyzer (TPA)
#   6. Inference services
#   7. GPU availability
#

set -uo pipefail

CLUSTER_DOMAIN="apps.salamander.aimlworkbench.com"
PASS=0
FAIL=0
WARN=0

# Colors (only if terminal supports it)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
    BOLD='\033[1m'
else
    GREEN='' RED='' YELLOW='' NC='' BOLD=''
fi

pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; ((WARN++)); }

check_pods() {
    local ns="$1"
    local label="${2:-}"
    local desc="$3"
    local count

    if [ -n "$label" ]; then
        count=$(oc get pods -n "$ns" -l "$label" --no-headers 2>/dev/null | grep -c "Running" || true)
    else
        count=$(oc get pods -n "$ns" --no-headers 2>/dev/null | grep -c "Running" || true)
    fi

    if [ "$count" -gt 0 ]; then
        pass "$desc ($count pods running)"
    else
        fail "$desc (no running pods found)"
    fi
}

echo ""
echo -e "${BOLD}OpenShift Secure AI — Platform Health Check${NC}"
echo -e "${BOLD}Cluster: ${CLUSTER_DOMAIN}${NC}"
echo ""

# ─── 1. Developer Hub ───────────────────────────────────────────────────────────

echo -e "${BOLD}[1/7] Developer Hub${NC}"
check_pods "rhdh-test" "app.kubernetes.io/name=developer-hub" "Developer Hub pods"

RHDH_HOST=$(oc get route -n rhdh-test -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
if [ -n "$RHDH_HOST" ]; then
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://${RHDH_HOST}" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 500 ]; then
        pass "Developer Hub route (https://${RHDH_HOST} → HTTP $HTTP_CODE)"
    else
        warn "Developer Hub route (https://${RHDH_HOST} → HTTP $HTTP_CODE)"
    fi
else
    fail "Developer Hub route not found"
fi
echo ""

# ─── 2. OpenShift AI ────────────────────────────────────────────────────────────

echo -e "${BOLD}[2/7] OpenShift AI${NC}"
check_pods "redhat-ods-operator" "" "OpenShift AI operator"
check_pods "redhat-ods-applications" "app=rhods-dashboard" "OpenShift AI dashboard"

DSC_READY=$(oc get dsc -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [ "$DSC_READY" = "True" ]; then
    pass "DataScienceCluster ready"
else
    warn "DataScienceCluster status: ${DSC_READY:-unknown}"
fi

for component in kserve-controller-manager modelmesh-controller notebook-controller model-registry; do
    count=$(oc get pods -n redhat-ods-applications --no-headers 2>/dev/null | grep -c "$component" || true)
    if [ "$count" -gt 0 ]; then
        pass "${component} ($count pods)"
    else
        warn "${component} (not detected)"
    fi
done
echo ""

# ─── 3. OpenShift Pipelines / Tekton Chains ─────────────────────────────────────

echo -e "${BOLD}[3/7] OpenShift Pipelines${NC}"
check_pods "openshift-pipelines" "app=tekton-pipelines-controller" "Tekton Pipelines controller"
check_pods "openshift-pipelines" "app=tekton-chains-controller" "Tekton Chains controller"

CHAINS_FORMAT=$(oc get tektonconfig config -o jsonpath='{.spec.chain.artifacts\.taskrun\.format}' 2>/dev/null || true)
if [ "$CHAINS_FORMAT" = "in-toto" ]; then
    pass "Tekton Chains signing format: in-toto"
else
    warn "Tekton Chains signing format: ${CHAINS_FORMAT:-not configured}"
fi

CHAINS_TRANSPARENCY=$(oc get tektonconfig config -o jsonpath='{.spec.chain.transparency\.enabled}' 2>/dev/null || true)
if [ "$CHAINS_TRANSPARENCY" = "true" ]; then
    pass "Tekton Chains transparency log: enabled"
else
    warn "Tekton Chains transparency log: ${CHAINS_TRANSPARENCY:-not configured}"
fi
echo ""

# ─── 4. Trusted Artifact Signer (TAS) ───────────────────────────────────────────

echo -e "${BOLD}[4/7] Trusted Artifact Signer (TAS)${NC}"

# Try both common namespaces
TAS_NS=""
for ns in trusted-artifact-signer rhtas-operator; do
    count=$(oc get pods -n "$ns" --no-headers 2>/dev/null | grep -c "Running" || true)
    if [ "$count" -gt 0 ]; then
        TAS_NS="$ns"
        pass "TAS pods in ${ns} ($count running)"
        break
    fi
done
[ -z "$TAS_NS" ] && fail "TAS pods (checked trusted-artifact-signer, rhtas-operator)"

if [ -n "$TAS_NS" ]; then
    for svc in fulcio-server rekor-server; do
        host=$(oc get route -n "$TAS_NS" "$svc" -o jsonpath='{.spec.host}' 2>/dev/null || true)
        if [ -n "$host" ]; then
            pass "$svc route: https://${host}"
        else
            fail "$svc route not found"
        fi
    done

    REKOR_HOST=$(oc get route -n "$TAS_NS" rekor-server -o jsonpath='{.spec.host}' 2>/dev/null || true)
    if [ -n "$REKOR_HOST" ]; then
        TREE_SIZE=$(curl -s --connect-timeout 5 "https://${REKOR_HOST}/api/v1/log" 2>/dev/null | jq -r '.treeSize' 2>/dev/null || true)
        if [ -n "$TREE_SIZE" ] && [ "$TREE_SIZE" != "null" ]; then
            pass "Rekor transparency log: $TREE_SIZE entries"
        else
            warn "Rekor transparency log: could not query"
        fi
    fi
fi
echo ""

# ─── 5. Trusted Profile Analyzer (TPA) ──────────────────────────────────────────

echo -e "${BOLD}[5/7] Trusted Profile Analyzer (TPA)${NC}"

TPA_NS=""
for ns in trustification tpa; do
    count=$(oc get pods -n "$ns" --no-headers 2>/dev/null | grep -c "Running" || true)
    if [ "$count" -gt 0 ]; then
        TPA_NS="$ns"
        pass "TPA pods in ${ns} ($count running)"
        break
    fi
done
[ -z "$TPA_NS" ] && warn "TPA pods (checked trustification, tpa)"

if [ -n "$TPA_NS" ]; then
    for svc in bombastic-api vexination-api spog-ui; do
        host=$(oc get route -n "$TPA_NS" "$svc" -o jsonpath='{.spec.host}' 2>/dev/null || true)
        if [ -n "$host" ]; then
            pass "$svc route: https://${host}"
        else
            warn "$svc route not found (may use different name)"
        fi
    done
fi
echo ""

# ─── 6. Inference Services ──────────────────────────────────────────────────────

echo -e "${BOLD}[6/7] Inference Services${NC}"
ISVC_OUTPUT=$(oc get inferenceservices -A --no-headers \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status' 2>/dev/null || true)

ISVC_COUNT=$(echo "$ISVC_OUTPUT" | grep -c "[a-z]" || true)
if [ "$ISVC_COUNT" -gt 0 ]; then
    pass "Found $ISVC_COUNT inference service(s)"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        ns=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{print $2}')
        ready=$(echo "$line" | awk '{print $3}')
        if [ "$ready" = "True" ]; then
            pass "  ${ns}/${name}: Ready"
        else
            warn "  ${ns}/${name}: Not ready (${ready:-unknown})"
        fi
    done <<< "$ISVC_OUTPUT"
else
    warn "No inference services found"
fi

ISAAC_PODS=$(oc get pods -n isaac-sim --no-headers 2>/dev/null | grep -c "Running" || true)
if [ "$ISAAC_PODS" -gt 0 ]; then
    pass "Isaac Sim: $ISAAC_PODS pods running"
else
    warn "Isaac Sim: no running pods in isaac-sim namespace"
fi
echo ""

# ─── 7. GPU Availability ────────────────────────────────────────────────────────

echo -e "${BOLD}[7/7] GPU Resources${NC}"
GPU_NODES=$(oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l || true)
if [ "$GPU_NODES" -gt 0 ]; then
    pass "GPU nodes: $GPU_NODES"
    oc get nodes -l nvidia.com/gpu.present=true \
        -o jsonpath='{range .items[*]}  {.metadata.name}: {.status.capacity.nvidia\.com/gpu} GPU(s){"\n"}{end}' 2>/dev/null || true
else
    warn "No GPU nodes detected (label nvidia.com/gpu.present=true)"
fi

NVIDIA_PODS=$(oc get pods -n nvidia-gpu-operator --no-headers 2>/dev/null | grep -c "Running" || true)
if [ "$NVIDIA_PODS" -gt 0 ]; then
    pass "NVIDIA GPU operator: $NVIDIA_PODS pods running"
else
    warn "NVIDIA GPU operator: not detected"
fi
echo ""

# ─── Summary ─────────────────────────────────────────────────────────────────────

echo -e "${BOLD}─────────────────────────────────────────${NC}"
echo -e "${BOLD}Summary${NC}"
echo -e "  ${GREEN}Passed: ${PASS}${NC}"
[ "$WARN" -gt 0 ] && echo -e "  ${YELLOW}Warnings: ${WARN}${NC}"
[ "$FAIL" -gt 0 ] && echo -e "  ${RED}Failed: ${FAIL}${NC}"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}Platform is NOT ready for demo. Fix failures above.${NC}"
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo -e "${YELLOW}Platform is mostly ready. Review warnings above.${NC}"
    exit 0
else
    echo -e "${GREEN}Platform is fully ready for demo.${NC}"
    exit 0
fi
