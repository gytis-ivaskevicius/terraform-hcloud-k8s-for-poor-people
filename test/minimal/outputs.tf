output "kubeconfig" {
  value     = module.talos.kubeconfig
  sensitive = true
}

output "talosconfig" {
  value     = module.talos.talosconfig
  sensitive = true
}

output "kubeconfig_data" {
  value     = module.talos.kubeconfig_data
  sensitive = true
}

output "public_ip" {
  value     = module.talos.public_ipv4_list
}
