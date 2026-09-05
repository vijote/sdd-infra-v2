#!/bin/bash
# Control plane bootstrap — runs ONCE at first boot (EC2 user-data).
# Installs containerd + kubeadm/kubelet/kubectl v1.28.0, runs `kubeadm init`,
# and publishes the worker join command to SSM Parameter Store (SecureString).
# CI never re-runs this — it polls node readiness via SSM Run Command.
set -euxo pipefail

exec > >(tee /var/log/bootstrap.log) 2>&1

K8S_VERSION="1.28.0"
POD_CIDR="192.168.0.0/16"
SERVICE_CIDR="10.96.0.0/12"
SSM_PARAM_NAME="/sdd-k8s-platform/kubeadm-join-command"

# --- Detect private IP via IMDS (no public IP on this instance) ---
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
echo "Control plane private IP: ${PRIVATE_IP}"

# --- Install and configure containerd (systemd cgroup driver) ---
dnf install -y containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

# --- Install kubeadm / kubelet / kubectl (pinned to v1.28.0) ---
dnf install -y dnf-plugins-core
dnf config-manager --add-repo https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
dnf install -y kubelet-${K8S_VERSION} kubeadm-${K8S_VERSION} kubectl-${K8S_VERSION}
systemctl enable --now kubelet

# --- Install AWS CLI v2 (needed for ssm put-parameter; not preinstalled on AL2023) ---
dnf install -y unzip
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q -o /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --bin-dir /usr/local/bin

# --- Write kubeadm config (cert SANs = private IP + localhost, pod CIDR, control-plane-endpoints) ---
cat > /etc/kubernetes/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${PRIVATE_IP}
  bindPort: 6443
nodeRegistration:
  name: control-plane-0
  criSocket: unix:///run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v${K8S_VERSION}
controlPlaneEndpoint: ${PRIVATE_IP}:6443
networking:
  podSubnet: ${POD_CIDR}
  serviceSubnet: ${SERVICE_CIDR}
apiServer:
  certSANs:
    - ${PRIVATE_IP}
    - localhost
    - 127.0.0.1
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

# --- Run kubeadm init ---
kubeadm init --config /etc/kubernetes/kubeadm-config.yaml

# --- Make kubectl usable by root (for SSM verification commands) ---
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config

# --- Generate the worker join command and publish it to SSM (SecureString) ---
JOIN_COMMAND=$(kubeadm token create --print-join-command)
aws ssm put-parameter \
  --name "${SSM_PARAM_NAME}" \
  --type SecureString \
  --value "${JOIN_COMMAND}" \
  --overwrite

echo "Bootstrap complete. Join command published to ${SSM_PARAM_NAME}"
