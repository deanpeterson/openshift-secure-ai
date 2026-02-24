# Konflux + Developer Hub Demo: AI Assistant Script

> **How to use:** Paste this file's content to Claude Code (or reference it) and say "Run the demo".
> Claude will execute CLI checks automatically, tell you when to do browser actions, wait for your confirmation, then verify what happened.

---

## Instructions for Claude

You are guiding a live demo of the Konflux + Developer Hub developer self-service workflow. Follow this script step by step:

- **[VERIFY: ...]** — Run these CLI commands automatically and report findings to the user
- **[ACTION: ...]** — Tell the user what to do in the browser, then wait for them to say "done" or "next"
- **[EXPLAIN: ...]** — Share this talking point with the user
- After each VERIFY block, summarize what the output means — don't just dump raw CLI output
- If something looks wrong, flag it and suggest troubleshooting steps
- Track timing — note when each step starts and how long the build takes

### Environment Reference

| Resource | URL |
|----------|-----|
| RHDH | `https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com` |
| Konflux UI | `https://konflux-ui-konflux-ui.apps.salamander.aimlworkbench.com` |
| Quay | `https://quay-quay-quay-test.apps.salamander.aimlworkbench.com` |
| Dev Spaces | `https://devspaces.apps.salamander.aimlworkbench.com` |

| Service | Credentials |
|---------|-------------|
| Konflux UI | `admin@konflux.dev` / `password` |
| Quay | `quayadmin` / `Admin1234!` |

RHDH API token: `Cnrggo63BFuxoP-_LxrPRMRngMlSFpBsPZKw3blu0OI`

---

## Pre-Flight Checks (Automated)

> Claude runs all of these automatically and reports a summary.

### [VERIFY: Required secrets exist in default-tenant]

```bash
echo "=== Checking required secrets ==="
for secret in pipelines-as-code-secret quay-push-secret; do
  if oc get secret "$secret" -n default-tenant -o name 2>/dev/null; then
    echo "  OK: $secret exists"
  else
    echo "  FAIL: $secret MISSING"
  fi
done
if oc get configmap trusted-ca -n default-tenant -o name 2>/dev/null; then
  echo "  OK: trusted-ca ConfigMap exists"
else
  echo "  FAIL: trusted-ca ConfigMap MISSING"
fi
```

**What to look for:** All three must show OK.
- `pipelines-as-code-secret` — GitHub PAT used by Pipelines as Code to clone repos and report status
- `quay-push-secret` — Quay robot account credentials for pushing built images
- `trusted-ca` — CA bundle so build tasks trust the cluster's self-signed certificates

### [VERIFY: No demo-python name collision]

```bash
echo "=== Checking for name collisions ==="
for kind in applications.appstudio.redhat.com components.appstudio.redhat.com; do
  if oc get "$kind" demo-python -n default-tenant 2>/dev/null; then
    echo "  WARNING: $kind/demo-python already exists — run cleanup first"
  else
    echo "  OK: no $kind/demo-python"
  fi
done

# Also check GitHub
if command -v gh &>/dev/null; then
  for repo in demo-python demo-python-gitops; do
    if gh repo view "deanpeterson/$repo" &>/dev/null 2>&1; then
      echo "  WARNING: GitHub repo deanpeterson/$repo already exists"
    else
      echo "  OK: no deanpeterson/$repo repo"
    fi
  done
fi
```

**What to look for:** All should show OK. If anything shows WARNING, run the cleanup section at the bottom first.

### [VERIFY: RHDH is healthy and template is loaded]

```bash
echo "=== Checking RHDH ==="
oc get pods -n rhdh-test -l app.kubernetes.io/name=developer-hub -o wide --no-headers

echo ""
echo "=== Checking for Python template ==="
curl -sk https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/api/catalog/entities?filter=kind=template \
  -H "Authorization: Bearer Cnrggo63BFuxoP-_LxrPRMRngMlSFpBsPZKw3blu0OI" | \
  python3 -c "
import sys, json
templates = json.load(sys.stdin)
python_templates = [t['metadata']['name'] for t in templates if 'python' in t['metadata']['name'].lower()]
if python_templates:
    print(f'  OK: Found Python template(s): {python_templates}')
else:
    all_names = [t['metadata']['name'] for t in templates]
    print(f'  WARNING: No Python template found. Available: {all_names}')
"
```

