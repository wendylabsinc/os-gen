#!/usr/bin/env bash
set -eu

# Get the directory where this script is located
DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# Get date for versioning
T=$(date +%Y-%m-%d)
VERSION="${PI_GEN_RELEASE:-EdgeOS-ref}_${T}"
IMG_NAME="${ORG_ID:-edgeos}-${RELEASE:-bookworm}-${ARCH:-arm64}-${T}"



# Store image name for later use
echo "${IMG_NAME}" > "${DIR}/img_name.txt"

# Core system configuration
export IMG_NAME="${ORG_ID:-edgeos}-${RELEASE:-bookworm}-${ARCH:-arm64}-${T}"
export RELEASE="${RELEASE:-bookworm}"
export ARCH="${ARCH:-arm64}"
export FIRST_USER_NAME="${FIRST_USER_NAME:-edge}"
export FIRST_USER_PASS="${FIRST_USER_PASS:-edge}"
export DISABLE_FIRST_BOOT_USER_RENAME=0

# Important: TARGET_HOSTNAME must be set before sourcing build.sh
# In build.sh: export TARGET_HOSTNAME=${TARGET_HOSTNAME:-raspberrypi}
export TARGET_HOSTNAME="edgeos-device"

# Locale and keyboard settings
export LOCALE_DEFAULT="${LOCALE:-en_US.UTF-8}"
export KEYBOARD_KEYMAP="${KEYBOARD_KEYMAP:-us}"
export KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-English (US)}"
export TIMEZONE_DEFAULT="${TIMEZONE:-America/New_York}"
export WPA_COUNTRY="${WPA_COUNTRY:-US}"

# SSH Configuration
export ENABLE_SSH="${ENABLE_SSH:-1}"
# export PUBKEY_ONLY_SSH="${PUBKEY_ONLY_SSH:-1}"
# export PUBKEY_SSH_FIRST_USER="${PUBKEY_SSH_FIRST_USER:-}"

# Build configuration
export EDGEOS_BUILD_HASH=$(git rev-parse --short HEAD)
export GIT_HASH=${EDGEOS_BUILD_HASH}
export STAGE_LIST="${DIR}/stage0 ${DIR}/stage1 ${DIR}/stage2"
export CLEAN=1
export IMG_SUFFIX=""
export DEPLOY_ZIP=1
export DEPLOY_COMPRESSION="zip"
export COMPRESSION_LEVEL=6
export DEPLOY_DIR="${DIR}/deploy"
export WORK_DIR="${DIR}/work/${IMG_NAME}"
export LOG_FILE="${WORK_DIR}/build.log"

# Skip later stages
touch ./stage3/SKIP ./stage4/SKIP ./stage5/SKIP
touch ./stage4/SKIP_IMAGES ./stage5/SKIP_IMAGES

# APT configuration
export APT_PROXY=""
export SETFCAP=1

# QEMU configuration
export USE_QEMU=0

# Container configuration
export CONTAINER_NAME="edgeos_builder"
export CONTINUE=0
export PRESERVE_CONTAINER=0

# Create docker options string with all our environment variables
# Create config file
cat << EOF > "${DIR}/config"
IMG_NAME=${IMG_NAME}
PI_GEN_RELEASE="${VERSION}"
RELEASE=${RELEASE:-bookworm}
FIRST_USER_NAME=${FIRST_USER_NAME:-edge}
FIRST_USER_PASS=${FIRST_USER_PASS:-edge}
ENABLE_SSH=${ENABLE_SSH:-1}
WPA_COUNTRY=${WPA_COUNTRY:-US}
ARCH=${ARCH:-arm64}
LOCALE_DEFAULT=${LOCALE:-en_US.UTF-8}
TIMEZONE_DEFAULT=${TIMEZONE:-America/New_York}
TARGET_HOSTNAME=${TARGET_HOSTNAME:-edgeos-device}
EOF

echo "Building EdgeOS..."
echo "Build Hash: ${EDGEOS_BUILD_HASH}"
echo "Image Name: ${IMG_NAME}"
echo "Target Hostname: ${TARGET_HOSTNAME}"
echo "Architecture: ${ARCH}"
echo "Deploy Directory: ${DEPLOY_DIR}"

# Create deploy directory
mkdir -p "${DEPLOY_DIR}"

# Create a dedicated directory for this build's artifacts
BUILD_DEPLOY_DIR="${DEPLOY_DIR}/${IMG_NAME}"
mkdir -p "${BUILD_DEPLOY_DIR}"

# Capture all output and errors
{
    # Call the original build-docker.sh script
    "${DIR}/build-docker.sh" "$@"
    
    # Debug: Check sizes and contents
    echo "=== Directory Sizes ==="
    du -h "${WORK_DIR}"/*/ || true
    du -h "${DEPLOY_DIR}/" || true
    
    echo "=== Deploy Contents ==="
    ls -la "${DEPLOY_DIR}/"
    
    echo "=== Build Logs ==="
    cat "${LOG_FILE}" || true
    
} > >(tee "${BUILD_DEPLOY_DIR}/build.log") 2>&1

# Move all files for this build into the dedicated directory
cd "${DEPLOY_DIR}"
mv "${IMG_NAME}"* "${BUILD_DEPLOY_DIR}/" 2>/dev/null || true
mv build.log image_version git_hash "${BUILD_DEPLOY_DIR}/" 2>/dev/null || true

# Create tarball of the dedicated directory
tar czf "${IMG_NAME}.tgz" "${IMG_NAME}"

# Optionally, remove the directory after creating the tarball
rm -rf "${BUILD_DEPLOY_DIR}"

echo "Build complete. Artifacts available in ${DEPLOY_DIR}/${IMG_NAME}.tgz" 