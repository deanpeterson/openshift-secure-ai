---
name: openshift-secure-ai
description: >
  Manages OpenShift Platform Plus, Advanced Developer Suite, and OpenShift AI
  on the salamander.aimlworkbench.com cluster. Triggers on: OpenShift, Developer Hub,
  RHDH, OpenShift AI, RHOAI, model serving, KServe, ModelMesh, supply chain, TSSC,
  TAS, TPA, artifact signing, SBOM, cosign, Tekton Chains, pipeline security,
  golden path templates, pre-sales demo, inference service, model registry,
  TrustyAI, notebooks, RAG, chatbot, codegen.
---

# OpenShift Secure AI — Skill Reference

## Cluster Context

| Resource | Value |
|---|---|
| Cluster | `salamander.aimlworkbench.com` |
| API | `https://api.salamander.aimlworkbench.com:6443` |
| Developer Hub | `https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/` |
| Developer Hub NS | `rhdh-test` |
| OpenShift AI NS | `redhat-ods-applications` (operator), per-project for workloads |
| Llama 3.1 8B NS | `llama-test` |
| Isaac Sim NS | `isaac-sim` |

## Quick Health Check

Run the platform health check before any demo:

```bash
bash scripts/check-platform.sh
```

Or manually verify the critical operators:

```bash
# Developer Hub
oc get pods -n rhdh-test -l app.kubernetes.io/name=developer-hub

# OpenShift AI operator
oc get pods -n redhat-ods-operator

# OpenShift AI dashboard and components
oc get dsci,dsc

# Pipeline operator
oc get pods -n openshift-pipelines

# TAS (Trusted Artifact Signer)
oc get pods -n trusted-artifact-signer

# TPA (Trusted Profile Analyzer)
oc get pods -n trustification
```

---

## Workflow 1: Scaffold a Secure AI Application

Use Developer Hub golden path templates to create a new application with built-in supply chain security.

### Available Template Families

| Family | Templates | Key Feature |
|---|---|---|
| AI Lab | chatbot, codegen, RAG, audio-to-text, object-detection, model-server | AI/ML workloads with model integration |
| TSSC | dotnet, go, java-quarkus, java-springboot, nodejs, python | Trusted Software Supply Chain (signing + SBOM) |
| RHDH Standard | go, nodejs, python, spring-boot, quarkus + argocd/tekton | Standard golden paths with GitOps |

### Steps

1. **List available templates:**
   ```bash
   # Query the Developer Hub catalog API
   curl -s -H "Authorization: Bearer $(oc create token developer-hub-sa -n rhdh-test 2>/dev/null || echo 'TOKEN')" \
     "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/catalog/entities?filter=kind=template" \
     | jq '.[].metadata.name'
   ```

2. **Scaffold via the UI** — direct the user to:
   ```
   https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/create
   ```

3. **Scaffold via API** (for automation):
   ```bash
   curl -X POST \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer $TOKEN" \
     "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/scaffolder/v2/tasks" \
     -d '{
       "templateRef": "template:default/tssc-python",
       "values": {
         "component_id": "secure-ai-demo",
         "owner": "user:default/dean",
         "repo": { "host": "github.com", "owner": "dean-org", "name": "secure-ai-demo" }
       }
     }'
   ```

4. **Verify the scaffolded component appears in catalog:**
   ```bash
   curl -s -H "Authorization: Bearer $TOKEN" \
     "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/catalog/entities?filter=metadata.name=secure-ai-demo" \
     | jq '.[] | {name: .metadata.name, lifecycle: .spec.lifecycle}'
   ```

> **Deep dive:** See [references/developer-hub.md](references/developer-hub.md) for full template details and API reference.

---

## Workflow 2: Deploy and Manage AI Models

### Check Existing Inference Services

```bash
# List all inference services across namespaces
oc get inferenceservices -A

# Check Llama 3.1 8B status
oc get inferenceservice -n llama-test -o wide

# Get detailed status with conditions
oc get inferenceservice -n llama-test -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[*].type}={.status.conditions[*].status}{"\n"}{end}'
```

### Deploy a New Model (KServe)