**What to look for:** RHDH pod should be `Running 1/1`. A Python template (like `python-trusted-application`) should be listed.

### [VERIFY: ArgoCD apps healthy]

```bash
echo "=== ArgoCD applications in tssc-gitops ==="
oc get applications.argoproj.io -n tssc-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers 2>/dev/null || echo "  No ArgoCD apps found in tssc-gitops (that's OK if this is a fresh setup)"
```

**What to look for:** Any existing apps should show `Synced` / `Healthy`. Don't worry if there are none — we're about to create them.

### [VERIFY: Cluster CPU capacity]

```bash
echo "=== Node CPU capacity ==="
oc adm top nodes 2>/dev/null || echo "  (metrics-server may not be available)"
echo ""
echo "NOTE: Konflux build needs ~6.5 CPU total (step-build alone requests 4600m)"
```

**What to look for:** At least one node should have 6.5+ CPU available. If capacity is tight, the build pod may get stuck in `Pending`.

### Pre-flight summary

> Claude: After running all checks, provide a summary like:
> "Pre-flight complete. All secrets present, no name collisions, RHDH healthy with Python template loaded, cluster has capacity. Ready to proceed."
> Or flag any issues that need attention before continuing.

---

## Step 1: Show Starting State (3 min)

### [ACTION: Show empty state in browser]

Open these four tabs and show that `demo-python` doesn't exist anywhere:

1. **RHDH Catalog** — `https://v1-developer-hub-rhdh-test.apps.salamander.aimlworkbench.com/catalog` — search for "demo-python"
2. **Konflux UI** — `https://konflux-ui-konflux-ui.apps.salamander.aimlworkbench.com` — login with `admin@konflux.dev` / `password`, check Applications page
3. **GitHub** — `https://github.com/deanpeterson?tab=repositories` — no demo-python repos
4. **Quay** — `https://quay-quay-quay-test.apps.salamander.aimlworkbench.com/organization/rhdh` — no demo-python image

Say **"done"** when you've shown all four.

### [VERIFY: Confirm clean state from CLI]

```bash
echo "=== Confirming clean state ==="
echo "Konflux Applications:"
oc get applications.appstudio.redhat.com -n default-tenant --no-headers 2>/dev/null | grep demo-python || echo "  (none)"
echo "Konflux Components:"
oc get components.appstudio.redhat.com -n default-tenant --no-headers 2>/dev/null | grep demo-python || echo "  (none)"
echo "PipelineRuns:"
oc get pipelineruns -n default-tenant --no-headers 2>/dev/null | grep demo-python || echo "  (none)"
echo "ArgoCD apps:"
oc get applications.argoproj.io -n tssc-gitops --no-headers 2>/dev/null | grep demo-python || echo "  (none)"
```

**What to look for:** Everything should show `(none)`.

### [EXPLAIN]

> We're starting with a completely clean slate. No repos, no pipelines, no images, no deployments. In the next step, a developer fills in one form in the Developer Hub and gets an entire application — source repo, gitops repo, CI pipeline, CD pipeline, supply chain tracking, and eventually a running deployment.

---

## Step 2: Scaffold in RHDH (~5 min)

### [ACTION: Navigate to the template]

1. In RHDH, click **Create** in the left sidebar
2. Find the **Python** trusted application template
3. Click **Choose**

### [ACTION: Fill in the scaffolding form]

Use these **exact** values:

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

> **CRITICAL:** The Image Registry must be the internal Quay hostname (`quay-quay-quay-test.apps...`), NOT `quay.io`. This is the most common mistake.

Click **Review** then **Create**.

Say **"done"** when the scaffolder starts running.

### [ACTION: Watch the scaffolder execute]

