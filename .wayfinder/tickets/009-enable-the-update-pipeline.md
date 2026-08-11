---
id: 009
title: Enable the update pipeline on GitHub
labels: [wayfinder:task]
state: open
assignee: null
blocked_by: [008]
---

## Question

HITL. Nothing to decide - WF-008 settled the strategy and `renovate.json` is
committed. This is the GitHub-side work that makes the decision real, and it
needs a human because both steps are repo settings the agent cannot change.

Until this is done, `renovate.json` is inert and the digests in `compose.yaml`
are a snapshot that will silently rot: pinned, reproducible, and never updated.
That is strictly worse than `latest` for security, because base-OS rebuilds stop
arriving with no signal that anything is stale.

### Checklist

1. **Install the Renovate GitHub App** on `grez-lucas/media-server`
   (https://github.com/apps/renovate). It will open an onboarding PR against
   `renovate.json`; the config is already written, so the onboarding PR should be
   close to a no-op. Confirm it raises one PR per service rather than a grouped
   one.
2. **Protect `main`** and require the portability check. The agent attempted this
   and was denied by the permission classifier, so it is yours to run:

   ```
   gh api -X PUT repos/grez-lucas/media-server/branches/main/protection --input - <<'EOF'
   {
     "required_status_checks": { "strict": true, "contexts": ["Clean-host round trip"] },
     "enforce_admins": false,
     "required_pull_request_reviews": null,
     "restrictions": null,
     "allow_force_pushes": false,
     "allow_deletions": false
   }
   EOF
   ```

   `Clean-host round trip` is the exact check-run name, confirmed against run
   31533869813. Settings UI works equally well.

### Resolved when

A Renovate PR exists and cannot be merged without `Clean-host round trip`
passing. The answer records the first PR raised and whether the check gated it,
since an unenforced gate is the failure mode this ticket exists to prevent.

### Facts

- Renovate app install page: https://github.com/apps/renovate
- Required check context: `Clean-host round trip` (job name in
  `.github/workflows/portability.yml`).
- The workflow already triggers on `pull_request`, so no workflow change is
  needed - only enforcement.
