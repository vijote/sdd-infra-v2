# MySQL secrets (005-mysql-statefulset) — SSM Parameter Store is the single source of
# truth (SecureString, created manually one-time). Read-only datasources; the deploy
# role already has ssm:GetParameter via PowerUserAccess. No GitHub secrets involved.
data "aws_ssm_parameter" "mysql_root_password" {
  name = "/sdd-k8s-platform/secrets/mysql-root-password"
}

data "aws_ssm_parameter" "mysql_password" {
  name = "/sdd-k8s-platform/secrets/mysql-password"
}

module "terraform_backend" {
  source = "../../modules/terraform-backend"

  state_bucket_name = var.state_bucket_name
  region            = var.region
}

module "vpc" {
  source = "../../modules/vpc"

  region             = var.region
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "1"
  }
}

module "cluster_plumbing" {
  source = "../../modules/cluster-plumbing"

  region   = var.region
  vpc_id   = module.vpc.vpc_id
  vpc_cidr = var.vpc_cidr

  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "3"
  }
}

module "control_plane" {
  source = "../../modules/control-plane"

  region                          = var.region
  vpc_id                          = module.vpc.vpc_id
  private_subnet_ids              = module.vpc.private_subnet_ids
  control_plane_security_group_id = module.cluster_plumbing.control_plane_security_group_id
  node_iam_instance_profile_name  = module.cluster_plumbing.node_iam_instance_profile_name

  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "3"
  }
}

module "worker_nodes" {
  source = "../../modules/worker-nodes"

  region                         = var.region
  vpc_id                         = module.vpc.vpc_id
  private_subnet_ids             = module.vpc.private_subnet_ids
  worker_security_group_id       = module.cluster_plumbing.worker_security_group_id
  node_iam_instance_profile_name = module.cluster_plumbing.node_iam_instance_profile_name
  control_plane_instance_id      = module.control_plane.control_plane_instance_id

  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "3"
  }
}

# Flannel CNI — applied on the control plane via SSM Run Command (P7: version-controlled, re-runnable).
# The local-exec runs on the CI runner (which has the assumed-role AWS credentials); it only issues the
# SSM send-command. The actual `kubectl apply` runs on the control plane instance.
locals {
  flannel_version      = "v0.24.0"
  flannel_manifest_url = "https://raw.githubusercontent.com/flannel-io/flannel/${local.flannel_version}/Documentation/kube-flannel.yml"
}

