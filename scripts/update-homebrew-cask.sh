#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 6 ]; then
  echo "Usage: $0 <tap-dir> <cask-name> <version> <sha256> <asset-url> <repo>"
  exit 1
fi

TAP_DIR="$1"
CASK_NAME="$2"
VERSION="$3"
SHA256="$4"
ASSET_URL="$5"
REPO="$6"

mkdir -p "${TAP_DIR}/Casks"

cat > "${TAP_DIR}/Casks/${CASK_NAME}.rb" <<EOF
cask "${CASK_NAME}" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "${ASSET_URL}"
  name "SpeakSmooth"
  desc "Menu bar app that rewrites speech and saves to Apple Reminders"
  homepage "https://github.com/${REPO}"

  app "SpeakSmooth.app"
end
EOF

echo "Updated ${TAP_DIR}/Casks/${CASK_NAME}.rb"
