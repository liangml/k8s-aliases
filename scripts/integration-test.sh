#!/bin/bash
set -eux

APP="./kubectl-aliases"

echo "=== Step 1: Check binary exists ==="
ls -la "$APP"
"$APP" --version

echo "=== Step 2: Generate aliases ==="
"$APP" -o /tmp/_test_aliases
echo "Generated OK"

echo "=== Step 3: Check cluster ==="
kubectl cluster-info 2>&1
echo "Cluster OK"

echo "=== Step 4: Create resources ==="
kubectl create ns test-aliases --dry-run=client -o yaml | kubectl apply -f -
kubectl -n test-aliases create deployment nginx --image=nginx:alpine
echo "Resources created"

echo "=== SUCCESS ==="
