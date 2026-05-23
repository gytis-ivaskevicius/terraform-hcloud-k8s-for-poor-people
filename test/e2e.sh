#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# E2E Test: k8s-for-poor-people on Hetzner Cloud
#
# Deploys a single-node control plane (CX23), verifies cluster health,
# and destroys everything. Can be run locally or in CI.
#
# Prerequisites:
#   - OpenTofu, kubectl, talosctl, helm, packer, hcloud CLI in PATH
#     (or run via `nix develop -c bash test/e2e.sh` with the flake)
#   - HCLOUD_TOKEN env var set
#
# Usage:
#   ./test/e2e.sh                    # full cycle: build → deploy → verify → destroy
#   ./test/e2e.sh --skip-image-build # skip Packer image build
#   ./test/e2e.sh --destroy-only     # just destroy any existing cluster
#   ./test/e2e.sh --help             # show this message
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$SCRIPT_DIR/minimal"
PACKER_DIR="$(cd "$SCRIPT_DIR/../example/_packer" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SKIP_IMAGE_BUILD=false
DESTROY_ONLY=false

# ── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-image-build) SKIP_IMAGE_BUILD=true; shift ;;
    --destroy-only)     DESTROY_ONLY=true; shift ;;
    --help|-h)          sed -n '3,17p' "$0"; exit 0 ;;
    *)                  echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Helpers ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

step()   { echo -e "\n${GREEN}━━━ $1 ━━━${NC}"; }
info()   { echo -e "  ${YELLOW}→${NC} $1"; }
ok()     { echo -e "  ${GREEN}✅${NC} $1"; }
fail()   { echo -e "  ${RED}❌${NC} $1"; }

cleanup_resources() {
  echo ""
  step "Cleanup"
  cd "$TEST_DIR"

  # Delete k8s test resources if kubeconfig exists
  if [ -f kubeconfig ]; then
    export KUBECONFIG="$TEST_DIR/kubeconfig"
    info "Deleting k8s test resources..."
    kubectl delete pod e2e-test-pod --ignore-not-found 2>/dev/null || true
    kubectl delete pvc e2e-test-pvc --ignore-not-found 2>/dev/null || true
    kubectl delete svc e2e-lb-svc --ignore-not-found 2>/dev/null || true
    kubectl delete pod e2e-lb-pod --ignore-not-found 2>/dev/null || true
  fi

  # Destroy Terraform infrastructure
  if [ -f terraform.tfstate ]; then
    info "Running tofu destroy..."
    tofu destroy -auto-approve -no-color 2>&1 | sed 's/^/    /'
    rm -f kubeconfig talosconfig
    ok "Cluster destroyed"
  else
    info "No cluster to destroy (no terraform.tfstate found)"
  fi
}

# Register cleanup trap
trap cleanup_resources EXIT

# ── Pre-flight checks ──────────────────────────────────────────────────────
step "Pre-flight checks"

if [ -z "${HCLOUD_TOKEN:-}" ]; then
  fail "HCLOUD_TOKEN is not set"
  exit 1
fi

for cmd in tofu kubectl talosctl packer hcloud; do
  if ! command -v "$cmd" &>/dev/null; then
    fail "Required command not found: $cmd"
    echo "  Run via nix: nix develop -c bash test/e2e.sh"
    exit 1
  fi
done
ok "All prerequisites met"

# ── Destroy only ────────────────────────────────────────────────────────────
if [ "$DESTROY_ONLY" = true ]; then
  cd "$TEST_DIR"
  if [ -f terraform.tfstate ]; then
    cleanup_resources
  else
    info "Nothing to destroy"
  fi
  exit 0
fi

# ── Phase 1: Build Talos x86 image ─────────────────────────────────────────
if [ "$SKIP_IMAGE_BUILD" = false ]; then
  step "Phase 1: Talos x86 image"

  EXISTING_ID=$(hcloud image list --selector "os=talos" --architecture x86 --output noheader --output columns=id 2>/dev/null | head -1)
  if [ -n "$EXISTING_ID" ]; then
    ok "Talos x86 image already exists (ID: $EXISTING_ID)"
    info "  Reuse or force rebuild by deleting the snapshot"
  else
    info "Building Talos x86 image via Packer..."
    cd "$PACKER_DIR"
    packer init . 2>&1 | sed 's/^/    /'
    packer build --only hcloud.talos-x86 . 2>&1 | sed 's/^/    /'
    ok "Talos x86 image built"
  fi
