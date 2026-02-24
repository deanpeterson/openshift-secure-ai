# Konflux + Developer Hub: Developer Self-Service Demo

**Duration:** ~35-45 minutes
**Focus:** Scaffold a brand-new Python app from RHDH, watch Konflux build it, verify the full supply chain

## URLs & Credentials

| Resource | URL |
|----------|-----|
| RHDH | `https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com` |
| Konflux UI | `https://konflux-ui-konflux-ui.apps.salamander.aimlworkbench.com` |
| Quay | `https://quay-quay-quay-test.apps.salamander.aimlworkbench.com` |
| Dev Spaces | `https://devspaces.apps.salamander.aimlworkbench.com` |
| ArgoCD | `https://openshift-gitops-server-openshift-gitops.apps.salamander.aimlworkbench.com` |

| Service | Credentials |
|---------|-------------|
| Konflux UI | `admin@konflux.dev` / `password` |
| Quay | `quayadmin` / `Admin1234!` |

---

## Pre-Flight Checks (~10 min)

Run these before the demo to make sure everything is healthy.

### 1. Verify secrets in default-tenant

```bash
oc get secret pipelines-as-code-secret -n default-tenant -o name
oc get secret quay-push-secret -n default-tenant -o name
oc get configmap trusted-ca -n default-tenant -o name
```

All three must exist. `pipelines-as-code-secret` has the GitHub PAT for PaC. `quay-push-secret` has the Quay robot account credentials. `trusted-ca` has the cluster CA bundle for self-signed certs.

### 2. Verify no name collision

```bash
oc get applications.appstudio.redhat.com demo-python -n default-tenant 2>&1
oc get components.appstudio.redhat.com demo-python -n default-tenant 2>&1
```

Both should return "not found". If they exist, run cleanup (see bottom of this doc) first.

### 3. Verify RHDH is healthy

```bash
oc get pods -n rhdh-test -l app.kubernetes.io/name=developer-hub
```

Pod should be `Running` with `1/1` Ready.

Verify the Python template is loaded:

```bash
curl -sk https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/catalog/entities?filter=kind=template \
  -H "Authorization: Bearer Cnrggo63BFuxoP-_LxrPRMRngMlSFpBsPZKw3blu0OI" | \
  python3 -c "import sys,json; [print(t['metadata']['name']) for t in json.load(sys.stdin)]" | grep python
```

Should see `python-trusted-application` (or similar).

### 4. Verify ArgoCD apps healthy

```bash
oc get applications.argoproj.io -n tssc-gitops --no-headers
```

Existing apps should show `Healthy`/`Synced`.

### 5. Verify cluster capacity

```bash
oc adm top nodes
```

The Konflux build needs ~6.5 CPU total (the `step-build` alone requests 4600m). Make sure at least one node has capacity.

---

## Step 1: Show Starting State (3 min)

**Goal:** Prove nothing exists yet — we're creating from scratch.

### In the browser

1. **RHDH Catalog** — Search for "demo-python" in the catalog. Nothing found.
2. **Konflux UI** — Log in, show Applications page. No `demo-python` application.
3. **GitHub** — Go to `github.com/deanpeterson` — no `demo-python` or `demo-python-gitops` repos.
4. **Quay** — Go to `rhdh` org — no `demo-python` repository.

### From CLI

```bash
oc get applications.appstudio.redhat.com -n default-tenant --no-headers | grep demo-python
oc get components.appstudio.redhat.com -n default-tenant --no-headers | grep demo-python
oc get pipelineruns -n default-tenant --no-headers | grep demo-python
```

All empty — nothing exists.

> **Talking point:** We're starting with a completely clean slate. No repos, no pipelines, no images, no deployments. In the next step, we'll scaffold an entire application — source repo, gitops repo, CI pipeline, CD pipeline, and Konflux supply chain — from a single RHDH template.

---

## Step 2: Scaffold in RHDH (~5 min)

### Navigate to the template

1. Open RHDH: `https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com`
2. Click **Create** (left sidebar) or **Create...** button
3. Find the **Python** trusted application template
4. Click **Choose**

### Fill in the form

Use these exact values:

