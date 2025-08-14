output "cluster_ips" {
  value = {
    for _, instance in merge(
      openstack_compute_instance_v2.control_nodes,
      openstack_compute_instance_v2.worker_nodes
    ) :
    instance.name => {
      ip      = instance.access_ip_v4
      cluster = instance.metadata.cluster
      role    = instance.metadata.role
    }
  }
}


output "prometheus_ip" {
  value = openstack_compute_instance_v2.prometheus_monitor.access_ip_v4
}
