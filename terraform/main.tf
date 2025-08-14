terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
      version = "3.3.2"
    }
  }
}
provider "openstack" {
  auth_url    = var.auth_url
  tenant_name = var.tenant_name
  user_name   = var.user_name
  password    = var.password
  region      = var.region_name
}

resource "openstack_compute_instance_v2" "control_nodes" {
 for_each = toset(var.clusters)
  name          = "${each.key}-control"
  image_name    = var.image_name
  flavor_name   = var.control_flavor
  key_pair      = var.keypair_name
  security_groups = ["default"]
  user_data = file("${path.module}/cloud-init/enable-password.yml")

  network {
    name = var.network_name
  }

  metadata = {
    role = "control-node"
    cluster = each.key
  }
}

variable "worker_count" {
  type    = number
  default = 2
}



resource "openstack_compute_instance_v2" "worker_nodes" {
  # one instance per (cluster, idx)
  for_each = {
    for w in local.workers :
    "${w.cluster}-${w.idx}" => w
  }

  name        = "${each.value.cluster}-worker-${each.value.idx}"
  image_name  = var.image_name
  flavor_name = var.worker_flavor
  key_pair    = var.keypair_name
  security_groups = ["default"]
  user_data   = file("${path.module}/cloud-init/enable-password.yml")

  network {
    name = var.network_name
  }

  metadata = {
    role    = "worker-node"
    cluster = each.value.cluster
    index   = tostring(each.value.idx)
  }
}


resource "openstack_compute_instance_v2" "prometheus_monitor" {
  name        = "monitoring-1"
  image_name  = var.image_name
  flavor_name = var.control_flavor
  key_pair    = var.keypair_name
  user_data = file("${path.module}/cloud-init/enable-password.yml")
  security_groups = ["default"]

  network {
    name = var.network_name
  }

  metadata = {
    role = "monitoring"
  }
} 