```bash
bash scripts/deploy-model.sh --name my-llm \
  --namespace ai-demo \
  --runtime vllm \
  --model-format pytorch \
  --storage-uri "s3://models/llama-3.1-8b"
```

Or apply directly:

```bash
cat <<'EOF' | oc apply -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llama-demo
  namespace: ai-demo
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
  labels:
    opendatahub.io/dashboard: "true"
spec:
  predictor:
    model:
      modelFormat:
        name: pytorch
      runtime: vllm-runtime
      storageUri: "s3://models/llama-3.1-8b"
      resources:
        requests:
          cpu: "4"
          memory: 16Gi
          nvidia.com/gpu: "1"
        limits:
          cpu: "8"
          memory: 32Gi
          nvidia.com/gpu: "1"
EOF
```

### Check Model Registry

```bash
# List registered models
oc get pods -n redhat-ods-applications -l app=model-registry
oc exec -n redhat-ods-applications deploy/model-registry -- \
  curl -s localhost:8080/api/model_registry/v1alpha3/registered_models | jq '.items[].name'
```

### Manage Notebooks

```bash
# List running notebooks
oc get notebooks -A

# Check notebook status
oc get notebook -n <namespace> -o jsonpath='{.items[*].status.readyReplicas}'
```

> **Deep dive:** See [references/openshift-ai.md](references/openshift-ai.md) for KServe vs ModelMesh, GPU scheduling, and pipeline details.

---

## Workflow 3: Verify Supply Chain Security

### Full Verification

```bash
bash scripts/verify-supply-chain.sh --namespace <app-namespace> --pipeline-run <run-name>
```

### Manual Checks

**Check Tekton pipeline run results:**
```bash
# List recent pipeline runs
oc get pipelineruns -n <namespace> --sort-by=.metadata.creationTimestamp -o name | tail -5

# Get results from a specific run
oc get pipelinerun <run-name> -n <namespace> \
  -o jsonpath='{range .status.results[*]}{.name}: {.value}{"\n"}{end}'
```

**Verify artifact signature with cosign:**
```bash
# Get the image digest from the pipeline run
IMAGE=$(oc get pipelinerun <run-name> -n <namespace> \
  -o jsonpath='{.status.results[?(@.name=="IMAGE_URL")].value}')
DIGEST=$(oc get pipelinerun <run-name> -n <namespace> \
  -o jsonpath='{.status.results[?(@.name=="IMAGE_DIGEST")].value}')

# Verify signature using TAS (cluster Rekor + Fulcio)
REKOR_URL=$(oc get route -n trusted-artifact-signer rekor-server -o jsonpath='{.spec.host}')
cosign verify --rekor-url="https://${REKOR_URL}" \
  --certificate-identity-regexp=".*" \
  --certificate-oidc-issuer-regexp=".*" \
  "${IMAGE}@${DIGEST}"
```

**Check SBOM:**
```bash
# Retrieve SBOM attestation
cosign download attestation "${IMAGE}@${DIGEST}" | jq -r '.payload' | base64 -d | jq '.predicate'

# Or check via TPA
TPA_URL=$(oc get route -n trustification vexination-api -o jsonpath='{.spec.host}' 2>/dev/null)
curl -s "https://${TPA_URL}/api/v1/vex?advisory=${DIGEST}" | jq '.vulnerabilities'
```

**Check Tekton Chains attestation:**
```bash
# Verify chains is signing
oc get tektonconfig -o jsonpath='{.items[0].spec.chain}'

# Check taskrun attestation
oc get taskrun -n <namespace> -l tekton.dev/pipelineRun=<run-name> \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.chains\.tekton\.dev/signed}{"\n"}{end}'
```

> **Deep dive:** See [references/supply-chain-security.md](references/supply-chain-security.md) for TAS architecture, TPA analysis, and SLSA compliance.

---

## Workflow 4: End-to-End Demo Flow

This is the "zero to secure AI app" demo. Use this when walking a customer through the full platform story.

### Pre-Demo Checklist

```bash
bash scripts/check-platform.sh
```

### Demo Steps

**Step 1 — Set the stage (1 min)**
Show the OpenShift console, highlight installed operators:
```bash
oc get csv -A | grep -E '(devhub|openshift-ai|pipelines|rhtas|trustification)' | awk '{print $2, $NF}'
```