Watch the scaffolder log. You should see steps like:
- `fetch:template` — renders the template files
- `publish:github` — creates source repo
- `publish:github` — creates gitops repo
- `catalog:register` — registers in RHDH catalog
- `argocd:create-resources` — creates ArgoCD apps
- `konflux:create-application` — creates Konflux CRs

When all steps are green, click **"Open Component in catalog"**.

Say **"done"** when you're on the component page.

### [VERIFY: Confirm scaffolded resources exist]

```bash
echo "=== Checking Konflux resources ==="
oc get applications.appstudio.redhat.com demo-python -n default-tenant -o custom-columns=NAME:.metadata.name,CREATED:.metadata.creationTimestamp --no-headers 2>/dev/null || echo "  FAIL: Application not found"
oc get components.appstudio.redhat.com demo-python -n default-tenant -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containerImage --no-headers 2>/dev/null || echo "  FAIL: Component not found"

echo ""
echo "=== Checking ArgoCD apps ==="
oc get applications.argoproj.io -n tssc-gitops --no-headers 2>/dev/null | grep demo-python || echo "  (no ArgoCD apps yet — may take a moment)"

echo ""
echo "=== Checking PaC Repository CRs ==="
oc get repositories.pipelinesascode.tekton.dev -n default-tenant --no-headers 2>/dev/null | grep demo-python || echo "  (no PaC repos yet — may take a moment)"

echo ""
echo "=== Checking GitHub repos ==="
if command -v gh &>/dev/null; then
  gh repo view deanpeterson/demo-python --json name,url -q '.url' 2>/dev/null && echo "  OK: source repo exists" || echo "  (source repo not found yet)"
  gh repo view deanpeterson/demo-python-gitops --json name,url -q '.url' 2>/dev/null && echo "  OK: gitops repo exists" || echo "  (gitops repo not found yet)"
fi
```

**What to look for:**
- Konflux `Application` and `Component` CRs should exist in `default-tenant`
- Component's `containerImage` should point to `quay-quay-quay-test.apps.salamander.aimlworkbench.com/rhdh/demo-python`
- ArgoCD apps for demo-python should be appearing in `tssc-gitops`
- PaC Repository CRs link the GitHub repos to the pipeline system
- Both GitHub repos should exist

### [EXPLAIN]

> One form submission just created: two GitHub repos (source + gitops), a component in the developer portal, ArgoCD applications for GitOps deployment across environments, and Konflux Application + Component CRs for supply chain tracking. The developer doesn't need to know any of the infrastructure details.

---

## Step 3: Explore What Was Created (~5 min)

### [ACTION: Browse the RHDH component page]

On the demo-python component page, click through each tab:

1. **Overview** — links to source repo, gitops repo, Quay image
2. **CI** — PipelineRuns (may be empty or showing a running build)
3. **CD** — ArgoCD application sync status
4. **Topology** — deployment graph (empty until first deploy)
5. **Image Registry** — Quay tags (empty until first build)

Also open the GitHub repos:
- `https://github.com/deanpeterson/demo-python` — note the `.tekton/` directory, `docker/Dockerfile`, `catalog-info.yaml`
- `https://github.com/deanpeterson/demo-python-gitops` — note the Kustomize overlays

Say **"done"** when you've explored.

### [VERIFY: Dump Konflux CR details]

```bash
echo "=== Konflux Application details ==="
oc get applications.appstudio.redhat.com demo-python -n default-tenant -o yaml | grep -A5 "spec:" | head -10

echo ""
echo "=== Konflux Component details ==="
oc get components.appstudio.redhat.com demo-python -n default-tenant -o jsonpath='{
  "Source": "{.spec.source.git.url}",
  "Image": "{.spec.containerImage}",
  "Dockerfile": "{.spec.source.git.dockerfileUrl}"
}' 2>/dev/null
echo ""

echo ""
echo "=== ArgoCD app status ==="
oc get applications.argoproj.io -n tssc-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers 2>/dev/null | grep demo-python

echo ""
echo "=== PaC Repository CRs ==="
oc get repositories.pipelinesascode.tekton.dev -n default-tenant -o custom-columns=NAME:.metadata.name,URL:.spec.url --no-headers 2>/dev/null | grep demo-python
```

