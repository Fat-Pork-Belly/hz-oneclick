# Auto-merge gate

Bot-labeled PRs (label `codex`) are only auto-merged after required CI checks report success.
The auto-merge workflow evaluates the PR head SHA and blocks merge when:

- Any required check is present but not successful.
- Any required check is missing on a PR event (except schedule-only checks).
- A check suite concludes with `failure` or `cancelled`.

## Required checks

The required checks are centralized in `.github/scripts/require_checks.sh`:

- Workflow: `CI`
- Workflow: `Regression Checks`
- Workflow: `Full Regression` (schedule-only; absence does not block, failures do)
- Check run: `shell-ci`

See `.github/workflows/auto-merge.yml` for the gate steps and logging output.
