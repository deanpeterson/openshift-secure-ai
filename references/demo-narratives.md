# Demo Narratives

Audience-specific talk tracks for live demos. Each follows the same platform flow
but emphasizes different value props.

---

## 1. CISO / Security Leader

**Theme:** "Compliance without compromise"

**Opening hook:** "Your developers are shipping AI applications. How do you know what's inside those containers, who built them, and whether they've been tampered with?"

### Walk-Through

**Step 1 — Show the problem (1 min)**
"Most organizations have a gap between what security wants and what developers actually do. Let me show you how Red Hat closes that gap."

**Step 2 — Scaffold a secure app (2 min)**
Open Developer Hub → Create from TSSC Python template.
"This template was built by the platform team. Every app that starts here gets supply chain security by default. The developer didn't have to ask for it, configure it, or even know about it."

**Step 3 — Show the pipeline (2 min)**
Watch the Tekton pipeline run.
```bash
oc get pipelineruns -n <ns> -w
```
"Look at what's happening automatically: build, test, generate SBOM, sign the artifact, create attestation, verify policies. The developer pushed code — that's all they did."

**Step 4 — Prove the chain (3 min)**
```bash
bash scripts/verify-supply-chain.sh --namespace <ns> --pipeline-run <run>
```
"Every artifact is signed with your own on-cluster Sigstore instance. The signature is in an immutable transparency log — you can audit who signed what, when, forever. The SBOM tells you every component and dependency. TPA has already scanned it against Red Hat's vulnerability data."

**Step 5 — Policy enforcement (2 min)**
"And here's the key: Enterprise Contract won't let unsigned or non-compliant artifacts deploy. This isn't honor system — it's enforced."

**Closing:** "SLSA Level 3 compliance, EO 14028 aligned, zero developer friction. Every artifact signed, attested, and analyzed — automatically."

---

## 2. CTO / VP Engineering

**Theme:** "Ship AI faster without risk"

**Opening hook:** "Your competitors are shipping AI features. Your security team wants a 6-month review cycle. Here's how you do both."

### Walk-Through

**Step 1 — Developer Hub (2 min)**
"This is Developer Hub — your internal developer platform. Instead of every team figuring out how to build, deploy, and secure AI apps from scratch, they pick a golden path template. Five minutes from zero to running application with full CI/CD."

Open Developer Hub → Show template catalog.
"AI chatbot, RAG application, model serving — all pre-built. And these TSSC templates come with supply chain security baked in."

**Step 2 — Scaffold an AI app (3 min)**
Create from AI Lab chatbot template.
"Watch: repo created, pipeline configured, GitOps set up, deployment ready. The developer fills in four fields and gets a production-grade AI application scaffold."

**Step 3 — OpenShift AI (3 min)**
```bash
oc get inferenceservices -A
```
"Your ML engineers have model serving, notebooks, pipelines, and a model registry — all on the same platform as your applications. No separate ML infrastructure to manage."

Show the Llama deployment:
"This is Llama 3.1 running on-cluster. vLLM runtime, GPU scheduling handled by Kueue, TrustyAI monitoring for bias and explainability."

**Step 4 — The security story (2 min)**
"And here's what your CISO will love: everything that pipeline built was signed, attested, and scanned. Automatically. Your developers didn't slow down; your security team got everything they need."

**Closing:** "One platform: developer velocity, AI capabilities, and security compliance. Not three separate tools duct-taped together."

---

## 3. Dev Lead / Principal Engineer

**Theme:** "Golden paths that don't feel like handcuffs"

**Opening hook:** "I know what you're thinking — 'another platform that'll slow my team down.' Let me show you why this one's different."

### Walk-Through

**Step 1 — Templates are real code (2 min)**
Show the template source in GitHub:
```
https://github.com/redhat-ai-dev/ai-lab-template/tree/main/templates/chatbot
```
"These aren't some proprietary config — it's Backstage templates. Nunjucks + YAML. Your platform team owns them, your developers can contribute. When best practices change, you update the template and every new app gets the improvement."

