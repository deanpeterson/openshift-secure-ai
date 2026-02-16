#!/usr/bin/env bash
#
# deploy-model.sh — Deploy a model to OpenShift AI model serving
#
# Usage:
#   bash scripts/deploy-model.sh --name <name> --namespace <ns> --storage-uri <uri> [options]
#
# Required:
#   --name          Name of the InferenceService
#   --namespace     Target namespace
#   --storage-uri   S3 URI or PVC path for model weights
#
# Options:
#   --runtime       Serving runtime: vllm, tgis, ovms, triton (default: vllm)
#   --model-format  Model format: pytorch, onnx, tensorflow, sklearn (default: pytorch)
#   --gpu           Number of GPUs (default: 1, use 0 for CPU-only)
#   --cpu           CPU request (default: 4)
#   --memory        Memory request (default: 16Gi)
#   --max-memory    Memory limit (default: 32Gi)
#   --mode          Deployment mode: RawDeployment, Serverless, ModelMesh (default: RawDeployment)
#   --s3-secret     Name of existing S3 credentials secret
#   --dry-run       Print the YAML without applying
#   --no-wait       Don't wait for the service to become ready
#   --timeout       Wait timeout in seconds (default: 600)
#

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────────

NAME=""
NAMESPACE=""
RUNTIME="vllm"
MODEL_FORMAT="pytorch"
STORAGE_URI=""
GPU=1
CPU="4"
MEMORY="16Gi"
MAX_MEMORY="32Gi"
MODE="RawDeployment"
S3_SECRET=""
DRY_RUN=false
WAIT=true
TIMEOUT=600

# ─── Parse Arguments ─────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)          NAME="$2"; shift 2 ;;
        --namespace)     NAMESPACE="$2"; shift 2 ;;
        --runtime)       RUNTIME="$2"; shift 2 ;;
        --model-format)  MODEL_FORMAT="$2"; shift 2 ;;
        --storage-uri)   STORAGE_URI="$2"; shift 2 ;;
        --gpu)           GPU="$2"; shift 2 ;;
        --cpu)           CPU="$2"; shift 2 ;;
        --memory)        MEMORY="$2"; shift 2 ;;
        --max-memory)    MAX_MEMORY="$2"; shift 2 ;;
        --mode)          MODE="$2"; shift 2 ;;
        --s3-secret)     S3_SECRET="$2"; shift 2 ;;
        --dry-run)       DRY_RUN=true; shift ;;
        --no-wait)       WAIT=false; shift ;;
        --timeout)       TIMEOUT="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ─── Validate ────────────────────────────────────────────────────────────────────

if [ -z "$NAME" ] || [ -z "$NAMESPACE" ] || [ -z "$STORAGE_URI" ]; then
    echo "Error: --name, --namespace, and --storage-uri are required" >&2
    echo "Run with --help for usage" >&2
    exit 1
fi

# Map runtime shorthand to full name
case "$RUNTIME" in
    vllm)    RUNTIME_NAME="vllm-runtime" ;;
    tgis)    RUNTIME_NAME="tgis-runtime" ;;
    ovms)    RUNTIME_NAME="ovms" ;;
    triton)  RUNTIME_NAME="triton" ;;
    *)       RUNTIME_NAME="$RUNTIME" ;;
esac

# ─── Build Resource Blocks ───────────────────────────────────────────────────────

GPU_REQUEST=""
GPU_LIMIT=""
if [ "$GPU" -gt 0 ]; then
    GPU_REQUEST="          nvidia.com/gpu: \"${GPU}\""
    GPU_LIMIT="          nvidia.com/gpu: \"${GPU}\""
fi

SA_BLOCK=""
if [ -n "$S3_SECRET" ]; then
    SA_BLOCK="    serviceAccountName: ${NAME}-sa"
fi

CPU_LIMIT=$((${CPU} * 2))

# ─── Generate YAML ───────────────────────────────────────────────────────────────

