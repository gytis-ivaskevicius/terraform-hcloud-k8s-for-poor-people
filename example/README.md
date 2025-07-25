
# Getting Started

## 1. Build Talos OS Images

Before deploying, build Talos OS images for Hetzner Cloud using Packer:

```bash
./_packer/create.sh
```

This creates both ARM and x86 Talos images and uploads them as Hetzner snapshots. You can customize the Talos version and extensions using the Talos Image Factory.

To build custom images with extensions, generate schematic IDs and override image URLs in `hcloud.auto.pkrvars.hcl`.

---

## 2. Configure the Cluster

Edit [main.tf](./main.tf) to suit your needs.

---

## 3. Deploy the Cluster

Create a `terraform.tfvars` file with required values (e.g. API keys), or export them as environment variables.

Then run:

```bash
terraform init
terraform apply
```

---

## 4. Retrieve Configuration Files

After deployment, export the kubeconfig and Talos config:

```bash
terraform output --raw kubeconfig > ./kubeconfig
terraform output --raw talosconfig > ./talosconfig
```

Use `kubectl` and `talosctl` with these configs to manage your cluster.

---

## 5. Accessing the Traefik Dashboard

Port-forward the Traefik dashboard to your local machine:

```bash
NAMESPACE=traefik
kubectl port-forward $(kubectl get pods --selector "app.kubernetes.io/name=traefik" --output=name -n $NAMESPACE) 8080:8080 -n $NAMESPACE
```

Then open [http://localhost:8080](http://localhost:8080) in your browser.

---

## 6. Testing Cloudflare Integration

Edit `./demo.yaml` and replace the hostname with your domain of choice.
Apply the config:

```bash
kubectl apply -f ./demo.yaml
```

After a few minutes, the demo application should be accessible at your specified hostname.

---
