loop this {

    from here 

        go run ./local/bin/l2sm-md/test --test-network-create

        kubectl --kubeconfig local/configs/k8s/kubeconfig-l2sm-managed-1.yaml apply -f experiments/multicast/l2sm/ping.yaml -n l2sm-system 
        kubectl --kubeconfig local/configs/k8s/kubeconfig-l2sm-managed-2.yaml apply -f experiments/multicast/l2sm/pong.yaml -n l2sm-system 

        kubectl exec -it ping --kubeconfig local/configs/k8s/kubeconfig-l2sm-managed-1.yaml -n l2sm-system -- ping pong.ping-network.inter.l2sm ? This until there is connectivity

    to here!

    kubectl --kubeconfig local/configs/k8s/kubeconfig-l2sm-managed-1.yaml delete -f experiments/multicast/l2sm/ping.yaml -n l2sm-system 
    kubectl --kubeconfig local/configs/k8s/kubeconfig-l2sm-managed-2.yaml delete -f experiments/multicast/l2sm/pong.yaml -n l2sm-system 
    kubectl --kubeconfig local/configs/k8s/kubeconfig-l2sm-managed-1.yaml delete l2network ping-network -n l2sm-system 
    kubectl --kubeconfig local/configs/k8s/kubeconfig-l2sm-managed-2.yaml delete l2network ping-network -n l2sm-system 


}