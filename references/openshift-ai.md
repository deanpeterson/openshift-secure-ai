# OpenShift AI Reference

## Overview

OpenShift AI (RHOAI) provides a full MLOps platform on this cluster:
KServe model serving, ModelMesh for multi-model, notebooks, data science pipelines,
model registry, and TrustyAI for explainability.

- **Operator NS:** `redhat-ods-operator`
- **Components NS:** `redhat-ods-applications`
- **Dashboard:** `https://rhods-dashboard-redhat-ods-applications.apps.salamander.aimlworkbench.com`

## Installed Components

```bash
# Check DataScienceCluster status
oc get dsc default-dsc -o jsonpath='{range .status.conditions[*]}{.type}: {.status}{"\n"}{end}'

# List all managed components
oc get dsc default-dsc -o jsonpath='{.spec.components}' | jq .
```

| Component | Status | Purpose |
|---|---|---|
| KServe | Managed | Single-model serving (GPU workloads, LLMs) |
| ModelMesh | Managed | Multi-model serving (lightweight, shared inference) |
| Data Science Pipelines | Managed | ML pipeline orchestration (Kubeflow-based) |
| Model Registry | Managed | Model versioning and metadata |
| TrustyAI | Managed | Model explainability and bias detection |
| Notebooks | Managed | JupyterHub-based data science environments |
| CodeFlare | Managed | Distributed compute for training |
| KubeRay | Managed | Ray cluster management |
| Kueue | Managed | Job queueing and fair scheduling |
| Training Operator | Managed | Distributed training (PyTorch, TF) |

## Current Workloads

### Inference Services
```bash
# List all inference services
oc get inferenceservices -A -o custom-columns=\
'NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,URL:.status.url'

# Llama 3.1 8B (llama-test namespace)
oc get inferenceservice -n llama-test -o yaml
```

### Notebooks
```bash
# List running notebooks
oc get notebooks -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.readyReplicas'
```

### Isaac Sim
```bash
# Running in isaac-sim namespace
oc get pods -n isaac-sim
oc get route -n isaac-sim -o jsonpath='{range .items[*]}https://{.spec.host}{"\n"}{end}'
```

## KServe vs ModelMesh

| Feature | KServe (Raw/Serverless) | ModelMesh |
|---|---|---|
| Best for | LLMs, large single models | Many small models sharing resources |
| GPU | Dedicated per model | Shared across models |
| Scale to zero | Yes (serverless mode) | No (always warm) |
| Runtimes | vLLM, TGI, Caikit, custom | OpenVINO, Triton, custom |
| Use when | Customer has large models, GPU budget | Customer has many small models, cost-sensitive |

### Deploy with KServe (vLLM Runtime)

```bash
# Create namespace and enable serving
oc new-project ai-demo
oc label namespace ai-demo opendatahub.io/dashboard=true modelmesh-enabled=false

# Create ServingRuntime
cat <<'EOF' | oc apply -n ai-demo -f -
apiVersion: serving.kserve.io/v1alpha1
kind: ServingRuntime
metadata:
  name: vllm-runtime
  annotations:
    opendatahub.io/recommended-accelerators: '["nvidia.com/gpu"]'
spec:
  builtInAdapter:
    modelLoadingTimeoutMillis: 90000
  containers:
  - name: kserve-container
    image: quay.io/modh/vllm:rhoai-2.16
    command: ["python", "-m", "vllm.entrypoints.openai.api_server"]
    args:
    - "--port=8080"
    - "--model=/mnt/models"
    - "--served-model-name={{.Name}}"
    ports:
    - containerPort: 8080
      protocol: TCP
  multiModel: false
  supportedModelFormats:
  - autoSelect: true
    name: pytorch
EOF
```

### Deploy with ModelMesh

```bash
oc label namespace ai-demo modelmesh-enabled=true

cat <<'EOF' | oc apply -n ai-demo -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: sentiment-model
  annotations:
    serving.kserve.io/deploymentMode: ModelMesh
spec:
  predictor:
    model:
      modelFormat:
        name: onnx
      storage:
        key: localMinIO
        path: models/sentiment
EOF
```

## Data Science Pipelines

```bash
# Check pipeline server
oc get pods -n <project> -l app=ds-pipeline

# List pipeline runs
oc get pipelineruns -n <project> --sort-by=.metadata.creationTimestamp

# Create a DataSciencePipelinesApplication
cat <<'EOF' | oc apply -f -
apiVersion: datasciencepipelinesapplications.opendatahub.io/v1alpha1
kind: DataSciencePipelinesApplication
metadata:
  name: dspa
  namespace: ai-demo
spec:
  dspVersion: v2
  objectStorage:
    externalStorage:
      bucket: pipeline-artifacts
      host: s3.amazonaws.com
      region: us-east-1
      s3CredentialsSecret:
        accessKey: AWS_ACCESS_KEY_ID
        secretKey: AWS_SECRET_ACCESS_KEY
        secretName: aws-connection-pipeline
EOF
```

## Model Registry

```bash
# Check model registry is running
oc get pods -n redhat-ods-applications -l app=model-registry

# List registered models (via API)
MODEL_REG_ROUTE=$(oc get route -n redhat-ods-applications model-registry -o jsonpath='{.spec.host}' 2>/dev/null)
curl -s "https://${MODEL_REG_ROUTE}/api/model_registry/v1alpha3/registered_models" | jq '.items[] | {name, state, description}'

# Register a new model
curl -X POST "https://${MODEL_REG_ROUTE}/api/model_registry/v1alpha3/registered_models" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "llama-3.1-8b-secure",
    "description": "Llama 3.1 8B with supply chain attestation",
    "customProperties": {
      "signed": {"string_value": "true"},
      "sbom": {"string_value": "cyclonedx"},
      "slsa_level": {"string_value": "3"}
    }
  }'
```

## GPU Resources

```bash
# Check available GPUs
oc describe nodes | grep -B2 -A5 "nvidia.com/gpu"

# Check GPU utilization
oc adm top nodes --sort-by=cpu

# Check NVIDIA GPU Operator
oc get pods -n nvidia-gpu-operator
```

## Troubleshooting

### InferenceService Not Ready

```bash
# Check conditions
oc get isvc <name> -n <ns> -o json | jq '.status.conditions[] | {type, status, message}'

# Check predictor pods
oc get pods -n <ns> -l serving.kserve.io/inferenceservice=<name>
oc logs -n <ns> -l serving.kserve.io/inferenceservice=<name> --tail=50

# Check events
oc get events -n <ns> --sort-by=.lastTimestamp | tail -20
```

### Notebook Not Starting

```bash
# Check notebook CR
oc get notebook <name> -n <ns> -o yaml

# Check pod events
oc describe pod <notebook-pod> -n <ns> | tail -30

# Check PVC
oc get pvc -n <ns>
```

## Pre-Sales Talking Points

- **"We already have Jupyter notebooks in AWS/GCP"** — OpenShift AI gives you notebooks PLUS model serving, pipelines, registry, and explainability in one platform. And it runs anywhere — on-prem, cloud, edge.
- **"Why not just use SageMaker/Vertex?"** — OpenShift AI is cloud-agnostic. No lock-in. Your ML platform moves with you. And it integrates with your existing OpenShift security posture.
- **"What about GPU cost?"** — KServe can scale to zero when models aren't in use. Kueue provides fair scheduling across teams. You pay for GPUs only when inference is happening.
- **"Is this production-ready?"** — Show them the Llama deployment, the model registry with versioning, TrustyAI for monitoring. This isn't a notebook playground — it's a production ML platform.
