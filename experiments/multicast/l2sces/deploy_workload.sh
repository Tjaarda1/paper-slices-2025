go run ./local/bin/l2sm-md/test --test-network-create

kubectl --kubeconfig local/configs/k8s/kubeconfig-l2sces-managed-1.yaml apply -f experiments/multicast/l2sces/server.yaml -n l2sces-system 
kubectl --kubeconfig local/configs/k8s/kubeconfig-l2sces-managed-2.yaml apply -f experiments/multicast/l2sces/sub-1.yaml -n l2sces-system 
kubectl --kubeconfig local/configs/k8s/kubeconfig-l2sces-managed-2.yaml apply -f experiments/multicast/l2sces/sub-2.yaml -n l2sces-system 