| Field | Value |
|-------|-------|
| **Name** | `demo-python` |
| **Owner** | `user:default/deanpeterson` |
| **Host Type** | GitHub |
| **Repository Name** | `demo-python` |
| **Branch** | `main` |
| **Repository Owner** | `deanpeterson` |
| **Repository Server** | `github.com` |
| **CI Provider** | Tekton (SLSA 3) |
| **Image Registry** | `quay-quay-quay-test.apps.salamander.aimlworkbench.com` |
| **Image Organization** | `rhdh` |
| **Image Name** | `demo-python` |
| **Deployment Namespace** | `tssc-app` |

> **CRITICAL:** The Image Registry must be the internal Quay hostname, NOT `quay.io`. This is the most common mistake.

5. Click **Review** then **Create**

### Watch the scaffolder execute

The scaffolder log shows each step:
- `fetch:template` — renders the template files
- `publish:github` — creates `deanpeterson/demo-python` on GitHub
- `publish:github` — creates `deanpeterson/demo-python-gitops` on GitHub
- `catalog:register` — registers the component in RHDH
- `argocd:create-resources` — creates ArgoCD Application resources
- `konflux:create-application` — creates Konflux Application + Component CRs

6. When done, click **Open Component in catalog**

> **Talking point:** One form submission just created two GitHub repos, registered a component in the developer portal, set up ArgoCD for GitOps deployment across dev/stage/prod, and onboarded the app into Konflux's trusted supply chain. The developer doesn't need to know any of the infrastructure details.

---

## Step 3: Explore What Was Created (~5 min)

### In the RHDH component page

Show each tab:
- **Overview** — links to source repo, gitops repo, Quay image
- **CI** — will show PipelineRuns once build starts
- **CD** — shows ArgoCD application sync status
- **Topology** — shows deployment topology (will be empty until first deploy)
- **Image Registry** — shows Quay image tags (empty until first build)

### On GitHub

1. `github.com/deanpeterson/demo-python` — source repo with:
   - Flask Python app scaffold
   - `catalog-info.yaml` with Backstage annotations
   - `.tekton/` directory with PaC pipeline definitions
   - `docker/Dockerfile`
2. `github.com/deanpeterson/demo-python-gitops` — gitops repo with:
   - Kustomize overlays for development, stage, prod
   - Helm chart or base manifests

### From CLI

```bash
# Konflux resources
oc get applications.appstudio.redhat.com demo-python -n default-tenant
oc get components.appstudio.redhat.com demo-python -n default-tenant

# ArgoCD apps (app-of-apps pattern)
oc get applications.argoproj.io -n tssc-gitops | grep demo-python

# PaC repositories
oc get repositories.pipelinesascode.tekton.dev -n default-tenant | grep demo-python
```

> **Talking point:** Everything is Kubernetes-native. The Konflux Application and Component are CRDs. ArgoCD apps are CRDs. PaC Repository is a CRD. The entire supply chain is declarative and auditable — you can `oc get` every piece of it.

---

## Step 4: Watch the Build (~10-15 min)

### How it starts

When the scaffolder pushed the `.tekton/` pipeline definition to the source repo, Pipelines as Code detected it and automatically triggered a PipelineRun. This usually starts within 1-2 minutes of scaffolding.

### In the browser

- **RHDH CI tab** — refresh to see the PipelineRun appear
- **Konflux UI** — navigate to `demo-python` Application > Activity tab

### From CLI — monitor progress

```bash
# Watch for the PipelineRun to appear
oc get pipelineruns -n default-tenant -l backstage.io/kubernetes-id=demo-python --watch

# Once running, check task progress
oc get taskruns -n default-tenant -l tekton.dev/pipelineRun=<pipelinerun-name> \
  --sort-by=.status.startTime
```

### Pipeline tasks (in order)

| Task | What it does | Duration |
|------|-------------|----------|
| `init` | Workspace setup | ~30s |
| `clone-repository` | Git clone from GitHub | ~30s |
| `prefetch-dependencies` | Dependency caching | ~1min |
| `build-container` | Buildah build + push to Quay | ~5-8min |
| `build-image-index` | OCI multi-arch manifest | ~1min |
| `inspect-image` | Inspect built image | ~30s |
| `label-check` | Verify image labels | ~15s |
| `deprecated-base-image-check` | Check for deprecated bases | ~30s |
| `ecosystem-cert-preflight-checks` | Red Hat certification checks | ~1min |
| `sast-snyk-check` | SAST scanning (may skip) | ~1min |
| `clamav-scan` | Virus scanning | ~1min |
| `apply-tags` | Tag image in registry | ~15s |
| `push-dockerfile` | Store Dockerfile artifact | ~15s |

