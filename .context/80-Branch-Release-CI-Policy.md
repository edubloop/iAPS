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

## Agent guidance

- When touching release/build scripts, cross-check `fastlane/` docs and playbook
- Avoid changing secrets/credential assumptions without explicit user request
- Document any CI/release behavior changes in PR notes and this file
- Keep `5. Sync Upstream` as canonical sync path; avoid enabling conflicting scheduled sync paths.
- Respect current bundler strategy in `BuildTools/setup_common_env.sh` (pinned bundler unless lockfile governs it).

## Source references

- `.context/ReleasePlaybook.md`
- `fastlane/docs/github.md`
- `fastlane/testflight.md`