resource "null_resource" "apply_flannel_cni" {
  depends_on = [module.worker_nodes]

  # Re-apply the CNI when the pinned Flannel version changes
  triggers = {
    flannel_version = local.flannel_version
    pod_cidr        = "192.168.0.0/16"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      FLANNEL_URL="${local.flannel_manifest_url}"
      # Wait for the control plane's SSM agent to register (fresh instance: the agent
      # starts after boot and lags behind the EC2 'running' state Terraform waits for).
      for i in $(seq 1 30); do
        SSM_ID=$(aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=$${INSTANCE_ID}" \
          --query 'InstanceInformationList[0].InstanceId' --output text 2>/dev/null) || SSM_ID="Pending"
        if [ "$${SSM_ID}" = "$${INSTANCE_ID}" ]; then
          echo "SSM agent registered for $${INSTANCE_ID}"
          break
        fi
        sleep 10
      done
      if [ "$${SSM_ID}" != "$${INSTANCE_ID}" ]; then
        echo "SSM agent did not register for $${INSTANCE_ID} within timeout" >&2
        exit 1
      fi
      # Wait for bootstrap completion: the control plane bootstrap publishes its own
      # instance ID to the bootstrap-instance-id parameter as its LAST step (after
      # kubeadm init + kubeconfig copy + join-command publication). Waiting for it to
      # equal THIS instance's ID makes the signal per-run — a stale value from a
      # previous run never matches, so a fresh apply blocks until the new bootstrap
      # finishes, and a persistent apply returns immediately.
      for i in $(seq 1 60); do
        BOOTSTRAP_ID=$(aws ssm get-parameter \
          --name "/sdd-k8s-platform/kubeadm-bootstrap-instance-id" \
          --query 'Parameter.Value' --output text 2>/dev/null) || BOOTSTRAP_ID=""
        if [ "$${BOOTSTRAP_ID}" = "$${INSTANCE_ID}" ]; then
          echo "Control plane bootstrap complete (instance-id signal matches $${INSTANCE_ID})"
          break
        fi
        sleep 10
      done
      if [ "$${BOOTSTRAP_ID}" != "$${INSTANCE_ID}" ]; then
        echo "Control plane bootstrap did not complete within timeout" >&2
        exit 1
      fi
      CMD_ID=$(aws ssm send-command \
        --instance-ids "$${INSTANCE_ID}" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"curl -sSL $${FLANNEL_URL} -o /tmp/kube-flannel.yml && sed -i 's|10.244.0.0/16|192.168.0.0/16|g' /tmp/kube-flannel.yml && KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/kube-flannel.yml && KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-flannel rollout restart ds/kube-flannel-ds\"]" \
        --timeout-seconds 300 \
        --comment "Apply Flannel CNI ${local.flannel_version} (003-3)" \
        --query 'Command.CommandId' --output text)
      for i in $(seq 1 60); do
        STATUS=$(aws ssm get-command-invocation \
          --instance-id "$${INSTANCE_ID}" \
          --command-id "$${CMD_ID}" \
          --query 'CommandInvocation.Status || Status' --output text 2>/dev/null) || STATUS="Pending"
        if [ "$${STATUS}" = "Success" ]; then
          echo "Flannel CNI ${local.flannel_version} applied successfully"
          exit 0
        fi
        if [ "$${STATUS}" = "Failed" ] || [ "$${STATUS}" = "TimedOut" ] || [ "$${STATUS}" = "Cancelled" ]; then
          echo "Flannel CNI apply failed with status $${STATUS}" >&2
          exit 1
        fi
        sleep 10
      done
      echo "Flannel CNI apply timed out waiting for invocation" >&2
      exit 1
    EOT
  }
}

# Application infrastructure (004-app-infrastructure) — EBS CSI driver, ebs-gp3 StorageClass,
# NGINX Ingress controller, and the sdd-apps namespace. Applied on the control plane via SSM
# Run Command (same pattern as apply_flannel_cni). Idempotent (kubectl apply); re-triggers only
# when a pinned version changes. The StorageClass manifest is base64-encoded (003-6) to avoid
# JSON-escaping its double-quoted values inside the SSM --parameters value.
resource "null_resource" "apply_app_infrastructure" {
  depends_on = [module.worker_nodes]

  triggers = {
    ebs_csi_ref     = "v1.28.0" # 004-3: driver minor must match cluster K8s minor (1.28)
    ingress_ref     = "controller-v1.15.1"
    git_bootstrap   = "1" # 004-2: re-runs the provisioner to install git on the running control plane
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      # Wait for the control plane's SSM agent to register (same as apply_flannel_cni).
      for i in $(seq 1 30); do
        SSM_ID=$(aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=$${INSTANCE_ID}" \
          --query 'InstanceInformationList[0].InstanceId' --output text 2>/dev/null) || SSM_ID="Pending"
        if [ "$${SSM_ID}" = "$${INSTANCE_ID}" ]; then
          echo "SSM agent registered for $${INSTANCE_ID}"
          break
        fi
        sleep 10
      done
      if [ "$${SSM_ID}" != "$${INSTANCE_ID}" ]; then
        echo "SSM agent did not register for $${INSTANCE_ID} within timeout" >&2
        exit 1
      fi
      # Wait for bootstrap completion (003-11 per-run signal): the bootstrap-instance-id
      # parameter must equal THIS control plane's instance ID.
      for i in $(seq 1 60); do
        BOOTSTRAP_ID=$(aws ssm get-parameter \
          --name "/sdd-k8s-platform/kubeadm-bootstrap-instance-id" \
          --query 'Parameter.Value' --output text 2>/dev/null) || BOOTSTRAP_ID=""
        if [ "$${BOOTSTRAP_ID}" = "$${INSTANCE_ID}" ]; then
          echo "Control plane bootstrap complete (instance-id signal matches $${INSTANCE_ID})"
          break
        fi
        sleep 10
      done
      if [ "$${BOOTSTRAP_ID}" != "$${INSTANCE_ID}" ]; then
        echo "Control plane bootstrap did not complete within timeout" >&2
        exit 1
      fi
      CMD_ID=$(aws ssm send-command \
        --instance-ids "$${INSTANCE_ID}" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[
          \"set -e\",
          \"dnf install -y git\",
          \"KUBECONFIG=/etc/kubernetes/admin.conf kubectl create namespace sdd-apps --dry-run=client -o yaml | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -\",
          \"KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -k 'github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=v1.28.0'\",
          \"echo '${base64encode(file("${path.module}/manifests/ebs-gp3-storageclass.yaml"))}' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -\",
          \"KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/cloud/deploy.yaml\"
        ]" \
        --timeout-seconds 600 \
        --comment "Apply app infrastructure: EBS CSI v1.28.0 + ingress controller-v1.15.1 (004/004-3)" \
        --query 'Command.CommandId' --output text)
      for i in $(seq 1 60); do
        STATUS=$(aws ssm get-command-invocation \
          --instance-id "$${INSTANCE_ID}" \
          --command-id "$${CMD_ID}" \
          --query 'CommandInvocation.Status || Status' --output text 2>/dev/null) || STATUS="Pending"
        if [ "$${STATUS}" = "Success" ]; then
          echo "Application infrastructure applied successfully"
          exit 0
        fi
        if [ "$${STATUS}" = "Failed" ] || [ "$${STATUS}" = "TimedOut" ] || [ "$${STATUS}" = "Cancelled" ]; then
          echo "Application infrastructure apply failed with status $${STATUS}" >&2
          exit 1
        fi
        sleep 10
      done
      echo "Application infrastructure apply timed out waiting for invocation" >&2
      exit 1
    EOT
  }
}

# MySQL StatefulSet (005-mysql-statefulset) — Secret + StatefulSet + Service in sdd-apps.
# Applied on the control plane via SSM Run Command (same pattern as apply_app_infrastructure).
# Secrets come from SSM Parameter Store datasources: the manifest's %%TOKEN%% placeholders
# are replaced with base64encode(param.value), then the whole manifest is base64-encoded
# for the SSM command (003-6 pattern — zero JSON-escaping, passwords never on the command line).
resource "null_resource" "apply_mysql" {
  depends_on = [null_resource.apply_app_infrastructure]

  triggers = {
    mysql_image = "8.0.36"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      # Wait for the control plane's SSM agent to register (same as apply_app_infrastructure).
      for i in $(seq 1 30); do
        SSM_ID=$(aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=$${INSTANCE_ID}" \
          --query 'InstanceInformationList[0].InstanceId' --output text 2>/dev/null) || SSM_ID="Pending"
        if [ "$${SSM_ID}" = "$${INSTANCE_ID}" ]; then
          echo "SSM agent registered for $${INSTANCE_ID}"
          break
        fi
        sleep 10
      done
      if [ "$${SSM_ID}" != "$${INSTANCE_ID}" ]; then
        echo "SSM agent did not register for $${INSTANCE_ID} within timeout" >&2
        exit 1
      fi
      # Wait for bootstrap completion (003-11 per-run signal): the bootstrap-instance-id
      # parameter must equal THIS control plane's instance ID.
      for i in $(seq 1 60); do
        BOOTSTRAP_ID=$(aws ssm get-parameter \
          --name "/sdd-k8s-platform/kubeadm-bootstrap-instance-id" \
          --query 'Parameter.Value' --output text 2>/dev/null) || BOOTSTRAP_ID=""
        if [ "$${BOOTSTRAP_ID}" = "$${INSTANCE_ID}" ]; then
          echo "Control plane bootstrap complete (instance-id signal matches $${INSTANCE_ID})"
          break
        fi
        sleep 10
      done
      if [ "$${BOOTSTRAP_ID}" != "$${INSTANCE_ID}" ]; then
        echo "Control plane bootstrap did not complete within timeout" >&2
        exit 1
      fi
      CMD_ID=$(aws ssm send-command \
        --instance-ids "$${INSTANCE_ID}" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[
          \"echo '${base64encode(replace(replace(file("${path.module}/manifests/mysql.yaml"), "%%MYSQL_ROOT_PASSWORD_B64%%", base64encode(data.aws_ssm_parameter.mysql_root_password.value)), "%%MYSQL_PASSWORD_B64%%", base64encode(data.aws_ssm_parameter.mysql_password.value)))}' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -\"
        ]" \
        --timeout-seconds 600 \
        --comment "Apply MySQL StatefulSet + Secret + Service (005)" \
        --query 'Command.CommandId' --output text)
      for i in $(seq 1 60); do
        STATUS=$(aws ssm get-command-invocation \
          --instance-id "$${INSTANCE_ID}" \
          --command-id "$${CMD_ID}" \
          --query 'CommandInvocation.Status || Status' --output text 2>/dev/null) || STATUS="Pending"
        if [ "$${STATUS}" = "Success" ]; then
          echo "MySQL StatefulSet applied successfully"
          exit 0
        fi
        if [ "$${STATUS}" = "Failed" ] || [ "$${STATUS}" = "TimedOut" ] || [ "$${STATUS}" = "Cancelled" ]; then
          echo "MySQL apply failed with status $${STATUS}" >&2
          exit 1
        fi
        sleep 10
      done
      echo "MySQL apply timed out waiting for invocation" >&2
      exit 1
    EOT
  }
}