### Troubleshooting

If the PipelineRun doesn't appear within 5 minutes:

```bash
# Check PaC repos
oc get repositories.pipelinesascode.tekton.dev -n default-tenant \
  -l app.kubernetes.io/part-of=demo-python -o yaml

# Check for scheduling issues (build needs 6.5 CPU)
oc get events -n default-tenant --field-selector reason=FailedScheduling --sort-by=.lastTimestamp

# Check PaC controller logs
oc logs deployment/pipelines-as-code-controller -n openshift-pipelines --tail=50 | grep demo-python
```

> **Talking point:** This is a full trusted software supply chain pipeline — not just a build. It includes vulnerability scanning, image inspection, SBOM generation, and compliance checks. Every image that comes out of this pipeline has a verifiable provenance chain. The build uses 6.5 CPU because Buildah creates a hermetic, reproducible build.

---

## Step 5: Konflux Lifecycle (~5 min, during the build)

While the build runs, show the Konflux CRDs that track the supply chain.

### Component status

```bash
oc get components.appstudio.redhat.com demo-python -n default-tenant -o yaml
```

Key fields:
- `spec.source.git.url` — the source repo
- `spec.containerImage` — the target image in Quay
- `status.conditions` — component health

### After build completes — Snapshots

```bash
oc get snapshots.appstudio.redhat.com -n default-tenant -l appstudio.openshift.io/application=demo-python
```

A Snapshot is an immutable record created after a successful build:
- Contains the exact image digest (`@sha256:...`)
- Links to the exact git commit
- Triggers IntegrationTests if configured

### IntegrationTestScenarios

```bash
oc get integrationtestscenarios.appstudio.redhat.com -n default-tenant
```

### Release pipeline

```bash
oc get releases.appstudio.redhat.com -n default-tenant -l appstudio.openshift.io/application=demo-python
```

> **Talking point:** Konflux models the entire supply chain as Kubernetes resources. Application groups Components. A successful build creates an immutable Snapshot. Snapshots trigger IntegrationTests. Passing tests trigger Releases. Every step is auditable, declarative, and git-driven.

---

## Step 6: Image in Quay (~2 min)

### In the browser

1. **RHDH Image Registry tab** — should show the pushed image with tags
2. **Quay UI** — navigate to `rhdh/demo-python` repository
   - Show the image tags (commit SHA tags)
   - Show the image layers and size
   - Click a tag to see the manifest

### From CLI

```bash
# Verify the image exists (use --tls-verify=false for self-signed cert)
skopeo list-tags \
  --tls-verify=false \
  docker://quay-quay-quay-test.apps.salamander.aimlworkbench.com/rhdh/demo-python
```

> **Talking point:** Every image is tagged with the exact git commit SHA, giving full traceability from image back to source. The image is stored in our internal Quay registry with digest pinning — no mutable `latest` tag that can be silently overwritten.

---

## Step 7: GitOps Deployment (~3 min)

### Check ArgoCD apps

```bash
oc get applications.argoproj.io -n tssc-gitops | grep demo-python
```

The app-of-apps pattern creates:
- `demo-python-app-of-apps` — parent
- `demo-python-ci` — CI namespace resources
- `demo-python-development` — dev deployment
- `demo-python-stage` — staging deployment
- `demo-python-prod` — production deployment

### In the browser

1. **RHDH CD tab** — shows ArgoCD sync status
2. **RHDH Topology tab** — shows the deployment graph
3. **GitHub gitops repo** — show commits from the pipeline updating the image digest

### Check the running deployment

```bash
# Check if the app deployed to development
oc get deployment -n tssc-app -l app.kubernetes.io/name=demo-python
oc get pods -n tssc-app -l app.kubernetes.io/name=demo-python
oc get route -n tssc-app -l app.kubernetes.io/name=demo-python
```

If a route exists, hit it:

```bash
ROUTE=$(oc get route demo-python -n tssc-app -o jsonpath='{.spec.host}' 2>/dev/null)
[ -n "$ROUTE" ] && curl -sk "https://$ROUTE"
```

> **Talking point:** The pipeline didn't just build the image — it updated the gitops repo with the new image digest. ArgoCD detected the change and deployed it automatically. The developer pushed code, and minutes later it's running in the cluster. That's the golden path.

---

## Step 8 (Optional): Dev Spaces (~5 min)