ISVC_YAML="apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: ${NAME}
  namespace: ${NAMESPACE}
  annotations:
    serving.kserve.io/deploymentMode: ${MODE}
  labels:
    opendatahub.io/dashboard: \"true\"
spec:
  predictor:
${SA_BLOCK:+    ${SA_BLOCK}
}    model:
      modelFormat:
        name: ${MODEL_FORMAT}
      runtime: ${RUNTIME_NAME}
      storageUri: \"${STORAGE_URI}\"
      resources:
        requests:
          cpu: \"${CPU}\"
          memory: ${MEMORY}
${GPU_REQUEST:+${GPU_REQUEST}
}        limits:
          cpu: \"${CPU_LIMIT}\"
          memory: ${MAX_MEMORY}
${GPU_LIMIT:+${GPU_LIMIT}
}"

# ─── Dry Run ─────────────────────────────────────────────────────────────────────

if $DRY_RUN; then
    echo "---"
    echo "$ISVC_YAML"
    exit 0
fi

# ─── Create Namespace If Needed ──────────────────────────────────────────────────

if ! oc get namespace "$NAMESPACE" &>/dev/null; then
    echo "Creating namespace: $NAMESPACE"
    oc new-project "$NAMESPACE" 2>/dev/null || oc create namespace "$NAMESPACE"
    oc label namespace "$NAMESPACE" opendatahub.io/dashboard=true --overwrite
fi

# ─── Create ServiceAccount for S3 ───────────────────────────────────────────────

if [ -n "$S3_SECRET" ]; then
    echo "Creating ServiceAccount ${NAME}-sa with S3 secret..."
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${NAME}-sa
  namespace: ${NAMESPACE}
secrets:
  - name: ${S3_SECRET}
EOF
fi

# ─── Apply ───────────────────────────────────────────────────────────────────────

echo ""
echo "Deploying InferenceService: ${NAME}"
echo "  Namespace:    ${NAMESPACE}"
echo "  Runtime:      ${RUNTIME_NAME}"
echo "  Model format: ${MODEL_FORMAT}"
echo "  Storage:      ${STORAGE_URI}"
echo "  GPU:          ${GPU}"
echo "  Mode:         ${MODE}"
echo ""

echo "$ISVC_YAML" | oc apply -f -
echo ""
echo "InferenceService created."

# ─── Wait for Ready ──────────────────────────────────────────────────────────────

if ! $WAIT; then
    echo ""
    echo "Skipping readiness wait (--no-wait)."
    echo "Check status: oc get inferenceservice ${NAME} -n ${NAMESPACE}"
    exit 0
fi

echo ""
echo "Waiting for InferenceService to become ready (timeout: ${TIMEOUT}s)..."

SECONDS=0
while [ $SECONDS -lt "$TIMEOUT" ]; do
    READY=$(oc get inferenceservice "$NAME" -n "$NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)

    if [ "$READY" = "True" ]; then
        URL=$(oc get inferenceservice "$NAME" -n "$NAMESPACE" \
            -o jsonpath='{.status.url}' 2>/dev/null || true)
        echo ""
        echo "InferenceService is READY."
        echo "  URL: ${URL}"
        echo ""
        echo "Test with:"
        echo "  curl -s '${URL}/v1/models'"
        echo "  curl -s '${URL}/v1/chat/completions' -H 'Content-Type: application/json' -d '{\"model\":\"${NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"max_tokens\":50}'"
        exit 0
    fi

    REASON=$(oc get inferenceservice "$NAME" -n "$NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true)
    printf "\r  [%3ds] Status: %-10s (%s)" "$SECONDS" "${READY:-Pending}" "${REASON:-initializing}"

    sleep 10
done

echo ""
echo ""
echo "WARNING: InferenceService did not become ready within ${TIMEOUT}s."
echo "Debug with:"
echo "  oc describe inferenceservice ${NAME} -n ${NAMESPACE}"
echo "  oc get pods -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${NAME}"
echo "  oc logs -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${NAME} --tail=50"
exit 1
