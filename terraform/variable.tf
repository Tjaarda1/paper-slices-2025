variable "auth_url" {}
variable "user_name" {}
variable "password" {}
variable "tenant_name" {}
variable "region_name" {}

variable "image_name" {
  default = "Ubuntu 22.04 LTS Cloud"
}

variable "network_name" {
  default = "control-provider"
}

variable "keypair_name" {
  default = "openstack-access"
}

variable "worker_flavor" {
  default = "C2_R4_D20"
}

variable "control_flavor" {
  default = "C4_R8_D50"
}

variable "clusters" {
  type = list(string)
  default = [
    "sub-control",
    "l2sm-control",
    "sub-managed-1",
    "sub-managed-2",
    "l2sm-managed-1",
    "l2sm-managed-2"
  ]
}