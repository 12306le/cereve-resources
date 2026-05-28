# ceserver build pipeline

This directory hosts the inputs the GitHub Actions workflow uses to build Cheat Engine's `ceserver` for Android. The workflow file itself lives at `.github/workflows/build-ceserver.yml`.

## What this pipeline does

- Triggered by a `ceserver-<ce_ref>-<build_num>` git tag (or manual `workflow_dispatch` for dry-run builds with no release).
- Matrix-builds three Android ABIs in parallel: `arm64-v8a`, `armeabi-v7a`, `x86_64`.
- On tag push, publishes a single GitHub Release containing all 9 files (3 ceserver binaries + 3 sha256 + 3 manifest).
- Currently validated matrix: CE `7.5`. CE `6.7` / `7.0` are **deferred** — they predate the `ndk-build/EXECUTABLE/jni` layout (see "Compatibility findings" below).

## How to release a new build

```bash
# Increment build_num for each rebuild of the same CE version
git tag ceserver-7.5-1   # first build for CE 7.5
git push origin ceserver-7.5-1
```

The workflow then:
1. Parses the tag → `ce_ref=7.5`, `build_num=1`.
2. Spawns 3 parallel matrix jobs (one per ABI), each:
   - Clones `cheat-engine/cheat-engine` at the requested `ce_ref`.
   - Installs NDK r25c via `nttld/setup-ndk@v1`.
   - Runs `scripts/ceserver/build.sh` to produce `ceserver`, `ceserver.sha256`, `manifest.json`.
   - Renames assets to `ceserver-<abi>`, `ceserver-<abi>.sha256`, `manifest-<abi>.json`.
   - Uploads as a workflow artifact.
3. After all 3 matrix jobs succeed, the `publish` job downloads the artifacts and posts them to a GitHub Release tagged `ceserver-7.5-1`.

## How to dry-run a build without publishing

```bash
gh workflow run build-ceserver.yml -f ce_ref=7.5 -f build_num=0
gh run watch
```

`workflow_dispatch` runs the build matrix but skips the publish job (controlled by `if: github.event_name == 'push'`). Artifacts are downloadable via `gh run download` for 30 days.

## Inside each release

For tag `ceserver-7.5-1`, the GitHub Release at `https://github.com/12306le/cereve-resources/releases/tag/ceserver-7.5-1` contains 9 files:

| File | Purpose |
|------|---------|
| `ceserver-arm64-v8a` | stripped ELF binary, ARM aarch64, PIE |
| `ceserver-arm64-v8a.sha256` | `sha256sum -c` compatible |
| `manifest-arm64-v8a.json` | `{ ce_ref, abi, ndk_version, build_num, source_commit, sha256, size_bytes, built_at }` |
| `ceserver-armeabi-v7a` | stripped ELF, 32-bit ARM EABI5, PIE |
| `ceserver-armeabi-v7a.sha256` | matching sha256 |
| `manifest-armeabi-v7a.json` | matching manifest |
| `ceserver-x86_64` | stripped ELF, x86-64, PIE |
| `ceserver-x86_64.sha256` | matching sha256 |
| `manifest-x86_64.json` | matching manifest |

## Client URL pattern (for Cereve desktop and other consumers)

```
https://github.com/12306le/cereve-resources/releases/download/ceserver-<ce_ref>-<build_num>/<asset>
```

Examples:

```
https://github.com/12306le/cereve-resources/releases/download/ceserver-7.5-1/ceserver-arm64-v8a
https://github.com/12306le/cereve-resources/releases/download/ceserver-7.5-1/ceserver-arm64-v8a.sha256
https://github.com/12306le/cereve-resources/releases/download/ceserver-7.5-1/manifest-arm64-v8a.json
```

This is a **public** repo, so these URLs are anonymously downloadable — no token needed.

## How `build.sh` works

`build.sh` is invoked by the workflow with `CE_DIR` and `ABI` env vars. It:

1. Locates `<CE_DIR>/Cheat Engine/ceserver/ndk-build/EXECUTABLE/jni/{Android.mk,Application.mk}`.
2. Backs up `Application.mk`, rewrites `APP_ABI` to the single requested ABI, builds, and restores the file on exit (so cached upstream checkouts stay clean).
3. Runs `ndk-build` and collects `libs/<abi>/ceserver` (or `libceserver.so` fallback) into `$OUT_DIR`.
4. Emits `ceserver.sha256` and `manifest.json`.

`build.sh` is POSIX `sh`; do not introduce bashisms.

## Adding a new (CE × ABI) combination later

1. Append the CE tag to `manifest.json::ce_versions`.
2. Append the ABI to `manifest.json::abis`.
3. The workflow already accepts both parameters — just dispatch with the new values.
4. If an older CE tag uses a different ndk-build layout, `build.sh`'s "expected file" check will surface the difference loudly; patch the script there.

## Compatibility findings (Slice 4b, 2026-05-28)

| CE tag | ceserver build system | Status |
|--------|----------------------|--------|
| 6.7    | `Release-android/makefile` (Eclipse CDT), `arm-linux-androideabi-gcc` toolchain (removed in NDK r24+) | **Deferred**. Would require NDK r17 era toolchain — out of pipeline scope. |
| 7.0    | `AndroidStudio/` + `Release-android/` (still no ndk-build) | **Deferred**. Same reason as 6.7. |
| 7.1    | `ndk-build/EXECUTABLE/jni/{Android.mk,Application.mk}` (first appearance) | Compatible, **not yet enabled**. Candidate replacement for the "popular old version" pre-install slot. |
| 7.2–7.4 | Same ndk-build layout as 7.1 | Compatible, **not yet enabled**. |
| 7.5    | Same ndk-build layout | **Enabled**. arm64-v8a / armeabi-v7a / x86_64 all validated. |
| 7.6+   | Upstream not tagged yet (as of 2026-05) | Deferred. |

### Picking a replacement "popular old version" (future product decision)

If the product still wants a second pre-installed CE version alongside 7.5, the earliest compatible candidate is **7.1** (Feb 2020). 7.1–7.4 all share 7.5's `ndk-build` layout, so adopting any of them costs only one dispatch. This decision is **not** in slice 4b scope.

### Known build.sh gotcha

`Cheat Engine` (the directory) literally contains a space. `ndk-build` forwards `APP_BUILD_SCRIPT` / `NDK_APPLICATION_MK` to `make`, which splits variables on whitespace. Passing absolute paths therefore fails inside make even when the file exists at the literal path. `build.sh` works around this by `cd`-ing into `EXECUTABLE` and passing relative paths. Do not "simplify" this back to absolute paths.

## Notes on upstream CE state (as of 2026-05)

- Latest stable tag: `7.5` (Feb 2023). No `7.6` tag yet; manifest records `7.6` as deferred.
- CE upstream issue [#2687](https://github.com/cheat-engine/cheat-engine/issues/2687) proposes the same automation we are implementing here. NDK r25c choice tracks that proposal.
- Build paths verified via the GitHub API in slices 4a/4b; if a future CE refactor moves files, the workflow fails loudly rather than silently producing nothing.
- 4b validated runs:
  - `7.5 × arm64-v8a` → 89424 bytes, sha256 `b2251c13...`, `ELF 64-bit LSB pie executable, ARM aarch64`
  - `7.5 × armeabi-v7a` → 64044 bytes, sha256 `82819e5e...`, `ELF 32-bit LSB pie executable, ARM EABI5`
  - `7.5 × x86_64` → 92216 bytes, sha256 `21c0a7d0...`, `ELF 64-bit LSB pie executable, x86-64`
