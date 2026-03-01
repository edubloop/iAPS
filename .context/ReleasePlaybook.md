# iAPS Release Playbook (Forked)

This playbook defines a stable release path for current users and an isolated development path for testing new changes safely.

## 1. Operating Model

| Repository | Role | Default Branch | TestFlight Target |
| :--- | :--- | :--- | :--- |
| `<fork-owner>/iAPS` | Stable production fork synced to upstream | `main` | Main app (`...FreeAPS`) |
| `<fork-owner>/iAPS_dev` | Integration and testing fork | `dev-ci-hardening` | Dev app (`...FreeAPS.dev`) |
| `<fork-owner>/Match-Secrets` | Shared signing assets repository | `master` | N/A |

## 2. Promotion Rule

- Never release to stable before dev is green.
- Flow is always: `upstream/main` -> `iAPS_dev` validation -> `iAPS` stable release.
- Keep `<fork-owner>/iAPS` as close to upstream as possible.

## 3. Stable Release Procedure (`<fork-owner>/iAPS`)

1. Sync stable branch with upstream:

```bash
git switch main
git fetch upstream
git merge upstream/main
git push origin main
```

2. Run Actions workflow `4. Build iAPS` on branch `main`.
3. Validate uploaded build in App Store Connect/TestFlight for the main app.

## 4. Dev Release Procedure (`<fork-owner>/iAPS_dev`)

1. Work on `dev-ci-hardening` (or short-lived feature branches from it).
2. Run Actions workflow `4. Build iAPS` on `dev-ci-hardening`.
3. Validate uploaded build in App Store Connect/TestFlight for the dev app.

Required dev variable:

- `APP_IDENTIFIER=ru.artpancreas.<TEAMID>.FreeAPS.dev`

## 5. One-Time Setup Notes (Already Completed)

- `iAPS_dev` created and configured.
- `alive` helper branch exists where required by workflow checkout logic.
- App Store Connect app created for dev bundle ID.
- Dev Apple identifiers created:
  - `ru.artpancreas.<TEAMID>.FreeAPS.dev`
  - `ru.artpancreas.<TEAMID>.FreeAPS.dev.watchkitapp`
  - `ru.artpancreas.<TEAMID>.FreeAPS.dev.watchkitapp.watchkitextension`
  - `ru.artpancreas.<TEAMID>.FreeAPS.dev.LiveActivity`
- App Groups configured and attached (not just enabled):
  - `group.com.<TEAMID>.loopkit.LoopGroup`

## 6. Upstream Sync — Canonical Path

**Canonical sync workflow**: `5. Sync Upstream` (`syncUpstreamRepo.yml`)
- Runs daily at 03:00 UTC (cron) and is available for manual dispatch.
- Always syncs `upstream/main` → this repo's `main` branch (hardcoded; does not follow `github.ref_name`).
- Triggering it from any branch is safe — it will always target `main`.

**Secondary sync path** (`build_iAPS.yml` `SCHEDULED_SYNC` variable):
- Disabled by default (`SCHEDULED_SYNC` not set).
- Do not enable it in `iAPS_dev`; keep the build workflow focused on building only.
- If both paths were active simultaneously they would race; keep only `5. Sync Upstream` active.

**Cadence**: daily automatic sync is sufficient. For urgent upstream fixes, run `5. Sync Upstream` manually then immediately trigger a build.

**Each sync cycle**:
1. `5. Sync Upstream` runs on `iAPS_dev` (syncs `upstream/main` → `iAPS_dev/main`).
2. Run dev pipeline (`4. Build iAPS`) and smoke test the TestFlight build.
3. If dev is green, manually sync the same commit to `<fork-owner>/iAPS` stable.

## 7. CI Troubleshooting Quick Checks

1. `checkout` fails for `alive`: create/refresh with `git push <remote> main:alive`.
2. `match` fails missing profiles: confirm `APP_IDENTIFIER` and rerun `2 -> 3 -> 4` workflows.
3. `gym` fails after signing succeeds: check App Groups assignment and HealthKit/NFC capabilities on all app IDs.
4. After changing secrets/variables: rerun `1. Validate Secrets`, then `2. Add Identifiers`, `3. Create Certificates`, `4. Build iAPS`.

## 8. Current Fastlane Strategy

- Keep using the Artificial-Pancreas fastlane fork in `Gemfile` for compatibility.
- Do not switch to rubygems fastlane unless intentionally moving away from AP-specific fastlane behavior.

## 9. Dependency Lock Strategy

**Current state**: No `Gemfile.lock` committed. `Gemfile` uses git sources (AP fastlane fork), so `bundle lock` cannot produce a fully deterministic lockfile without network access and a committed SHA.

**Bundler version**: Pinned to `2.7.2` in `BuildTools/setup_common_env.sh`. The script auto-detects from `Gemfile.lock` (`BUNDLED WITH` field) if a lockfile is ever committed, with fallback to the pin.

**To adopt a lockfile in future**:
1. Run `bundle lock` locally (requires network; pins git SHAs).
2. Commit `Gemfile.lock`.
3. `setup_common_env.sh` will automatically read the bundler version from it — no script change needed.

## 10. Build Artifact Policy

- Artifacts are named `build-artifacts-<run_number>` for uniqueness across queued runs.
- Retention: **14 days**. IPAs are large; older artifacts are rarely needed after TestFlight upload succeeds.
- To change retention, update `retention-days` in `build_iAPS.yml`.
