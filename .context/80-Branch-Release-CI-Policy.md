# Branch Release CI Policy

## Purpose

Summarize branch roles, release flow, and CI expectations for agent-safe changes.

## Policy summary

- Follow existing branch promotion and release flow in `.context/ReleasePlaybook.md`
- Keep CI/workflow files aligned with active branch model
- Do not assume upstream defaults; this repo follows fork-specific release operations
- Current model from playbook:
  - dev/testing branch: `dev-ci-hardening`
  - stable branch: `main`
  - promotion order: `upstream/main` -> dev validation -> stable release

## Repository ownership boundaries

- `Artificial-Pancreas/iAPS` is upstream source only for sync; agents must not open PRs there.
- `edubloop/iAPS` should remain a clean mirror of upstream on `main`.
- Custom work should stay on `dev-ci-hardening` (typically in `edubloop/iAPS_dev`).
- When PRs are used, target only owner-controlled repos/branches (never upstream/public).

## Agent guidance

- When touching release/build scripts, cross-check `fastlane/` docs and playbook
- Avoid changing secrets/credential assumptions without explicit user request
- Document any CI/release behavior changes in PR notes and this file
- Keep `5. Sync Upstream` as canonical sync path; avoid enabling conflicting scheduled sync paths.
- Respect current bundler strategy in `BuildTools/setup_common_env.sh` (pinned bundler unless lockfile governs it).
- Before git operations, verify remote/branch target to prevent accidental upstream pushes.

## Source references

- `.context/ReleasePlaybook.md`
- `fastlane/docs/github.md`
- `fastlane/testflight.md`
