#!/usr/bin/env sh
# Build ceserver for a single CE version × Android ABI.
#
# Required env vars:
#   CE_DIR  - absolute path to a checkout of cheat-engine/cheat-engine at the
#             desired tag (e.g. "7.5"). Must contain
#             "Cheat Engine/ceserver/ndk-build/EXECUTABLE/jni/Application.mk".
#   ABI     - one of arm64-v8a | armeabi-v7a | x86_64
#
# Optional env vars:
#   OUT_DIR        - directory to place the produced ceserver + sidecars.
#                    Defaults to "$PWD/out".
#   CE_REF         - human-readable label written into manifest.json.
#                    Defaults to "unknown".
#   BUILD_NUM      - build number label written into manifest.json.
#                    Defaults to "0".
#   SOURCE_COMMIT  - cereve-resources commit sha written into manifest.json.
#                    Defaults to "unknown".
#   NDK_VERSION    - ndk version label written into manifest.json.
#                    Defaults to "$ANDROID_NDK_VERSION" or "unknown".
#
# Output (all inside OUT_DIR):
#   ceserver           the stripped ELF binary
#   ceserver.sha256    "<hex>  ceserver"  (sha256sum --check compatible)
#   manifest.json      { ce_ref, abi, ndk_version, sha256, size_bytes, built_at }
set -eu

require_env() {
  if [ -z "${1:-}" ]; then
    echo "build.sh: missing required env var $2" >&2
    exit 1
  fi
}

require_env "${CE_DIR:-}" CE_DIR
require_env "${ABI:-}" ABI

case "$ABI" in
  arm64-v8a|armeabi-v7a|x86_64) ;;
  *)
    echo "build.sh: unsupported ABI '$ABI'" >&2
    exit 1
    ;;
esac

OUT_DIR="${OUT_DIR:-$PWD/out}"
CE_REF_LABEL="${CE_REF:-unknown}"
EXEC_DIR="$CE_DIR/Cheat Engine/ceserver/ndk-build/EXECUTABLE"
APP_MK="$EXEC_DIR/jni/Application.mk"
ANDROID_MK="$EXEC_DIR/jni/Android.mk"

if [ ! -f "$APP_MK" ] || [ ! -f "$ANDROID_MK" ]; then
  echo "build.sh: expected ndk-build files not found under $EXEC_DIR/jni" >&2
  echo "Contents of $EXEC_DIR (if it exists):" >&2
  ls -la "$EXEC_DIR" 2>&1 >&2 || true
  exit 1
fi

# In-place rewrite Application.mk so APP_ABI is exactly the requested single ABI.
# Restore the original on exit so cached CE checkouts stay clean for the next run.
APP_MK_BACKUP="$(mktemp)"
cp "$APP_MK" "$APP_MK_BACKUP"
cleanup() {
  cp "$APP_MK_BACKUP" "$APP_MK"
  rm -f "$APP_MK_BACKUP"
}
trap cleanup EXIT INT TERM

# Replace any APP_ABI line; if absent, append one. Use sed without GNU-only flags.
if grep -q '^APP_ABI' "$APP_MK"; then
  sed -i.bak "s|^APP_ABI.*|APP_ABI := $ABI|" "$APP_MK"
  rm -f "$APP_MK.bak"
else
  printf "\nAPP_ABI := %s\n" "$ABI" >> "$APP_MK"
fi

echo "build.sh: building ceserver for $ABI from $CE_REF_LABEL"
echo "build.sh: APP_ABI now:"
grep '^APP_ABI' "$APP_MK"

cd "$EXEC_DIR"
# ndk-build forwards APP_BUILD_SCRIPT / NDK_APPLICATION_MK to make, and make
# splits on whitespace — so passing absolute paths containing "Cheat Engine"
# (with its space) breaks resolution inside make. Stay relative to $EXEC_DIR.
ndk-build NDK_PROJECT_PATH=. \
  APP_BUILD_SCRIPT=jni/Android.mk \
  NDK_APPLICATION_MK=jni/Application.mk

# ndk-build typically drops the executable at libs/<abi>/ceserver
SRC="$EXEC_DIR/libs/$ABI/ceserver"
if [ ! -f "$SRC" ]; then
  # Some CE builds prefix with "lib" if a shared library target was used; tolerate both.
  ALT="$EXEC_DIR/libs/$ABI/libceserver.so"
  if [ -f "$ALT" ]; then
    SRC="$ALT"
  else
    echo "build.sh: ceserver output not found under $EXEC_DIR/libs/$ABI" >&2
    ls -la "$EXEC_DIR/libs" 2>&1 >&2 || true
    exit 1
  fi
fi

mkdir -p "$OUT_DIR"
cp "$SRC" "$OUT_DIR/ceserver"
chmod 0755 "$OUT_DIR/ceserver"

# sha256 + size
cd "$OUT_DIR"
SHA="$(sha256sum ceserver | awk '{print $1}')"
SIZE_BYTES="$(wc -c < ceserver | tr -d ' ')"
printf "%s  ceserver\n" "$SHA" > ceserver.sha256

NDK_VERSION="${NDK_VERSION:-${ANDROID_NDK_VERSION:-unknown}}"
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BUILD_NUM_LABEL="${BUILD_NUM:-0}"
SOURCE_COMMIT_LABEL="${SOURCE_COMMIT:-unknown}"

cat > manifest.json <<JSON
{
  "ce_ref": "$CE_REF_LABEL",
  "abi": "$ABI",
  "ndk_version": "$NDK_VERSION",
  "build_num": "$BUILD_NUM_LABEL",
  "source_commit": "$SOURCE_COMMIT_LABEL",
  "sha256": "$SHA",
  "size_bytes": $SIZE_BYTES,
  "built_at": "$BUILT_AT"
}
JSON

echo "build.sh: produced $OUT_DIR/ceserver ($SIZE_BYTES bytes, sha256 $SHA)"
