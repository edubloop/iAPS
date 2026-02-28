# iAPS Release Playbook (Forked)

This playbook defines a stable release path for current users and an isolated development path for testing new changes safely.

## 1. Operating Model

| Repository | Role | Default Branch | TestFlight Target |
| :--- | :--- | :--- | :--- |
| `edubloop/iAPS` | Stable production fork synced to upstream | `main` | Main app (`...FreeAPS`) |
| `edubloop/iAPS_dev` | Integration and testing fork | `dev-ci-hardening` | Dev app (`...FreeAPS.dev`) |
| `edubloop/Match-Secrets` | Shared signing assets repository | `master` | N/A |

## 2. Promotion Rule

- Never release to stable before dev is green.
- Flow is always: `upstream/main` -> `iAPS_dev` validation -> `iAPS` stable release.
- Keep `edubloop/iAPS` as close to upstream as possible.

## 3. Stable Release Procedure (`edubloop/iAPS`)

1. Sync stable branch with upstream:

```bash
git switch main
git fetch upstream
git merge upstream/main
git push origin main
```

2. Run Actions workflow `4. Build iAPS` on branch `main`.
3. Validate uploaded build in App Store Connect/TestFlight for the main app.

## 4. Dev Release Procedure (`edubloop/iAPS_dev`)

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

## 6. Upstream Update Cadence

- Recommended cadence: weekly (or immediately for important upstream fixes).
- Each cycle:
  1. Sync upstream into `iAPS_dev`.
  2. Run dev pipeline and smoke test.
  3. Promote same commit to `iAPS` stable if dev is good.

## 7. CI Troubleshooting Quick Checks

1. `checkout` fails for `alive`: create/refresh with `git push <remote> main:alive`.
2. `match` fails missing profiles: confirm `APP_IDENTIFIER` and rerun `2 -> 3 -> 4` workflows.
3. `gym` fails after signing succeeds: check App Groups assignment and HealthKit/NFC capabilities on all app IDs.
4. After changing secrets/variables: rerun `1. Validate Secrets`, then `2. Add Identifiers`, `3. Create Certificates`, `4. Build iAPS`.

## 8. Current Fastlane Strategy

- Keep using the Artificial-Pancreas fastlane fork in `Gemfile` for compatibility.
- Do not switch to rubygems fastlane unless intentionally moving away from AP-specific fastlane behavior.
