#!/usr/bin/env bash
# Exit on error
set -e

# --- Configuration ---
# The commit ID of the Antigravity IDE version.
# Change this to match your IDE version if it is different.
COMMIT_ID="2.0.4-def9583aef9852ff94cb0dea16ede9bb6b095b30"
NODE_VERSION="v22.20.0"

echo "=== Initializing setup on macOS remote host ==="
SERVER_DIR="$HOME/.antigravity-ide-server/bin/$COMMIT_ID"
echo "Target server directory: $SERVER_DIR"

# Step 1: Create clean target directory
rm -rf "$SERVER_DIR"
mkdir -p "$SERVER_DIR"
cd "$SERVER_DIR"

# Step 2: Download and extract the linux-arm platform-agnostic skeleton
echo "Downloading linux-arm base skeleton..."
curl -fsSL "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/$COMMIT_ID/linux-arm/Antigravity%20IDE-reh.tar.gz" -o reh.tar.gz
echo "Extracting base skeleton..."
tar -xzf reh.tar.gz --strip-components 1
rm reh.tar.gz
# Step 3: Detect architecture and download native Node.js
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
  NODE_ARCH="darwin-arm64"
elif [ "$ARCH" = "x86_64" ]; then
  NODE_ARCH="darwin-x64"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi
echo "Detected architecture: $ARCH. Using Node build for $NODE_ARCH"

echo "Downloading Node.js $NODE_VERSION for macOS $NODE_ARCH..."
cd /tmp
curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-$NODE_ARCH.tar.gz" -o node.tar.gz
echo "Extracting Node.js..."
rm -rf node-$NODE_VERSION-$NODE_ARCH
tar -xzf node.tar.gz

# Step 4: Replace the linux node binary with the native macOS build
echo "Replacing node binary..."
cp node-$NODE_VERSION-$NODE_ARCH/bin/node "$SERVER_DIR/node"

# Step 5: Install/rebuild native modules natively in a temp folder and copy them back to prevent pruning
echo "Rebuilding native modules in temporary build directory..."
export PATH="/tmp/node-$NODE_VERSION-$NODE_ARCH/bin:$PATH"
rm -rf /tmp/npm-build
mkdir -p /tmp/npm-build/node_modules
cp "$SERVER_DIR/package.json" /tmp/npm-build/package.json
cd /tmp/npm-build

# Force compilation of native modules natively on Apple Silicon/Intel using Xcode/CommandLineTools
npm install --no-save --legacy-peer-deps --cache /tmp/npm-cache \
  @vscode/spdlog@0.15.2 \
  @parcel/watcher@2.5.1 \
  node-pty@1.1.0-beta35 \
  native-watchdog@1.4.2 \
  kerberos@2.1.1 \
  @vscode/ripgrep@1.15.14

echo "Copying rebuilt native modules back to target server directory..."
mkdir -p "$SERVER_DIR/node_modules"
cp -R node_modules/* "$SERVER_DIR/node_modules/"
cd "$SERVER_DIR"

# Step 6: Create the startup script to support macOS dynamic loading and DYLD_LIBRARY_PATH
echo "Writing patched startup script..."
cat << 'EOF' > "$SERVER_DIR/bin/antigravity-ide-server"
#!/usr/bin/env sh
#
# Copyright (c) Microsoft Corporation. All rights reserved.
#

case "$1" in
        --inspect*) INSPECT="$1"; shift;;
esac

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"

# Set rpath before changing the interpreter path
# Refs https://github.com/NixOS/patchelf/issues/524
if [ -n "$VSCODE_SERVER_CUSTOM_GLIBC_LINKER" ] && [ -n "$VSCODE_SERVER_CUSTOM_GLIBC_PATH" ] && [ -n "$VSCODE_SERVER_PATCHELF_PATH" ]; then
        echo "Patching glibc from $VSCODE_SERVER_CUSTOM_GLIBC_PATH with $VSCODE_SERVER_PATCHELF_PATH..."
        "$VSCODE_SERVER_PATCHELF_PATH" --set-rpath "$VSCODE_SERVER_CUSTOM_GLIBC_PATH" "$ROOT/node"
        echo "Patching linker from $VSCODE_SERVER_CUSTOM_GLIBC_LINKER with $VSCODE_SERVER_PATCHELF_PATH..."
        "$VSCODE_SERVER_PATCHELF_PATH" --set-interpreter "$VSCODE_SERVER_CUSTOM_GLIBC_LINKER" "$ROOT/node"
        echo "Patching complete."
fi

export DYLD_LIBRARY_PATH="/opt/homebrew/lib:$DYLD_LIBRARY_PATH"
"$ROOT/node" ${INSPECT:-} "$ROOT/out/server-main.js" "$@"
EOF

chmod +x "$SERVER_DIR/bin/antigravity-ide-server"

# Step 7: Clear Gatekeeper quarantine tags and apply ad-hoc local code signatures
echo "Applying ad-hoc code signatures..."
xattr -rc "$SERVER_DIR"

# Find and codesign the binary executables & modules to satisfy macOS Gatekeeper policies
find "$SERVER_DIR" -type f \( -name "*.node" -o -name "rg" -o -name "spawn-helper" -o -name "node" \) | while read -r file; do
  if [ -f "$file" ]; then
    echo "Signing $file..."
    codesign --force --sign - "$file"
  fi
done

# Cleaning up temp files
rm -rf /tmp/node-$NODE_VERSION-$NODE_ARCH /tmp/node.tar.gz

echo "=== Patched Remote SSH Server Successfully! ==="
