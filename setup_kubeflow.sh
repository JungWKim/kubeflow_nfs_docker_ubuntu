#!/bin/bash

MASTER_IP=
CURRENT_DIR=$PWD

sudo docker login

# download kubeflow manifest repository
cd ~
git clone https://github.com/kubeflow/manifests.git -b v1.8-branch

# enable kubeflow to be accessed through https (1)
cat << EOF >> ~/manifests/common/istio-1-16/kubeflow-istio-resources/base/kf-istio-resources.yaml
    tls:
      httpsRedirect: true
  - hosts:
    - '*'
    port:
      name: https
      number: 443
      protocol: HTTPS
    tls:
      mode: SIMPLE
      privateKey: /etc/istio/ingressgateway-certs/tls.key
      serverCertificate: /etc/istio/ingressgateway-certs/tls.crt
EOF

# enable kubeflow to be accessed through https (1)
cat << EOF >> ~/manifests/common/istio-1-17/kubeflow-istio-resources/base/kf-istio-resources.yaml
    tls:
      httpsRedirect: true
  - hosts:
    - '*'
    port:
      name: https
      number: 443
      protocol: HTTPS
    tls:
      mode: SIMPLE
      privateKey: /etc/istio/ingressgateway-certs/tls.key
      serverCertificate: /etc/istio/ingressgateway-certs/tls.crt
EOF

# enable kubeflow to be accessed through http
#sed -i "s/true/false/g" ~/manifests/apps/jupyter/jupyter-web-app/upstream/base/params.env
#sed -i "s/true/false/g" ~/manifests/apps/volumes-web-app/upstream/base/params.env
#sed -i "s/true/false/g" ~/manifests/apps/tensorboard/tensorboards-web-app/upstream/base/params.env

# change service as nodeport
sed -i "s/ClusterIP/NodePort/g" ~/manifests/common/dex/base/service.yaml
sed -i "s/ClusterIP/NodePort/g" ~/manifests/common/istio-1-16/istio-install/base/patches/service.yaml
sed -i "s/ClusterIP/NodePort/g" ~/manifests/common/istio-1-17/istio-install/base/patches/service.yaml

# download kustomize 5.0.3 which is stable with kubeflow 1.8.0 then copy it into /bin/bash
wget https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.0.3/kustomize_v5.0.3_linux_amd64.tar.gz
tar -xvf kustomize_v5.0.3_linux_amd64.tar.gz
sudo mv ~/kustomize /usr/bin/

# install kubeflow as a single command
cd ~/manifests
while ! kustomize build example | kubectl apply -f -; do echo "Retrying to apply resources"; sleep 10; done

# create certification for https connection
sed -i 's/MASTER_IP/'"${MASTER_IP}"'/g' ${CURRENT_DIR}/certificate.yaml
kubectl apply -f ${CURRENT_DIR}/certificate.yaml