**What to look for:**
- The Component links the source git repo to the target container image
- ArgoCD apps follow the app-of-apps pattern: `demo-python-app-of-apps` (parent), plus per-environment apps (ci, development, stage, prod)
- PaC Repository CRs bind each GitHub repo to the `default-tenant` namespace so PaC knows where to create PipelineRuns

### [EXPLAIN]

> Everything is Kubernetes-native. The Konflux Application and Component are CRDs. ArgoCD apps are CRDs. PaC Repository is a CRD. You can `oc get` every piece of the supply chain. This is what makes it GitOps-friendly and auditable.

---

## Step 4: Watch the Build (~10-15 min)

### [VERIFY: Check if a PipelineRun has started]

```bash
echo "=== PipelineRuns for demo-python ==="
oc get pipelineruns -n default-tenant -l backstage.io/kubernetes-id=demo-python \
  -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].reason,STARTED:.status.startTime --no-headers 2>/dev/null

if [ $? -ne 0 ] || [ -z "$(oc get pipelineruns -n default-tenant -l backstage.io/kubernetes-id=demo-python --no-headers 2>/dev/null)" ]; then
  echo "  No PipelineRun yet — checking broader label..."
  oc get pipelineruns -n default-tenant --no-headers 2>/dev/null | grep demo-python || echo "  Still no PipelineRun. It may take 1-2 minutes after scaffolding."
fi
```

**What to look for:** A PipelineRun should appear within 1-2 minutes of scaffolding. It starts when PaC detects the `.tekton/` pipeline definition in the new repo.

If no PipelineRun appears after 5 minutes, troubleshoot:

```bash
# Check PaC controller for errors
oc logs deployment/pipelines-as-code-controller -n openshift-pipelines --tail=30 2>/dev/null | grep -i "demo-python\|error"

# Check for scheduling issues (build needs 6.5 CPU)
oc get events -n default-tenant --field-selector reason=FailedScheduling --sort-by=.lastTimestamp 2>/dev/null | tail -5
```

### [ACTION: Watch the build in the browser]

Go to the **CI tab** in RHDH (or the **Activity tab** in Konflux UI) to watch the PipelineRun progress.

You can also watch from the CLI — I'll monitor the TaskRuns.

### [VERIFY: Monitor TaskRun progress]

> Claude: Run this periodically (every 30-60 seconds) while the build is running, and report which tasks have completed.

```bash
# Get the PipelineRun name
PR_NAME=$(oc get pipelineruns -n default-tenant -l backstage.io/kubernetes-id=demo-python -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$PR_NAME" ]; then
  echo "=== PipelineRun: $PR_NAME ==="
  echo ""
  echo "Task progress:"
  oc get taskruns -n default-tenant -l tekton.dev/pipelineRun="$PR_NAME" \
    -o custom-columns=TASK:.metadata.labels.tekton\.dev/pipelineTask,STATUS:.status.conditions[0].reason,DURATION:.status.completionTime \
    --sort-by=.status.startTime --no-headers 2>/dev/null
  echo ""
  echo "PipelineRun status:"
  oc get pipelinerun "$PR_NAME" -n default-tenant \
    -o jsonpath='Status: {.status.conditions[0].reason} — {.status.conditions[0].message}' 2>/dev/null
  echo ""
else
  echo "  No PipelineRun found yet"
fi
```

**What to look for:**
- Tasks complete in order: init → clone → prefetch → build-container → build-image-index → inspect/scan → apply-tags
- `build-container` is the longest task (5-8 minutes) — this is the buildah build
- `Succeeded` means the task completed OK
- `Running` means it's in progress
- If a task shows `Failed`, check its logs:
  ```bash
  oc logs -n default-tenant <taskrun-name> --all-containers 2>/dev/null | tail -30
  ```

### [EXPLAIN]

> This is a full trusted software supply chain pipeline — not just a build. It includes vulnerability scanning, image inspection, SBOM generation, and compliance checks. The build uses ~6.5 CPU because Buildah creates a hermetic, reproducible build environment. Every image that comes out has verifiable provenance.

