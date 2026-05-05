#!/usr/bin/env bash

set -euox pipefail

# Usage: ~/<mdc_repo>/scripts/foo.sh <mount_dir> " user-user1
#        user-user2
#        user-user3"

# Determine the project root directory based on the script's location.
# This allows the script to be run from any directory.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# Adjust the number of '../' based on the script's depth relative to the project root.
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." &>/dev/null && pwd)
export PROJECT_ROOT # Export for any child scripts that might need it

MOUNT_DIR=${1}
USERS=${2}

cd "${PROJECT_ROOT}"
pwd

echo "🔐 Setting up user list for ${MOUNT_DIR}..."

mkdir -p ${MOUNT_DIR}

cat > "${MOUNT_DIR}.users" << EOF
${USERS}
EOF
echo "✅ User list written to ${MOUNT_DIR}.users"

./bin/crypt-setup "${MOUNT_DIR}"
echo "✅ Setup completed for ${MOUNT_DIR}!"

./bin/crypt-mount "${MOUNT_DIR}"
echo "✅ Mounted ${MOUNT_DIR} successfully!"

rm -rf "${MOUNT_DIR}"
echo "✅ Cleaned up ${MOUNT_DIR} directory!"