**Step 2 — Scaffold the app (3 min)**
Navigate to Developer Hub and create a new app from a TSSC template:
```
https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/create
```
Choose the **TSSC Python** template. This gives us:
- A Python application repo with Tekton pipeline
- Automatic artifact signing via TAS
- SBOM generation and analysis via TPA
- GitOps deployment via ArgoCD

**Step 3 — Watch the pipeline (2 min)**
```bash
# Find the pipeline run that was triggered
oc get pipelineruns -n <app-namespace> --sort-by=.metadata.creationTimestamp -w

# Show the pipeline tasks completing
oc get pipelinerun <run-name> -n <app-namespace> \
  -o jsonpath='{range .status.childReferences[*]}{.name}{"\t"}{.pipelineTaskName}{"\n"}{end}'
```

**Step 4 — Prove the supply chain (3 min)**
```bash
bash scripts/verify-supply-chain.sh --namespace <app-namespace> --pipeline-run <run-name>
```
Walk through:
- The image was signed (cosign verify succeeds)
- The SBOM was generated (show components list)
- Tekton Chains recorded the attestation (show signed taskruns)
- TPA analyzed the profile (show vulnerability scan)

**Step 5 — Deploy the AI model (3 min)**
Show OpenShift AI:
```bash
# Show existing inference services
oc get inferenceservices -A

# Show the Llama model
oc describe inferenceservice -n llama-test

# Test the inference endpoint (if ready)
ISVC_URL=$(oc get inferenceservice -n llama-test -o jsonpath='{.items[0].status.url}')
curl -s "${ISVC_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model": "llama-3.1-8b", "messages": [{"role": "user", "content": "What is OpenShift?"}], "max_tokens": 100}'
```

**Step 6 — Connect the story (2 min)**
Tie it together:
- The **developer** used Developer Hub to scaffold in minutes, not weeks
- The **pipeline** built, signed, and scanned automatically — zero friction
- The **security team** can verify every artifact in the supply chain
- The **AI team** has model serving, monitoring, and a registry ready to go
- The **platform team** manages it all from one control plane

> **Deep dive:** See [references/demo-narratives.md](references/demo-narratives.md) for audience-specific talk tracks.

---

## Workflow 5: Troubleshooting

### Developer Hub Issues

```bash
# Check pod health
oc get pods -n rhdh-test
oc logs -n rhdh-test deploy/developer-hub --tail=50

# Check catalog refresh
oc logs -n rhdh-test deploy/developer-hub --tail=100 | grep -i catalog

# Verify GitHub auth
oc get secret -n rhdh-test -l app.kubernetes.io/name=developer-hub -o name
```

### OpenShift AI Issues

```bash
# Check DSC/DSCI status
oc get dsc -o jsonpath='{.items[0].status.conditions[*].type}={.items[0].status.conditions[*].status}'

# Check inference service conditions
oc get inferenceservice -n llama-test -o json | jq '.items[].status.conditions'

# Check serving runtime
oc get servingruntimes -n llama-test

# GPU availability
oc describe nodes | grep -A5 "nvidia.com/gpu"
```

### Pipeline / Supply Chain Issues

```bash
# Check pipeline operator
oc get pods -n openshift-pipelines -l app=tekton-pipelines-controller

# Check Tekton Chains controller
oc get pods -n openshift-pipelines -l app=tekton-chains-controller

# Check TAS components
oc get pods -n trusted-artifact-signer

# Check TPA components
oc get pods -n trustification
```

---

## Value Propositions by Role

| Role | Key Message |
|---|---|
| **CISO** | Every artifact is signed and attested. Full SBOM visibility. SLSA Level 3 compliance out of the box. |
| **CTO** | Developers ship AI apps in hours, not months. Security is built in, not bolted on. |
| **Dev Lead** | Golden path templates mean no more YAML wrangling. Focus on code, not plumbing. |
| **Platform Eng** | One platform for apps + AI + security. Operators handle lifecycle. GitOps handles drift. |

> **Deep dive:** See [references/demo-narratives.md](references/demo-narratives.md) for full talk tracks.
