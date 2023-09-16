#---------------------------------------------------------------------------------------------------------------------------------------------------------
#
# reference site: https://velog.io/@seokbin/Kubeflow-V1.4-%EC%84%A4%EC%B9%98-%EB%B0%8F-%EC%B4%88%EA%B8%B0-%EC%84%A4%EC%A0%95User-%EC%B6%94%EA%B0%80-CORS
#
#---------------------------------------------------------------------------------------------------------------------------------------------------------

#!/bin/bash

MASTER_IP=
CURRENT_DIR=$PWD

sudo docker login

# download kubeflow manifest repository
cd ~
git clone https://github.com/kubeflow/manifests.git -b v1.6-branch

# enable kubeflow to be accessed through https (1)
cat << EOF >> ~/manifests/common/istio-1-14/kubeflow-istio-resources/base/kf-istio-resources.yaml
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

# enable kubeflow to be accessed through https (2)
#sed -i "s/true/false/g" ~/manifests/apps/jupyter/jupyter-web-app/upstream/base/params.env
#sed -i "s/true/false/g" ~/manifests/apps/volumes-web-app/upstream/base/params.env
#sed -i "s/true/false/g" ~/manifests/apps/tensorboard/tensorboards-web-app/upstream/base/params.env

# download kustomize 5.0.0 which is stable with kubeflow 1.7.0 then copy it into /bin/bash
wget https://github.com/kubernetes-sigs/kustomize/releases/download/v3.2.0/kustomize_3.2.0_linux_amd64
sudo chmod +x kustomize_3.2.0_linux_amd64
sudo mv kustomize_3.2.0_linux_amd64 /usr/bin/kustomize

# install kubeflow as a single command
cd ~/manifests
while ! kustomize build example | kubectl apply -f -; do echo "Retrying to apply resources"; sleep 10; done

# create certification for https connection
sed -i 's/MASTER_IP/'"${MASTER_IP}"'/g' ${CURRENT_DIR}/certificate.yaml
kubectl apply -f ${CURRENT_DIR}/certificate.yaml
