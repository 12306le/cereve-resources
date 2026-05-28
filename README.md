# cereve-resources

Public build pipeline and GitHub Releases distribution for [Cereve](https://github.com/12306le/cereve)'s pre-compiled `ceserver` binaries (Cheat Engine, Android).

This repo is intentionally **public and auditable**: the build script and workflow that produce the binaries Cereve installs on user devices live here, so any user can:

1. Read [`scripts/ceserver/build.sh`](scripts/ceserver/build.sh) to see exactly how each `ceserver` is compiled.
2. Re-run the build themselves on a clean ubuntu runner and compare the resulting `sha256` against the [Releases](https://github.com/12306le/cereve-resources/releases) page.
3. Verify the immutable URL pattern matches what their Cereve install actually downloads.

The Cereve desktop client itself (Tauri / Vue / Rust source) remains in a separate private repo. Nothing in this repo can read or affect the client's authorization logic.

## What lives here

| Path | Purpose |
|------|---------|
| [`.github/workflows/build-ceserver.yml`](.github/workflows/build-ceserver.yml) | Tag-driven (`ceserver-<ce_ref>-<build_num>`) matrix build + GitHub Release publish. |
| [`scripts/ceserver/build.sh`](scripts/ceserver/build.sh) | POSIX-`sh` script that rewrites `Application.mk::APP_ABI` and runs `ndk-build`. |
| [`scripts/ceserver/manifest.json`](scripts/ceserver/manifest.json) | Project-level declared matrix (`ce_versions`, `abis`, `ndk`, `deferred`). |
| [`scripts/ceserver/README.md`](scripts/ceserver/README.md) | Operating manual + compatibility findings + URL pattern reference. |

## Releasing

Push a tag matching `ceserver-<ce_ref>-<build_num>`:

```bash
git tag ceserver-7.5-1
git push origin ceserver-7.5-1
```

The workflow then builds all three Android ABIs (arm64-v8a, armeabi-v7a, x86_64) in parallel and publishes a single GitHub Release containing nine files (3 binaries + 3 sha256 + 3 manifests).

For details, see [`scripts/ceserver/README.md`](scripts/ceserver/README.md).

## Cereve client download URL pattern

```
https://github.com/12306le/cereve-resources/releases/download/ceserver-<ce_ref>-<build_num>/ceserver-<abi>
```

ABI values: `arm64-v8a`, `armeabi-v7a`, `x86_64`. Each binary has matching `<file>.sha256` and `manifest-<abi>.json` sidecar files alongside it under the same release tag.

## What does NOT live here

- Cereve desktop client source code (private repo).
- Authorization / license / payment logic.
- ADB executor / managed runtime (private repo).
- User data of any kind.

## Upstream

`ceserver` source comes from <https://github.com/cheat-engine/cheat-engine>. This repo only redistributes binaries built from that upstream — see [upstream issue #2687](https://github.com/cheat-engine/cheat-engine/issues/2687) for the (proposed) official build automation that this pipeline tracks.
