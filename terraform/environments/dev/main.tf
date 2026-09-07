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
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      FLANNEL_URL="${local.flannel_manifest_url}"
      # Clear any stale join-command parameter from a previous run so its presence
      # is a reliable per-run "bootstrap complete" signal (deleted here, re-created
      # by the control plane bootstrap at its end after kubeadm init).
      aws ssm delete-parameter \
        --name "/sdd-k8s-platform/kubeadm-join-command" 2>/dev/null || true
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
      # Wait for bootstrap completion: the join-command parameter is published by
      # the control plane bootstrap as its LAST step (after kubeadm init + kubeconfig
      # copy). It was deleted above, so its presence means THIS run's bootstrap
      # finished and kubectl + the API server are ready for `kubectl apply`.
      for i in $(seq 1 60); do
        JOIN_PRESENT=$(aws ssm get-parameter \
          --name "/sdd-k8s-platform/kubeadm-join-command" \
          --with-decryption \
          --query 'Parameter.Value' --output text 2>/dev/null) || JOIN_PRESENT=""
        if [ -n "$${JOIN_PRESENT}" ]; then
          echo "Control plane bootstrap complete (join command published)"
          break
        fi
        sleep 10
      done
      if [ -z "$${JOIN_PRESENT}" ]; then
        echo "Control plane bootstrap did not complete within timeout" >&2
        exit 1
      fi
      CMD_ID=$(aws ssm send-command \
        --instance-ids "$${INSTANCE_ID}" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"curl -sSL $${FLANNEL_URL} -o /tmp/kube-flannel.yml\",\"kubectl apply -f /tmp/kube-flannel.yml\"]" \
        --timeout-seconds 300 \
        --comment "Apply Flannel CNI ${local.flannel_version} (003-3)" \
        --query 'Command.CommandId' --output text)
      for i in $(seq 1 60); do
        STATUS=$(aws ssm get-command-invocation \
          --instance-id "$${INSTANCE_ID}" \
          --command-id "$${CMD_ID}" \
          --query 'CommandInvocation.Status' --output text 2>/dev/null) || STATUS="Pending"
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