---

## Step 5: Konflux Lifecycle (~5 min, during the build)

> Claude: Run these checks while the build is in progress to explain the Konflux CRD model.

### [VERIFY: Component status]

```bash
echo "=== Component conditions ==="
oc get components.appstudio.redhat.com demo-python -n default-tenant \
  -o jsonpath='{range .status.conditions[*]}Type: {.type}, Status: {.status}, Reason: {.reason}
{end}' 2>/dev/null
```

**What to look for:** The Component tracks the build pipeline. Look for conditions like `Updated` and `GitOpsResourcesGenerated`.

### [VERIFY: Check for Snapshots (after build completes)]

```bash
echo "=== Snapshots for demo-python ==="
oc get snapshots.appstudio.redhat.com -n default-tenant \
  -l appstudio.openshift.io/application=demo-python \
  -o custom-columns=NAME:.metadata.name,CREATED:.metadata.creationTimestamp --no-headers 2>/dev/null || echo "  No snapshots yet (created after successful build)"
```

**What to look for:** A Snapshot appears after a successful build. It's an immutable record containing:
- The exact image digest (`@sha256:...`) — not a mutable tag
- The exact git commit that was built
- Used as input for IntegrationTests and Release pipelines

### [VERIFY: IntegrationTestScenarios and Releases]

```bash
echo "=== IntegrationTestScenarios ==="
oc get integrationtestscenarios.appstudio.redhat.com -n default-tenant --no-headers 2>/dev/null || echo "  (none configured)"

echo ""
echo "=== Releases ==="
oc get releases.appstudio.redhat.com -n default-tenant \
  -l appstudio.openshift.io/application=demo-python --no-headers 2>/dev/null || echo "  (none yet)"

echo ""
echo "=== ReleasePlans ==="
oc get releaseplans.appstudio.redhat.com -n default-tenant --no-headers 2>/dev/null || echo "  (none configured)"
```

**What to look for:**
- **IntegrationTestScenarios** define tests that run against each Snapshot (e.g., smoke tests, integration tests)
- **Releases** are created when a Snapshot passes all integration tests
- **ReleasePlans** define where releases go (e.g., which registry, which environment)
- These may not be configured for the demo — that's OK. The key point is the model supports it.

### [EXPLAIN]

> Konflux models the entire supply chain as Kubernetes resources. Application groups Components. A successful build creates an immutable Snapshot. Snapshots trigger IntegrationTests. Passing tests trigger Releases. Every step is auditable, declarative, and git-driven. This is how you get SLSA Level 3 provenance.

---

## Step 6: Image in Quay (~2 min)

> Wait for the build to complete before this step.

### [VERIFY: Confirm image exists in Quay]

```bash
echo "=== Checking Quay for demo-python image ==="
skopeo list-tags --tls-verify=false \
  docker://quay-quay-quay-test.apps.salamander.aimlworkbench.com/rhdh/demo-python 2>/dev/null

if [ $? -ne 0 ]; then
  echo "  skopeo failed — trying curl to Quay API..."
  curl -sk "https://quay-quay-quay-test.apps.salamander.aimlworkbench.com/api/v1/repository/rhdh/demo-python/tag/" | \
    python3 -c "import sys,json; tags=json.load(sys.stdin).get('tags',[]); [print(f'  Tag: {t[\"name\"]}') for t in tags[:10]]" 2>/dev/null || echo "  Could not check tags"
fi
```

**What to look for:** You should see tags like:
- A commit SHA tag (e.g., `abc1234`) — links the image to the exact source commit
- Possibly a `latest` or build-number tag

### [ACTION: Check image in the browser]

1. **RHDH Image Registry tab** — click it on the demo-python component page. Should show the pushed image with tags.
2. **Quay UI** — go to `https://quay-quay-quay-test.apps.salamander.aimlworkbench.com/repository/rhdh/demo-python`
   - Show the image tags
   - Click a tag to see the manifest and layers

Say **"done"** when you've shown the image.

### [EXPLAIN]

