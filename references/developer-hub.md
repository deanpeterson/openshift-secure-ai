# Developer Hub Reference

## Overview

Red Hat Developer Hub (RHDH) is the enterprise Backstage deployment on this cluster.
It provides golden path templates that let developers scaffold production-ready applications
with built-in CI/CD, GitOps, and supply chain security — in minutes instead of weeks.

- **URL:** https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/
- **Namespace:** `rhdh-test`
- **Auth:** GitHub OAuth (configured)

## Checking Developer Hub Health

```bash
# Pod status
oc get pods -n rhdh-test -l app.kubernetes.io/name=developer-hub

# Route accessibility
oc get route -n rhdh-test -o jsonpath='{range .items[*]}{.metadata.name}: https://{.spec.host}{"\n"}{end}'

# Logs (last 50 lines)
oc logs -n rhdh-test deploy/developer-hub --tail=50

# ConfigMap and dynamic plugins
oc get configmap -n rhdh-test -l app.kubernetes.io/name=developer-hub -o name
```

## Template Catalogs

### 1. AI Lab Templates

**Source:** `redhat-ai-dev/ai-lab-template` (GitHub)

These templates create AI/ML applications that integrate with OpenShift AI model serving.

| Template | Description | Key Components |
|---|---|---|
| `chatbot` | Conversational AI app with LLM backend | Streamlit/Gradio UI, vLLM inference, LangChain |
| `codegen` | Code generation assistant | IDE plugin integration, model serving endpoint |
| `rag` | Retrieval-Augmented Generation app | Vector DB (Milvus/PGVector), embedding model, LLM |
| `audio-to-text` | Speech-to-text transcription | Whisper model, audio processing pipeline |
| `object-detection` | Computer vision detection | YOLO/DETR model, image processing |
| `model-server` | Standalone model serving endpoint | KServe InferenceService, ServingRuntime |

**When to use:** Customer wants to see how quickly a developer can build an AI-powered application on OpenShift.

### 2. TSSC Templates (Trusted Software Supply Chain)

**Source:** `redhat-appstudio/tssc-sample-templates` (GitHub)

These templates include full supply chain security: Tekton pipelines with signing, SBOM generation, and attestation.

| Template | Description | Pipeline Features |
|---|---|---|
| `tssc-dotnet` | .NET application | Build, sign, SBOM, deploy |
| `tssc-go` | Go application | Build, sign, SBOM, deploy |
| `tssc-java-quarkus` | Quarkus (Java) application | Build, sign, SBOM, deploy, Trusted Content |
| `tssc-java-springboot` | Spring Boot (Java) application | Build, sign, SBOM, deploy |
| `tssc-nodejs` | Node.js application | Build, sign, SBOM, deploy |
| `tssc-python` | Python application | Build, sign, SBOM, deploy |

**When to use:** Customer cares about software supply chain security, SLSA compliance, or has regulatory requirements around artifact provenance.

**What makes these special:**
- Tekton pipelines with Tekton Chains for automatic attestation
- Artifact signing via Trusted Artifact Signer (Sigstore/cosign)
- SBOM generation in CycloneDX format
- SBOM analysis via Trusted Profile Analyzer
- Enterprise Contract policy verification

### 3. RHDH Standard Templates

**Source:** `redhat-developer/red-hat-developer-hub-software-templates` (GitHub)

Standard application templates with GitOps deployment.

| Template | Description | Deployment |
|---|---|---|
| `go` | Go application | Tekton + ArgoCD |
| `nodejs` | Node.js application | Tekton + ArgoCD |
| `python` | Python application | Tekton + ArgoCD |
| `spring-boot` | Spring Boot application | Tekton + ArgoCD |
| `quarkus` | Quarkus application | Tekton + ArgoCD |
| `argocd` | ArgoCD GitOps config | ArgoCD only |
| `tekton` | Tekton pipeline config | Tekton only |

**When to use:** Customer wants standard app development golden paths without the AI or TSSC focus.

## Catalog API Reference

### List All Templates

```bash
TOKEN=$(oc create token default -n rhdh-test 2>/dev/null || echo "NEEDS_TOKEN")

curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/catalog/entities?filter=kind=template" \
  | jq '[.[] | {name: .metadata.name, title: .metadata.title, type: .spec.type}]'
```

### List All Components (Scaffolded Apps)

