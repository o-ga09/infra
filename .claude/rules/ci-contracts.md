---
paths:
  - "manifests/**/cronworkflow.yaml"
  - "manifests/**/migration-job.yaml"
  - "manifests/**/agent-deployment.yaml"
  - "manifests/**/mcp-deployment.yaml"
  - "manifests/**/deployments.yaml"
  - "manifests/workflows/**/*.yaml"
---

# CI-patched fields — do not rename

The application repo's CI patches these files in place by matching on container/template `name`
via a `yq`/`jq` `select(.name == "...")` query, then overwriting `.image` (and nothing else).
Renaming the matched field breaks that automation silently — the next image build will fail to
find its target and the deploy will look fine but never update.

- `manifests/secretary/cronworkflow.yaml`: container template name must stay `run-batch`, and it
  must stay a `container:` block (not `script:`).
- `manifests/*/migration-job.yaml`: container name must stay `migration`.
- Deployment containers (e.g. `manifests/mh-api/deployments.yaml`, `agent-deployment.yaml`,
  `mcp-deployment.yaml`): container `name` matches the app/service name (`mh-api`, `mh-agent`,
  `mh-mcp`) — keep it stable once CI is wired to it.

If you need to rename one of these, it must happen in lockstep with the corresponding change in the
application repo's CI config — flag this to the user rather than renaming unilaterally.