> Every image is tagged with the exact git commit SHA, giving full traceability from image back to source. No mutable `latest` tag that can be silently overwritten. In production, the image would also have a cosign signature and SLSA provenance attestation stored alongside it.

---

## Step 7: GitOps Deployment (~3 min)

### [VERIFY: Check ArgoCD app status]

```bash
echo "=== ArgoCD apps for demo-python ==="
oc get applications.argoproj.io -n tssc-gitops \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers 2>/dev/null | grep demo-python
```

**What to look for:** The app-of-apps pattern creates:
- `demo-python-app-of-apps` — parent application
- `demo-python-ci` — CI namespace resources
- `demo-python-development` — dev deployment
- `demo-python-stage` — staging
- `demo-python-prod` — production

### [VERIFY: Check running deployment]

```bash
echo "=== Deployment in tssc-app ==="
oc get deployment -n tssc-app -l app.kubernetes.io/name=demo-python --no-headers 2>/dev/null || echo "  No deployment yet"

echo ""
echo "=== Pods ==="
oc get pods -n tssc-app -l app.kubernetes.io/name=demo-python --no-headers 2>/dev/null || echo "  No pods yet"

echo ""
echo "=== Route ==="
oc get route -n tssc-app -l app.kubernetes.io/name=demo-python --no-headers 2>/dev/null || echo "  No route yet"

# Try to hit the route
ROUTE=$(oc get route demo-python -n tssc-app -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$ROUTE" ]; then
  echo ""
  echo "=== Testing route: https://$ROUTE ==="
  curl -sk "https://$ROUTE" | head -5
fi
```

**What to look for:** After ArgoCD syncs the gitops repo, you should see a Deployment, Pod(s), and potentially a Route in the `tssc-app` namespace. The pipeline updated the gitops repo with the new image digest, and ArgoCD deployed it.

### [ACTION: Check deployment in RHDH]

1. **CD tab** — shows ArgoCD sync status for each environment
2. **Topology tab** — shows the visual deployment graph
3. **GitHub gitops repo** — check recent commits, the pipeline should have pushed an image digest update

Say **"done"** when you've explored.

### [EXPLAIN]

> The pipeline didn't just build the image — it updated the gitops repo with the new image digest. ArgoCD detected the change and deployed it automatically. The developer pushed code, and minutes later it's running in the cluster. That's the golden path: from code push to running deployment, fully automated, fully auditable.

---

## Step 8 (Optional): Dev Spaces (~5 min)

### [ACTION: Open Dev Spaces from RHDH]

1. On the demo-python component page in RHDH, look for the **Dev Spaces** link or icon
2. Click it to open a workspace
3. Wait ~2-3 minutes for the workspace to provision
4. Once in the editor, make a small code change (e.g., edit `app.py` to change a response string)
5. Commit and push the change

Say **"done"** when you've pushed the change.

### [VERIFY: Watch for new PipelineRun]

```bash
echo "=== Watching for new PipelineRun ==="
oc get pipelineruns -n default-tenant -l backstage.io/kubernetes-id=demo-python \
  -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].reason,STARTED:.status.startTime \
  --sort-by=.status.startTime --no-headers 2>/dev/null
```

**What to look for:** A new PipelineRun should appear within 1-2 minutes of the push. PaC detects the push to `main` and triggers the pipeline automatically.

### [EXPLAIN]

> Dev Spaces gives every developer a consistent, pre-configured development environment running in the cluster. No "works on my machine" issues. And because it's integrated with Pipelines as Code, every push automatically triggers the full supply chain pipeline. Inner loop (code in Dev Spaces) feeds directly into outer loop (build, scan, deploy).

---

## Demo Complete!

### Summary

> Claude: Provide a summary of what was demonstrated:

Here's what we just did:
1. **Started from nothing** — no repos, no pipelines, no images, no deployments
2. **One form in Developer Hub** created: source repo, gitops repo, CI pipeline, CD pipeline, Konflux supply chain tracking, and RHDH catalog entry
3. **Pipelines as Code** automatically triggered a trusted build pipeline with vulnerability scanning, SBOM generation, and compliance checks
4. **Konflux** tracked the entire supply chain: Application → Component → PipelineRun → Snapshot
5. **Image pushed to Quay** with commit-SHA tags for full traceability
6. **ArgoCD deployed** the app automatically via GitOps
7. **All visible** in a single developer portal (RHDH)

