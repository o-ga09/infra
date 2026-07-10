# GitOps deploy safety

This repo has no CI gate. ArgoCD `syncPolicy.automated` (`prune: true`, `selfHeal: true`) is set on
every Application in `apps/`. Whatever lands on `main` is applied to the live cluster automatically.

- Treat `git push` to `main` as a production deploy, not a commit. Confirm with the user before
  pushing changes under `manifests/` or `apps/`.
- Treat `kubectl apply` against the cluster the same way — it bypasses ArgoCD but has the same
  blast radius. Prefer `kubectl apply --dry-run=server` while iterating.
- Before editing an existing Deployment/Service/Ingress/Job, check whether ArgoCD would prune
  anything you remove (`prune: true` deletes resources no longer present in the manifest path).