else
  info "Skipping image build (--skip-image-build)"
fi

# ── Phase 2: Deploy cluster ────────────────────────────────────────────────
step "Phase 2: Deploy cluster"

cd "$TEST_DIR"
# Pass token via env var (TF_VAR_hcloud_token) to avoid writing it to disk
export TF_VAR_hcloud_token="$HCLOUD_TOKEN"
trap cleanup_resources EXIT  # re-register after cd

info "tofu init..."
tofu init -no-color 2>&1 | sed 's/^/    /'

info "tofu apply..."
tofu apply -auto-approve -no-color 2>&1 | sed 's/^/    /'
tofu output -raw kubeconfig > kubeconfig
ok "Cluster deployed"

export KUBECONFIG="$TEST_DIR/kubeconfig"
PUBLIC_IP=$(tofu output -raw public_ip)
info "Control plane public IP: $PUBLIC_IP"

# ── Phase 3: Verify cluster ─────────────────────────────────────────────────
step "Phase 3: Verify cluster"

# 3a. Nodes
info "Waiting for node to be Ready..."
kubectl wait --for=condition=Ready node/control-plane-1 --timeout=120s 2>&1 | sed 's/^/    /'
kubectl get nodes -o wide 2>&1 | sed 's/^/    /'
ok "Node is Ready"

# 3b. System pods
info "Waiting for system pods..."
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=180s 2>&1 | sed 's/^/    /'
kubectl get pods -A 2>&1 | sed 's/^/    /'
ok "All system pods are Running"

# 3c. Storage (PVC + Pod)
info "Testing persistent storage..."
cat <<'EOF' | kubectl apply -f - 2>&1 | sed 's/^/    /'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: e2e-test-pvc
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
  storageClassName: hcloud-volumes
---
apiVersion: v1
kind: Pod
metadata:
  name: e2e-test-pod
  namespace: default
spec:
  containers:
  - name: test
    image: busybox:1.36
    command: ["sleep", "30"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: e2e-test-pvc
EOF
kubectl wait --for=condition=Ready pod/e2e-test-pod --timeout=60s 2>&1 | sed 's/^/    /'
info "PVC:"
kubectl get pvc -A 2>&1 | sed 's/^/    /'
ok "Storage works"

# 3d. LoadBalancer
info "Testing LoadBalancer service..."
cat <<'EOF' | kubectl apply -f - 2>&1 | sed 's/^/    /'
apiVersion: v1
kind: Pod
metadata:
  name: e2e-lb-pod
  namespace: default
  labels:
    app: e2e-lb
spec:
  containers:
  - name: whoami
    image: traefik/whoami:v1.11.0
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: e2e-lb-svc
  namespace: default
  annotations:
    load-balancer.hetzner.cloud/location: fsn1
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: e2e-lb
EOF

LB_IP=""
for i in $(seq 1 24); do
  LB_IP=$(kubectl get svc e2e-lb-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -n "$LB_IP" ]; then
    ok "LoadBalancer IP: $LB_IP"
    break
  fi
  info "  waiting for LB IP... ($i)"
  sleep 5
done

if [ -z "$LB_IP" ]; then
  info "LoadBalancer IP not assigned within timeout. CCM logs:"
  kubectl logs -n kube-system deployment/hcloud-cloud-controller-manager --tail=20 2>&1 | sed 's/^/    /'
  fail "LoadBalancer did not get an IP (known limitation: control-plane-only cluster)"
  info "  Add a worker node for LoadBalancer targets to be assigned"
  exit 1
else
  ok "LoadBalancer works"
fi

# 3e. Idempotency
info "Verifying idempotency..."
tofu plan -no-color -detailed-exitcode 2>&1 | sed 's/^/    /'
PLAN_EXIT=${PIPESTATUS[0]}
if [ "$PLAN_EXIT" -eq 2 ]; then
  fail "Plan shows changes — not idempotent!"
  exit 1
elif [ "$PLAN_EXIT" -eq 0 ]; then
  ok "Idempotent — no changes"
else
  fail "tofu plan failed (exit $PLAN_EXIT)"
  exit 1
fi

# ── Done ────────────────────────────────────────────────────────────────────
step "All E2E tests passed 🎉"
echo ""
echo "  Cluster was running at: https://$PUBLIC_IP:6443"
echo "  Cleanup will happen automatically (trap on EXIT)"