### Open from RHDH

1. On the component page, click the **Open in Dev Spaces** link (or the Dev Spaces icon)
2. Wait for the workspace to provision (~2-3 minutes)
3. You're now in a VS Code-like editor running in the cluster

### Make a code change

1. Edit `app.py` or a template — something visible
2. Commit and push

### Watch the new build

```bash
oc get pipelineruns -n default-tenant -l backstage.io/kubernetes-id=demo-python --watch
```

A new PipelineRun triggers automatically from the push.

> **Talking point:** Dev Spaces gives every developer a consistent, pre-configured development environment running in the cluster. No "works on my machine" issues. And because it's integrated with PaC, every push automatically triggers the full supply chain pipeline.

---

## Cleanup

Run these commands to remove all demo resources:

```bash
# Delete Konflux resources
oc delete components.appstudio.redhat.com demo-python -n default-tenant
oc delete applications.appstudio.redhat.com demo-python -n default-tenant
oc delete snapshots.appstudio.redhat.com -n default-tenant \
  -l appstudio.openshift.io/application=demo-python

# Delete PaC repositories
oc delete repositories.pipelinesascode.tekton.dev -n default-tenant \
  -l app.kubernetes.io/part-of=demo-python

# Delete PipelineRuns
oc delete pipelineruns -n default-tenant -l backstage.io/kubernetes-id=demo-python

# Delete ArgoCD apps
oc delete applications.argoproj.io demo-python-app-of-apps -n tssc-gitops
oc delete applications.argoproj.io -n tssc-gitops -l app.kubernetes.io/part-of=demo-python

# Delete deployments (if any)
oc delete all -n tssc-app -l app.kubernetes.io/name=demo-python

# Unregister from RHDH catalog (via API)
# Find the entity UID first, then:
# curl -sk -X DELETE "https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/catalog/entities/by-uid/<UID>" \
#   -H "Authorization: Bearer Cnrggo63BFuxoP-_LxrPRMRngMlSFpBsPZKw3blu0OI"

# Delete GitHub repos (manual or via gh CLI)
# gh repo delete deanpeterson/demo-python --yes
# gh repo delete deanpeterson/demo-python-gitops --yes
```

> **Note:** Delete Konflux Component before Application — the Component has a finalizer that cleans up PaC resources.

---

## Architecture Diagram

```
Developer clicks "Create" in RHDH
        |
        v
RHDH Scaffolder runs template actions
  ├── Creates source repo (demo-python) on GitHub
  │     └── Contains: Flask app, .tekton/ pipelines, catalog-info.yaml, Dockerfile
  ├── Creates gitops repo (demo-python-gitops) on GitHub
  │     └── Contains: Kustomize overlays (dev/stage/prod)
  ├── Registers component in RHDH catalog
  ├── Creates ArgoCD Application CRs (app-of-apps)
  └── Creates Konflux Application + Component CRs
        |
        v
Pipelines as Code detects .tekton/ in repo
        |
        v
PipelineRun in default-tenant namespace
  ├── clone-repository
  ├── build-container (buildah → push to Quay)
  ├── vulnerability scanning (SAST, ClamAV)
  ├── image inspection + label checks
  ├── apply-tags + push-dockerfile
  └── update-gitops-repo (image digest → gitops repo)
        |
        v
Konflux integration-service creates Snapshot
  (immutable: image digest + git commit)
        |
        v
ArgoCD detects gitops repo change → deploys to cluster
        |
        v
App running in tssc-app namespace
  (visible in RHDH Topology tab)
```

---

## Key Talking Points

1. **One form, full supply chain** — A developer fills in one template form and gets: source repo, gitops repo, CI pipeline, CD pipeline, supply chain tracking, and a running deployment.

2. **Everything is Kubernetes-native** — Applications, Components, Snapshots, PipelineRuns, ArgoCD Apps — all CRDs. Fully declarative, auditable, GitOps-friendly.

3. **Trusted by default** — Every build includes vulnerability scanning, SBOM generation, image signing, and compliance checks. SLSA Level 3 provenance.

4. **Developer self-service** — Developers don't configure infrastructure. They pick a template, fill in a form, and start coding. The platform team maintains the templates and infrastructure.

5. **Inner loop + outer loop** — Dev Spaces provides the inner loop (code-test-debug in-cluster). PaC + Konflux provide the outer loop (build-scan-deploy on every push).
