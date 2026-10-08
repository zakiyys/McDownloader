#!/bin/bash
# Compile the app on the Mac over SSH. No installs; uses CommandLineTools swiftc.
set -euo pipefail
TARBALL="${1:-/tmp/mcd-app.tgz}"
REMOTE_DIR="/tmp/McDownloader-App"

echo "== packaging =="
cd /data/apps/McDownloader
tar czf "$TARBALL" -C App .

echo "== copying to mac =="
scp -o BatchMode=yes -q "$TARBALL" mac:/tmp/mcd-app.tgz

echo "== unpacking =="
ssh -o BatchMode=yes mac "rm -rf $REMOTE_DIR && mkdir -p $REMOTE_DIR && tar xzf /tmp/mcd-app.tgz -C $REMOTE_DIR && cd $REMOTE_DIR && swift build 2>&1 | tail -60; echo EXIT=\${PIPESTATUS[0]}"
