# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**The Response generated Japanese**

## Repository purpose

This is a GitOps repository for a homelab Kubernetes cluster (k3s) managed by ArgoCD. There is no
application source code here — only Kubernetes manifests. Application repos (e.g.
`o-ga09/adk-go-sample` for `secretary`) build container images elsewhere; this repo only wires those
images into the cluster.

## Repository layout

```
apps/                 ArgoCD Application definitions (one file per app). Adding a file here is what
                      makes ArgoCD start tracking and deploying an app.
manifests/<app>/      The actual Kubernetes manifests ArgoCD applies for that app: Deployment,
                      Service, Ingress, Secret/SealedSecret, migration Job, CronWorkflow, etc.
```

Every `apps/<name>.yaml` points at `manifests/<name>` via `spec.source.path`, and deploys into
`spec.destination.namespace` (conventionally the same as `<name>`). `syncPolicy.automated` has
`prune: true` and `selfHeal: true` on every app — **once a change is pushed to `main`, ArgoCD applies
it to the live cluster within its poll interval, with no separate approval step.** Treat `git push`
on this repo as a production deploy, not just a commit.

## Adding a new app

1. Create `manifests/<app-name>/` with its manifests (Deployment, Service, Ingress, Secret/SealedSecret
   as needed).
2. Create `apps/<app-name>.yaml` (copy the ArgoCD Application shape from an existing app, e.g.
   `apps/mh-api.yaml` or `apps/secretary.yaml`).
3. `kubectl apply -f apps/<app-name>.yaml` to register it with ArgoCD.
4. From then on, changes to `manifests/<app-name>/` deploy automatically on push.

## Secrets and CI-patched fields

Rules for editing `secret.yaml`/`sealed-secret.yaml` and for the CI-patched container/template names
(`run-batch`, `migration`, etc.) are **not** duplicated here — see `.claude/rules/secrets.md` and
`.claude/rules/ci-contracts.md`. Those are path-scoped and load automatically when you touch the
relevant files. Every namespace that pulls images from Artifact Registry also needs its own
`gar-secret` (docker-registry secret) referenced via `imagePullSecrets`.

## Validating changes before committing

```bash
# YAML is syntactically valid (handles multi-document files)
python3 -c "import yaml,sys; list(yaml.safe_load_all(open('manifests/<app>/<file>.yaml')))"

# Server-side dry run against the real cluster/CRDs without actually applying
kubectl apply --dry-run=server -f manifests/<app>/<file>.yaml
```

## Common commands

```bash
# Register a new/updated Application with ArgoCD
kubectl apply -f apps/<app-name>.yaml

# Encrypt a plaintext secret.yaml into the committed sealed-secret.yaml
kubeseal --format yaml \
  --controller-name=sealed-secrets --controller-namespace=kube-system \
  < manifests/<app>/secret.yaml \
  > manifests/<app>/sealed-secret.yaml

# Local kubeconfig setup against the k3s server
scp -i ~/.ssh/ouchi_k8s ubuntu@192.168.1.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i '' 's/127.0.0.1/192.168.1.10/' ~/.kube/config
kubectl get nodes
```

## Batch/workflow jobs (Argo Workflows)

Scheduled jobs live in the `argo-workflows` namespace as either:
- A single `CronWorkflow` with an inline `workflowSpec` (e.g. `manifests/secretary/cronworkflow.yaml`),
  or
- A `WorkflowTemplate` plus a separate `CronWorkflow` that references it via `workflowSpecRef`/
  `workflowTemplateRef` (e.g. `manifests/workflows/remind-24hr-event-start.yaml` +
  `remind-24hr-event-start-cron.yaml`).

Use `ttlStrategy` to control cleanup of completed Workflows/Pods (shorter TTL on success, longer on
failure so failure logs stay inspectable), and `concurrencyPolicy: Forbid` for jobs that must not
overlap runs.
