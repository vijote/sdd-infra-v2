#!/bin/bash
# Worker node bootstrap — runs ONCE at first boot (EC2 user-data).
# Installs containerd + kubeadm/kubelet/kubectl v1.28.0, loads br_netfilter +
# sysctls, fetches the join command from SSM Parameter Store (SecureString),
# and runs `kubeadm join` to attach this node to the cluster.
# CI never re-runs this — it polls node readiness via SSM Run Command.
set -euxo pipefail

exec > >(tee /var/log/bootstrap.log) 2>&1

K8S_VERSION="1.28.0"
SSM_PARAM_NAME="/sdd-k8s-platform/kubeadm-join-command"

# --- Install and configure containerd (systemd cgroup driver) ---
dnf install -y containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

# --- Install kubeadm / kubelet / kubectl (pinned to v1.28.0) ---
dnf install -y dnf-plugins-core
cat <<'EOF' > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOF
dnf install -y kubelet-${K8S_VERSION} kubeadm-${K8S_VERSION} kubectl-${K8S_VERSION}
systemctl enable --now kubelet

# --- Install AWS CLI v2 (needed for ssm get-parameter; not preinstalled on AL2023) ---
dnf install -y unzip
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q -o /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --bin-dir /usr/local/bin

# --- Load br_netfilter and enable required sysctls (kubeadm preflight requirements) ---
modprobe br_netfilter
cat <<'EOF' > /etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

# --- Fetch the join command from SSM (SecureString) and join the cluster ---
JOIN_COMMAND=$(aws ssm get-parameter \
  --name "${SSM_PARAM_NAME}" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)
if [ -z "${JOIN_COMMAND}" ]; then
  echo "ERROR: join command not found in SSM ${SSM_PARAM_NAME}" >&2
  exit 1
fi
eval "${JOIN_COMMAND}"

echo "Bootstrap complete. Worker joined the cluster."
