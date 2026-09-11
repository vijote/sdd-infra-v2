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

# --- Detect private IP via IMDSv2 (AL2023 enforces token-based metadata) ---
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
  http://169.254.169.254/latest/meta-data/local-ipv4)
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
  http://169.254.169.254/latest/meta-data/instance-id)
# Fail fast if IMDS returned empty values (e.g. token expired or IMDS unreachable).
[ -n "${PRIVATE_IP}" ] && [ -n "${INSTANCE_ID}" ] || {
  echo "IMDS fetch failed (PRIVATE_IP='${PRIVATE_IP}' INSTANCE_ID='${INSTANCE_ID}')" >&2
  exit 1
}
echo "Control plane private IP: ${PRIVATE_IP} (instance ${INSTANCE_ID})"

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

# --- Install AWS CLI v2 (needed for ssm put-parameter; not preinstalled on AL2023) ---
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

# --- Publish the per-run bootstrap-complete signal (this instance's ID) ---
# The Flannel gate and worker bootstrap wait for this to equal the current control
# plane instance ID, which makes the signal per-run (a stale value from a previous
# run never matches). Published LAST so its presence implies the join command is fresh.
# INSTANCE_ID was captured at the top of the script (while the IMDS token was fresh);
# the instance ID is immutable for the instance's lifetime, so reusing it is safe.
aws ssm put-parameter \
  --name "/sdd-k8s-platform/kubeadm-bootstrap-instance-id" \
  --type String \
  --value "${INSTANCE_ID}" \
  --overwrite

echo "Bootstrap complete. Join command published to ${SSM_PARAM_NAME}; instance-id signal = ${INSTANCE_ID}"
