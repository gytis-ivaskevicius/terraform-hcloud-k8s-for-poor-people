# Automated Testing Strategy

This Terraform module provisions **real Hetzner Cloud infrastructure** — there's no
way to mock the API or run unit tests that cover actual cluster bootstrapping.
Testing strategy is a trade-off between coverage and cost.

## Tier 1: Static Analysis (every PR, free)

Already set up in `.github/workflows/dev-experience.yml`:

- `terraform fmt` — formatting
- `terraform validate` — syntax + provider validation
- `commitlint` — conventional commit format
- `checkov` — security scanning
- `tflint` (via pre-commit) — best practices

**What's missing:** `terraform plan` against an actual state. You can add a
`terraform plan` step that uses a dummy backend, but it won't catch logic errors
that only surface during apply (e.g., Talos API failures, network conflicts).

## Tier 2: Plan Validation (every PR, near-free)

Add a CI step that runs `terraform plan` using the `example/demo.yaml` config.
This catches:
- Provider version incompatibilities
- Variable type mismatches
- Resource key conflicts
- Missing required variables

Without real credentials it'll init+validate but can't plan. To get a real plan
you'd need a Hetzner API token in CI secrets.

## Tier 3: Scheduled Integration Test (weekly, ~€0.50-1.50/run)

A GitHub Actions workflow that:
1. Checks out the repo
2. Creates a Hetzner test project (or uses a dedicated project)
3. Runs `tofu apply` with `test/minimal`
4. Runs verification commands (`kubectl get nodes`, `kubectl get pods -A`)
5. Runs `tofu destroy`

```yaml
name: Integration Test
on:
  schedule:
    - cron: '0 6 * * 1'  # Monday 06:00 UTC
  workflow_dispatch:

jobs:
  deploy-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: hashicorp/setup-terraform@v4
        with:
          terraform_version: ~1.10.0
      - name: Install talosctl & kubectl
        run: |
          curl -sL https://talos.dev/install | sh
          curl -sLO https://dl.k8s.io/release/v1.36.0/bin/linux/amd64/kubectl
          chmod +x kubectl && sudo mv kubectl /usr/local/bin/
      - name: Deploy
        run: |
          cd test/minimal
          cat > terraform.tfvars <<EOF
          hcloud_token = "${{ secrets.HCLOUD_TOKEN }}"
          EOF
          terraform init
          terraform apply -auto-approve
      - name: Verify cluster
        run: |
          cd test/minimal
          terraform output -raw kubeconfig > kubeconfig
          KUBECONFIG=$(pwd)/kubeconfig kubectl get nodes -o wide
          KUBECONFIG=$(pwd)/kubeconfig kubectl get pods -A
          KUBECONFIG=$(pwd)/kubeconfig kubectl get storageclass
      - name: Destroy
        if: always()
        run: |
          cd test/minimal
          terraform destroy -auto-approve
```

**Cost:** ~€6/hr for the CX22 server. A full test cycle (deploy + verify +
destroy) takes ~10-15 minutes = ~€1-1.50 per run. Weekly = ~€5-6/month.

## Tier 4: Matrix Integration Test (before release, on-demand)

Same as Tier 3 but across a version matrix:
- Talos v1.12 / K8s 1.35 / Cilium 1.19
- Talos v1.13 / K8s 1.36 / Cilium 1.19
- ARM nodes vs x86 nodes
- Single vs HA control plane (3 nodes)

## Recommended Setup

For this repo's maturity level (single maintainer, community project), I recommend:

1. **Static analysis on every PR** ✅ (already done, just maintain it)
2. **`terraform plan` on every PR** — add a step that runs plan against a
   dedicated Hetzner project using secrets
3. **Weekly integration test** — the minimal `test/minimal` config is designed
   for this. ~€5-6/month for the confidence that the example actually works.
4. **Manual smoke test before releases** — run the full example manually
