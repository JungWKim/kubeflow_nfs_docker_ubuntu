#!/bin/bash

IP=
CURRENT_DIR=$PWD

sudo docker login

if [ -e /etc/needrestart/needrestart.conf ] ; then
	# disable outdated librareis pop up
	sudo sed -i "s/\#\$nrconf{restart} = 'i'/\$nrconf{restart} = 'a'/g" /etc/needrestart/needrestart.conf
	# disable kernel upgrade hint pop up
	sudo sed -i "s/\#\$nrconf{kernelhints} = -1/\$nrconf{kernelhints} = 0/g" /etc/needrestart/needrestart.conf
fi

# install basic packages
sudo apt update
sudo apt install -y python3-pip net-tools nfs-common whois xfsprogs

# basic setup
sudo sed -i 's/1/0/g' /etc/apt/apt.conf.d/20auto-upgrades

# disable ufw
sudo systemctl stop ufw
sudo systemctl disable ufw

cat <<EOF | sudo tee -a /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

# ssh configuration
ssh-keygen -t rsa
ssh-copy-id -i ~/.ssh/id_rsa ${USER}@${IP}

# k8s installation via kubespray
cd ~
git clone -b release-2.18 https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
pip install -r requirements.txt

echo "export PATH=${HOME}/.local/bin:${PATH}" | sudo tee ${HOME}/.bashrc > /dev/null
export PATH=${HOME}/.local/bin:${PATH}
source ${HOME}/.bashrc

cp -rfp inventory/sample inventory/mycluster
declare -a IPS=(${IP})
CONFIG_FILE=inventory/mycluster/hosts.yaml python3 contrib/inventory_builder/inventory.py ${IPS[@]}

# use docker container runtime
sed -i "s/docker_version: '20.10'/docker_version: 'latest'/g" roles/container-engine/docker/defaults/main.yml
sed -i "s/docker_containerd_version: 1.4.12/docker_containerd_version: latest/g" roles/download/defaults/main.yml
sed -i "s/container_manager: containerd/container_manager: docker/g" inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
sed -i "s/etcd_deployment_type: host/etcd_deployment_type: docker/g" inventory/mycluster/group_vars/etcd.yml
sed -i "s/host_architecture }}]/host_architecture }} signed-by=\/etc\/apt\/keyrings\/docker.gpg]/g" roles/container-engine/docker/vars/ubuntu.yml
sed -i "s/# docker_cgroup_driver: systemd/docker_cgroup_driver: systemd/g" inventory/mycluster/group_vars/all/docker.yml
sed -i "s/# docker_storage_options: -s overlay2/docker_storage_options: -s overlay2/g" inventory/mycluster/group_vars/all/docker.yml

# change kube_proxy_mode to iptables
sed -i "s/kube_proxy_mode: ipvs/kube_proxy_mode: iptables/g" roles/kubespray-defaults/defaults/main.yaml
sed -i "s/kube_proxy_mode: ipvs/kube_proxy_mode: iptables/g" inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

# remove aufs-tools in specific yml file (ubuntu 22.04 bug)
OS_DIST=$(. /etc/os-release;echo $ID$VERSION_ID)

if [ "${OS_DIST}" == "ubuntu22.04" ] ; then
	sed -i "/aufs-tools/d" roles/kubernetes/preinstall/vars/ubuntu.yml
fi

# download docker gpg
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# enable dashboard / disable dashboard login / change dashboard service as nodeport
sed -i "s/# dashboard_enabled: false/dashboard_enabled: true/g" inventory/mycluster/group_vars/k8s_cluster/addons.yml
sed -i "s/dashboard_skip_login: false/dashboard_skip_login: true/g" roles/kubernetes-apps/ansible/defaults/main.yml
sed -i'' -r -e "/targetPort: 8443/a\  type: NodePort" roles/kubernetes-apps/ansible/templates/dashboard.yml.j2

# enable helm
sed -i "s/helm_enabled: false/helm_enabled: true/g" inventory/mycluster/group_vars/k8s_cluster/addons.yml

# disable nodelocaldns
sed -i "s/enable_nodelocaldns: true/enable_nodelocaldns: false/g" inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

# enable kubectl & kubeadm auto-completion
echo "source <(kubectl completion bash)" >> ${HOME}/.bashrc
echo "source <(kubeadm completion bash)" >> ${HOME}/.bashrc
echo "source <(kubectl completion bash)" | sudo tee -a /root/.bashrc
echo "source <(kubeadm completion bash)" | sudo tee -a /root/.bashrc
source ${HOME}/.bashrc

ansible-playbook -i inventory/mycluster/hosts.yaml  --become --become-user=root cluster.yml -K
sleep 30
cd ~

# enable kubectl in admin account and root
mkdir -p ${HOME}/.kube
sudo cp -i /etc/kubernetes/admin.conf ${HOME}/.kube/config
sudo chown ${USER}:${USER} ${HOME}/.kube/config

# create sa and clusterrolebinding of dashboard to get cluster-admin token
kubectl apply -f ${CURRENT_DIR}/sa.yaml
kubectl apply -f ${CURRENT_DIR}/clusterrolebinding.yaml

# install gpu-operator
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia \
  && helm repo update

helm install --wait --generate-name \
     -n gpu-operator --create-namespace \
     nvidia/gpu-operator
