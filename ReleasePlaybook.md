# iAPS Release Playbook (Forked)

This playbook details the process for building and distributing releases to the main TestFlight track and a separate development track in your personal fork (`edubloop/iAPS`).

---

## 1. Repository Structure

| Repository | Purpose | Default Branch | Primary Action Branch |
| :--- | :--- | :--- | :--- |
| `edubloop/iAPS` (`origin`) | **Stable Track** for existing users. Synced to upstream. | `main` | `main` (or merge from feature branches) |
| `edubloop/iAPS_dev` (`devrepo`) | **Development Track** for new features/testing before stable. | `dev-ci-hardening` | `dev-ci-hardening` |
| `edubloop/Match-Secrets` | Stores provisioning profiles/certificates for CI signing. | `master` | `master` |

---

## 2. Main Track Release (`edubloop/iAPS`)

This track should always match the public upstream branch after sync.

**Prerequisites (One-time setup completed):**
- GitHub Secrets/Variables configured in `edubloop/iAPS`.
- Apple Developer IDs/Profiles configured for main bundle IDs.
- `alive` branch exists: `git push origin main:alive`.

**Build Workflow:**
1. **Ensure Sync:** Confirm `main` is up-to-date with `upstream/main`.
   ```bash
   git switch main
   git fetch upstream
   git merge upstream/main # or rebase if preferred
   git push origin main
   ```
2. **Trigger Workflow:**
   - Go to **`edubloop/iAPS` → Actions → `4. Build iAPS`**
   - Branch: `main`
   - Run Workflow.
3. **Validation:** If successful, monitor App Store Connect for the new build.

---

## 3. Development Track Release (`edubloop/iAPS_dev`)

Use this track for testing CI fixes and new features that are not ready for stable release.

**Prerequisites (One-time setup completed):**
- Repository created (`iAPS_dev`).
- Branch `dev-ci-hardening` pushed from main.
- Default branch set to `dev-ci-hardening` in repo settings.
- Dev Secrets/Variables configured (especially `APP_IDENTIFIER = ru.artpancreas.<TEAMID>.FreeAPS.dev`).
- Dev Bundle IDs created and configured with **App Groups** + **HealthKit** in Apple Developer.
- Dev provisioning profiles generated via CI (this was the final successful step).

**Build Workflow:**
1. **Code Changes:** Apply feature changes to `dev-ci-hardening` (or a feature branch derived from it).
2. **Trigger Workflow:**
   - Go to **`edubloop/iAPS_dev` → Actions → `4. Build iAPS`**
   - Branch: `dev-ci-hardening`
   - Run Workflow.
3. **Validation:** The resulting build goes to the **"iAPS Dev"** app in TestFlight.

---

## 4. CI Health Checklist (For Troubleshooting)

If any workflow fails (especially `4. Build iAPS`):

1. **Did `3. Create Certificates` pass?** If not, go to Apple Developer and check if the 4 `.dev` App IDs have the **App Group** capability configured (`Enabled App Groups (1)`).
2. **Did `4. Build iAPS` fail at `match`?** Check `APP_IDENTIFIER` secret value consistency between GitHub Actions variable and Apple Dev ID.
3. **Did `4. Build iAPS` fail at `gym`?** This usually means a capability (HealthKit/App Groups) is enabled in Xcode/Apple Dev, but not correctly configured in the other. Compare capabilities between main and dev IDs.
4. **If only `alive` branch fails checkout:** Run `git push origin main:alive` from local repo to recreate it.
5. **If you change a secret/variable in `iAPS_dev`**: Rerun the entire sequence (`1` through `4`) to ensure all artifacts (certs/profiles) are regenerated for the new value.