**Step 2 — Scaffold and inspect (3 min)**
Create from TSSC Python template → Show the generated repo.
"Look at what you got: application code scaffold, Dockerfile, Tekton pipeline, ArgoCD config, catalog-info.yaml. Everything a production app needs. And the pipeline has artifact signing built into the build task — you didn't have to configure cosign or figure out Tekton Chains."

**Step 3 — Show the pipeline doing its thing (2 min)**
```bash
oc get pipelinerun <run> -n <ns> -o jsonpath='{range .status.childReferences[*]}{.pipelineTaskName}{"\n"}{end}'
```
"Build → Test → Generate SBOM → Sign → Attest → Deploy. All in the pipeline. You push code, you get a signed, attested, SBOM'd container image. The overhead for the developer? Zero."

**Step 4 — AI integration (2 min)**
"Now here's where it gets fun. Your AI workloads run on the same platform. Need a model serving endpoint? It's a CRD. Need a notebook for prototyping? Click a button in the OpenShift AI dashboard. Need a RAG pipeline? There's a template for that."

**Step 5 — Developer Hub as service catalog (1 min)**
Show the catalog view with running components.
"Developer Hub isn't just for scaffolding — it's your service catalog. See what's running, who owns it, what dependencies it has, read the docs, check the pipeline status — all in one place."

**Closing:** "The platform does the boring stuff so your developers can do the interesting stuff. And when the auditors come, you have receipts."

---

## 4. Platform Engineer / SRE

**Theme:** "One platform to rule them all"

**Opening hook:** "You're probably managing 5 different tools for CI/CD, GitOps, security scanning, model serving, and developer portals. What if it was all one platform?"

### Walk-Through

**Step 1 — Operator-managed everything (2 min)**
```bash
oc get csv -A | grep -E '(devhub|openshift-ai|pipelines|rhtas|trustification|gitops)' | awk '{print $2, $NF}'
```
"Every component is operator-managed. Upgrades, patches, configuration — the operator handles lifecycle. You're not maintaining Helm charts for 15 different tools."

**Step 2 — Show the operator health (1 min)**
```bash
bash scripts/check-platform.sh
```
"One command: every component green. If something's degraded, you know exactly where."

**Step 3 — GitOps deployment (2 min)**
"Applications deploy via ArgoCD. The pipeline builds and signs the image, ArgoCD picks up the new manifest, deploys to the target environment. Drift? ArgoCD corrects it. Rollback? Git revert."

**Step 4 — Supply chain as infrastructure (2 min)**
"TAS and TPA aren't add-ons — they're infrastructure. Sigstore runs on-cluster, Tekton Chains signs automatically, Enterprise Contract enforces policies. You set it up once and forget about it."

**Step 5 — OpenShift AI ops (2 min)**
```bash
oc get inferenceservices -A
oc get servingruntimes -A
oc adm top nodes --sort-by=cpu
```
"Model serving is just another workload. KServe handles scale-to-zero, Kueue handles GPU scheduling, model registry tracks versions. Your ML team doesn't need separate infrastructure."

**Step 6 — Day 2 story (1 min)**
"And when you need to manage 50 clusters? AutoShift uses ACM + GitOps to push all of this — operators, policies, configurations — to every cluster declaratively. Label a cluster, it gets the stack."

**Closing:** "Fewer tools, fewer tickets, fewer 2AM pages. One platform, operator-managed, GitOps-driven. That's the Advanced Developer Suite story."

---

## Demo Tips

- **Always run `check-platform.sh` first** — nothing kills a demo faster than a broken component
- **Have a pre-scaffolded app ready** as backup — template scaffolding depends on GitHub and can be slow
- **Keep a terminal with `oc get pipelineruns -w`** running — watching tasks complete in real-time is compelling
- **If Llama isn't ready**, use the model-server template to deploy a smaller model for the demo
- **Isaac Sim is a wildcard** — if the audience cares about edge/robotics/manufacturing, show it; otherwise skip
- **Let the customer drive** — "What would you like to see deployed?" is more powerful than a scripted demo
