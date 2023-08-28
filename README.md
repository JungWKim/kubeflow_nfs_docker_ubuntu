# Summary
### OS : Ubuntu 22.04
### CRI : Docker latest
### k8s : 1.24.6 deployed by kubespray release-2.20
### CNI : calico
### Kubeflow version : 1.7
### kustomize version : 5.0.0
### storageclass : nfs-provisioner
### etc : gpu-operator
#
# How to use this repository
### * you don't need to execute setup_server repository in advance.
### 1. run bootstrap.sh without sudo in a master node
### 2. run add_node.sh without sudo in every worker and other master nodes.
### 3. run setup_nfs_provisioner.sh without sudo in a master node
### 4. run setup_kubeflow.sh without sudo
#
# how to uninstall gpu-operator
### 1. helm delete -n gpu-operator $(helm list -n gpu-operator | grep gpu-operator | awk '{print $1}')
#
# how to delete kubeflow
### 1. change directory to manifests
### 2. kustomize build example | awk '!/well-defined/' | kubectl delete -f -
### 3. delete all namespaces related with kubeflow(kubeflow, kubeflow-user-example-com, knative-serving, knative-eventing, istio-system, cert-manager)
### 4. delete all data in nfs server
#
# how to connect kubeflow with http
### 1. comment below parts in setup_kubeflow.sh
![image](https://github.com/JungWKim/kubeflow_nfs_docker_ubuntu2004/assets/50034678/70055f8b-d63a-4d36-a80b-3872c67a52bc)
![image](https://github.com/JungWKim/kubeflow_nfs_docker_ubuntu2004/assets/50034678/bda83d0e-5e74-4442-a2b6-d15ce02a18c3)
### 2. uncomment beflow part in setup_kubeflow.sh
![image](https://github.com/JungWKim/kubeflow_nfs_docker_ubuntu2004/assets/50034678/22e17942-02ae-444a-8de7-600d3d6c3005)


# 이외에도 추가적인 내용은 kubespray_ubuntu 레포지토리 참고할 것
