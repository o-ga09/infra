---
paths:
  - "manifests/**/secret.yaml"
  - "manifests/**/sealed-secret.yaml"
---

# Secret handling — absolute rules

0. **`Read`/`Edit` of `manifests/**/secret.yaml` is blocked at the permission layer** (`.claude/settings.json` `permissions.deny`), not just by convention — Claude Code will refuse the call outright. Retrieve/patch secret values through `kubectl get secret ... -o json | jq ...` instead of opening the plaintext file.
1. **Never hand-edit `sealed-secret.yaml` ciphertext.** It must only ever be the direct output of
   `kubeseal`. A past manual edit broke the encrypted payload.
2. **Never commit `manifests/<app>/secret.yaml`.** It's gitignored (`**/secret.yaml`) and must stay
   plaintext-local only.
3. **Adding/changing one key does not mean rebuilding all keys.** Pull the live Secret from the
   cluster with `kubectl get secret ... -o json`, merge the one changed key with `jq`, then reseal.
   Retyping every key from scratch risks silently dropping or mistyping an unrelated one.
4. **Never put a plaintext secret value directly on a shell command line** (even inside a heredoc,
   the command itself lands in shell history/session logs). Pipe it through variables into
   `kubectl ... | jq ... | kubeseal ...` instead.
5. Some apps run in multiple namespaces (e.g. `secretary`: `secretary` namespace for the API,
   `argo-workflows` namespace for its CronWorkflow) and need the same-named Secret provisioned in
   each namespace — sometimes with different key sets. Check `metadata.namespace` across the app's
   manifests before assuming one Secret covers everything.

Full step-by-step workflow (including the nested-command-substitution race condition that once
zeroed out a webhook URL, and per-app required-key tables): `.claude/skills/manage-sealed-secrets/SKILL.md`.
Use that skill for any Secret/SealedSecret change rather than improvising the `kubeseal` invocation.
