terraform {
  required_version = ">= 1.9.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.63.0"
    }

    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.11.0"
    }

    http = {
      source  = "hashicorp/http"
      version = ">= 3.6.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.1.1"
    }

    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.2.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.1.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.3.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "kubernetes" {
  host                   = module.talos.kubeconfig_data.host
  cluster_ca_certificate = module.talos.kubeconfig_data.cluster_ca_certificate
  client_certificate     = module.talos.kubeconfig_data.client_certificate
  client_key             = module.talos.kubeconfig_data.client_key
}

provider "helm" {
  kubernetes = {
    host                   = module.talos.kubeconfig_data.host
    client_certificate     = module.talos.kubeconfig_data.client_certificate
    client_key             = module.talos.kubeconfig_data.client_key
    cluster_ca_certificate = module.talos.kubeconfig_data.cluster_ca_certificate
  }
}

provider "kubectl" {
  host                   = module.talos.kubeconfig_data.host
  cluster_ca_certificate = module.talos.kubeconfig_data.cluster_ca_certificate
  client_certificate     = module.talos.kubeconfig_data.client_certificate
  client_key             = module.talos.kubeconfig_data.client_key
  load_config_file       = false
  apply_retry_count      = 3
}

locals {
  allowed_ips = ["0.0.0.0/0", "::/0"]
}

module "talos" {
  source = "../../"

  hcloud_token      = var.hcloud_token
  cluster_name      = "test-k8s"
  talos_version     = "v1.13.2"
  datacenter        = "fsn1-dc14"
  kubernetes_version = "1.36.0"

  # Single control plane — cheapest config
  control_planes = {
    control-plane = {
      server_type  = "cx23"
      count        = 1
    }
  }

  # Disable autoscaler (no worker pools needed for basic validation)
  autoscaler_nodepools = {}

  # Pin versions to match the module defaults
  cilium = {
    enabled = true
    version = "1.19.4"
    values  = {}
  }

  hcloud_ccm = {
    enabled   = true
    version   = "1.31.0"
    namespace = "kube-system"
    values    = {}
  }

  hcloud_csi = {
    enabled   = true
    version   = "2.21.0"
    namespace = "kube-system"
    values    = null
  }

  # Open API access for testing (restrict in production!)
  firewall_kube_api_source  = local.allowed_ips
  firewall_talos_api_source = local.allowed_ips

  # Disable features not needed for basic validation
  enable_ipv6       = false
  enable_kube_span  = false
  enable_floating_ip = false
  enable_alias_ip   = true

  # Dummy SSH key prevents Hetzner credential emails
  ssh_public_key = null

  # Only x86 needed for CX23 server
  disable_arm = true
  disable_x86 = false
}
