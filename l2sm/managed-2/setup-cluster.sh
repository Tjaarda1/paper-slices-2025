CLUSTER_NAME=managed-2
DIRECTORY=$(pwd)/l2sm/$(CLUSTER_NAME)
KUBECONFIG=$(DIRECTORY)/kubeconfig
kind create cluster --kubeconfig $KUBECONFIG --config $(DIRECTORY)/cluster.yaml

wget -q https://github.com/containernetworking/plugins/releases/download/v1.6.0/cni-plugins-linux-amd64-v1.6.0.tgz
mkdir -p plugins/bin
tar -xf cni-plugins-linux-amd64-v1.6.0.tgz -C plugins/bin
rm cni-plugins-linux-amd64-v1.6.0.tgz

# copy necessary plugins into all nodes
docker cp ./plugins/bin/. l2sm-$(CLUSTER_NAME)-control-plane:/opt/cni/bin
docker cp ./plugins/bin/. l2sm-$(CLUSTER_NAME)-worker:/opt/cni/bin
docker cp ./plugins/bin/. l2sm-$(CLUSTER_NAME)-worker2:/opt/cni/bin
docker exec -it l2sm-$(CLUSTER_NAME)-control-plane modprobe br_netfilter
docker exec -it l2sm-$(CLUSTER_NAME)-worker modprobe br_netfilter
docker exec -it l2sm-$(CLUSTER_NAME)-worker2 modprobe br_netfilter

docker exec -it l2sm-$(CLUSTER_NAME)-control-plane sysctl -p /etc/sysctl.conf
docker exec -it l2sm-$(CLUSTER_NAME)-worker sysctl -p /etc/sysctl.conf
docker exec -it l2sm-$(CLUSTER_NAME)-worker2 sysctl -p /etc/sysctl.conf


kubectl --kubeconfig $KUBECONFIG apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl --kubeconfig $KUBECONFIG wait --for=condition=Ready pods -n kube-flannel -l app=flannel --timeout=300s


kubectl --kubeconfig $KUBECONFIG apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml
kubectl --kubeconfig $KUBECONFIG apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
