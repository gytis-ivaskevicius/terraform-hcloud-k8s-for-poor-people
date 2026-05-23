# Test Infrastructure

This directory contains minimal test configurations for validating the module.

## Prerequisites

- [OpenTofu](https://opentofu.org/) or Terraform >= 1.9
- [Talosctl](https://www.talos.dev/v1.13/introduction/getting-started/#talosctl)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/)
- A Hetzner Cloud API token

## CI Workflows

Two GitHub Actions workflows use this test configuration:

### 1. OpenTofu Plan Check (`.github/workflows/dev-experience.yml`)

Runs on every PR to `master`. Initializes and plans the `test/minimal` configuration
using OpenTofu. Requires the `HCLOUD_TOKEN` repository secret.

### 2. E2E Test (`.github/workflows/e2e.yml`)

Triggers on:
- `workflow_dispatch` (manual)
- PRs labeled `e2e-test`

Provisions a real cluster on Hetzner Cloud, runs full verification (nodes, system pods,
storage, LoadBalancer, idempotency), then destroys everything.

The E2E workflow delegates to `test/e2e.sh`, which can also be run locally. The plan-check job runs `tofu init` and `tofu plan` directly without the script.

## Automated E2E Script (`test/e2e.sh`)

A single entry point for both local and CI use:

```bash
# Full cycle: build → deploy → verify → destroy
export HCLOUD_TOKEN="your-hetzner-token"
bash test/e2e.sh

# Skip image build (use existing snapshot)
bash test/e2e.sh --skip-image-build

# Just destroy any existing cluster
bash test/e2e.sh --destroy-only
```

Prerequisites: `tofu`, `kubectl`, `packer`, `hcloud` in PATH, or run via:
```bash
nix develop -c bash test/e2e.sh
```

## Manual Run

Deploys a single-node control plane + Cilium + CCM + CSI, without any Cloudflare or
ingress dependencies. Use this to verify core module functionality locally.

```bash
cd test/minimal

# Create tfvars
cat > terraform.tfvars <<'EOF'
hcloud_token = "<your-hetzner-token>"
EOF

tofu init
tofu plan
tofu apply -auto-approve

# Verify cluster is up
export KUBECONFIG=$(pwd)/kubeconfig
tofu output -raw kubeconfig > kubeconfig
kubectl get nodes
kubectl get pods -A

# Clean up
tofu destroy -auto-approve
```

## What Gets Created

| Resource | Type | Cost |
|---|---|---|
| CX23 server | Control plane | ~€6/mo |
| Primary IPv4 | IP address | Free |
| Network / Subnet | Private network | Free |
| Firewall | Security rules | Free |
| Cilium | CNI (helm) | Free |
| hcloud-ccm | Cloud controller | Free |
| hcloud-csi | Storage driver | Free |

Total: ~€6/month while running. A full validation takes ~15 minutes.

## Manual Verification Steps

After `tofu apply` succeeds:

1. **Node status**: `kubectl get nodes -o wide` → should show 1 Ready node
2. **System pods**: `kubectl get pods -n kube-system` → cilium, ccm, csi should be Running
3. **Storage**: Create a test PVC to verify hcloud-csi works
4. **Load balancer**: Deploy a test service with LoadBalancer type
5. **Reapply**: Run `tofu plan` again → should show no changes (idempotent)