```bash
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/catalog/entities?filter=kind=component" \
  | jq '[.[] | {name: .metadata.name, owner: .spec.owner, lifecycle: .spec.lifecycle}]'
```

### Get a Specific Template

```bash
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/catalog/entities/by-name/template/default/tssc-python" \
  | jq '{name: .metadata.name, description: .metadata.description, steps: [.spec.steps[].id]}'
```

### Trigger Scaffolding via API

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/scaffolder/v2/tasks" \
  -d '{
    "templateRef": "template:default/tssc-python",
    "values": {
      "component_id": "my-secure-app",
      "description": "Demo secure AI application",
      "owner": "user:default/dean",
      "repo": {
        "host": "github.com",
        "owner": "your-org",
        "name": "my-secure-app"
      }
    }
  }'
```

### Check Scaffolding Task Status

```bash
TASK_ID="<task-id-from-scaffold-response>"

curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/scaffolder/v2/tasks/${TASK_ID}" \
  | jq '{status: .status, steps: [.steps[] | {id: .id, status: .status}]}'
```

### List Task Events (Streaming)

```bash
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/scaffolder/v2/tasks/${TASK_ID}/events" \
  | jq '.[] | {type: .type, body: .body.message}'
```

## Dynamic Plugins

Check which plugins are loaded:

```bash
oc get configmap -n rhdh-test dynamic-plugins -o yaml 2>/dev/null | grep "package:" | sort
```

Key plugins for this demo:
- `@janus-idp/backstage-plugin-tekton` — pipeline visualization
- `@janus-idp/backstage-plugin-argocd` — GitOps status
- `@janus-idp/backstage-plugin-topology` — OpenShift topology view
- `@janus-idp/backstage-plugin-kubernetes` — K8s resource views

## Catalog Location Management

### List Registered Locations

```bash
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/catalog/locations" \
  | jq '.[] | {id: .id, type: .data.type, target: .data.target}'
```

### Register a New Catalog Location

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/catalog/locations" \
  -d '{
    "type": "url",
    "target": "https://github.com/your-org/your-repo/blob/main/catalog-info.yaml"
  }'
```

### Refresh an Entity

```bash
ENTITY_UID=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/catalog/entities/by-name/component/default/my-app" \
  | jq -r '.metadata.uid')

curl -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/catalog/entities/${ENTITY_UID}/refresh"
```

## Troubleshooting

### Template Not Appearing

```bash
# Check if the catalog location is registered
oc logs -n rhdh-test deploy/developer-hub --tail=200 | grep -i "catalog" | grep -i "error"

# Verify the template source URL is reachable
oc exec -n rhdh-test deploy/developer-hub -- curl -s -o /dev/null -w "%{http_code}" \
  "https://github.com/redhat-ai-dev/ai-lab-template"
```

### Scaffolding Fails

```bash
# Check recent scaffolder tasks
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/scaffolder/v2/tasks" \
  | jq '[.tasks[-5:] | .[] | {id: .id, status: .status, template: .spec.templateInfo.entity.metadata.name}]'

# Get error details for a failed task
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/scaffolder/v2/tasks/${TASK_ID}/events" \
  | jq '.[] | select(.body.stepId and .type == "log") | {step: .body.stepId, message: .body.message}'
```

### GitHub Auth Issues

```bash
# Check GitHub auth config exists
oc get secret -n rhdh-test -o name | grep -i github

# Verify RHDH can reach GitHub
oc exec -n rhdh-test deploy/developer-hub -- curl -s -o /dev/null -w "%{http_code}" \
  "https://api.github.com"
```

## Pre-Sales Talking Points

- **"How fast can a developer go from idea to running app?"** — With golden path templates, a developer selects a template, fills in a few fields, and gets a running app with CI/CD pipeline, GitOps, and supply chain security in under 5 minutes.
- **"What about standardization?"** — Templates encode your organization's best practices. Every app starts with the right pipeline, the right security controls, the right deployment pattern.
- **"Can we customize the templates?"** — Absolutely. Templates are YAML + Nunjucks. Platform teams own the templates and update them as standards evolve. Developers always get the latest.
- **"How does this compare to just using GitHub Actions?"** — Developer Hub gives you a service catalog, not just CI/CD. You get discoverability, ownership tracking, dependency mapping, and TechDocs — all in one place. The pipeline is just one piece.
