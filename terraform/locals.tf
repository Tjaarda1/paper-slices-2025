locals {
  control_clusters = [for c in var.clusters : c if !strcontains(c, "managed")]
 managed_clusters = [for c in var.clusters : c if strcontains(c, "managed")]

  workers = flatten([
    for c in local.managed_clusters : [
      for i in range(1, var.worker_count + 1) : {
        cluster = c
        idx     = i
      }
    ]
  ])
}