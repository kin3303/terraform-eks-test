
## Install kubectl CLI
- https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html

## kubeconfig
- https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html#eks-configure-kubectl


## Test
- https://kubernetes.io/docs/reference/kubectl/cheatsheet/

```console
aws eks --region ap-northeast-2 update-kubeconfig --name IDT-dev-eks-demo-cluster
kubectl get nodes
kubectl get nodes -o wide
kubectl get namespaces
kubectl get all -n kube-node-lease
kubectl get all -n kube-public
kubectl get all -n default
kubectl describe ds aws-node -n kube-system
kubectl describe ds kube-proxy -n kube-system
kubectl describe deploy coredns -n kube-system

# deployment + service(nlb) 배포 테스트
kubectl apply -f loadbalancer.yaml
kubectl get svc nlb-sample-service -n lbtest  
kubectl delete -f loadbalancer.yaml

```

## Bastion Host 에서 EKS Worker Node 접속후 아래 확인

```console
cd /tmp
ssh -i eks-terraform-key.pem ec2-user@<WorkerNodeIP>
ps -ef | grep kube
cat /etc/kubernetes/kubelet/kubelet-config.json
cat /var/lib/kubelet/kubeconfig
wget <kubernetes endpoint>
```