**Key message:** Developer self-service at enterprise scale. Developers fill in a form and start coding. Platform teams maintain the templates, pipelines, and infrastructure. Security is built in, not bolted on.

---

## Cleanup

> Claude: Run these when the user says "cleanup" or "clean up".

```bash
echo "=== Starting cleanup ==="

# Delete Konflux Component first (has finalizer that cleans up PaC resources)
echo "Deleting Konflux Component..."
oc delete components.appstudio.redhat.com demo-python -n default-tenant --ignore-not-found

echo "Deleting Konflux Application..."
oc delete applications.appstudio.redhat.com demo-python -n default-tenant --ignore-not-found

echo "Deleting Snapshots..."
oc delete snapshots.appstudio.redhat.com -n default-tenant \
  -l appstudio.openshift.io/application=demo-python --ignore-not-found

echo "Deleting PaC Repositories..."
oc delete repositories.pipelinesascode.tekton.dev -n default-tenant \
  -l app.kubernetes.io/part-of=demo-python --ignore-not-found

echo "Deleting PipelineRuns..."
oc delete pipelineruns -n default-tenant -l backstage.io/kubernetes-id=demo-python --ignore-not-found

echo "Deleting ArgoCD apps..."
oc delete applications.argoproj.io demo-python-app-of-apps -n tssc-gitops --ignore-not-found
oc delete applications.argoproj.io -n tssc-gitops -l app.kubernetes.io/part-of=demo-python --ignore-not-found

echo "Deleting deployments in tssc-app..."
oc delete all -n tssc-app -l app.kubernetes.io/name=demo-python --ignore-not-found

echo ""
echo "=== Cleanup complete ==="
echo ""
echo "Manual steps remaining:"
echo "  1. Delete GitHub repos:"
echo "     gh repo delete deanpeterson/demo-python --yes"
echo "     gh repo delete deanpeterson/demo-python-gitops --yes"
echo "  2. Unregister from RHDH catalog (via API or UI)"
echo "  3. Delete Quay repo: rhdh/demo-python (via Quay UI)"
```

> **Important:** Delete the Component before the Application — the Component's finalizer handles PaC cleanup. Deleting the Application first can leave orphaned PaC resources.

---

## Troubleshooting Reference

### PipelineRun stuck in Pending

```bash
# Check for scheduling issues
oc get events -n default-tenant --field-selector reason=FailedScheduling --sort-by=.lastTimestamp | tail -5

# Check node capacity
oc adm top nodes

# The build needs ~6.5 CPU. If nodes are full, scale up or wait.
```

### PipelineRun failed

```bash
# Get the failed TaskRun
PR_NAME=$(oc get pipelineruns -n default-tenant -l backstage.io/kubernetes-id=demo-python -o jsonpath='{.items[0].metadata.name}')
FAILED_TR=$(oc get taskruns -n default-tenant -l tekton.dev/pipelineRun="$PR_NAME" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[0].reason}{"\n"}{end}' | grep Failed | awk '{print $1}')

echo "Failed TaskRun: $FAILED_TR"
oc logs -n default-tenant "$FAILED_TR" --all-containers 2>/dev/null | tail -50
```

### build-container fails with TLS error

The internal Quay uses self-signed certs. Check that `trusted-ca` ConfigMap is mounted and `TLSVERIFY=false` is set in the buildah task.

### PaC not triggering

```bash
# Check PaC controller logs
oc logs deployment/pipelines-as-code-controller -n openshift-pipelines --tail=50 | grep demo-python

# Check the Repository CR
oc get repositories.pipelinesascode.tekton.dev -n default-tenant -l app.kubernetes.io/part-of=demo-python -o yaml
```

### RHDH tabs empty

Ensure `catalog-info.yaml` has the annotation `backstage.io/kubernetes-namespace: default-tenant`. The K8s backend plugin uses this to find resources.
