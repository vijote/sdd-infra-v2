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

# ECR repositories (010-ecr-repositories) — registry for the frontend/backend app images.
# Leaf module: no cluster dependency, nothing depends on it. Push role lives in the app
# repos; the in-cluster pull secret is spec 011.
module "ecr" {
  source = "../../modules/ecr"

  repository_names = [
    "sdd-k8s-platform/frontend",
    "sdd-k8s-platform/backend",
  ]
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
    instance_id     = module.control_plane.control_plane_instance_id # 004-10: re-apply on cluster recreation
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
    ebs_csi_ref   = "v1.28.0" # 004-3: driver minor must match cluster K8s minor (1.28)
    ingress_ref   = "controller-v1.15.1"
    git_bootstrap = "1"                                            # 004-2: re-runs the provisioner to install git on the running control plane
    instance_id   = module.control_plane.control_plane_instance_id # 004-10: re-apply on cluster recreation
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

# cert-manager + ClusterIssuers (004-1-cert-manager) — cert-manager namespace.
# Applied on the control plane via SSM Run Command (same pattern as apply_app_infrastructure).
# (1) applies the upstream static manifest (controller + webhook + cainjector + CRDs),
# (2) applies the base64-encoded ClusterIssuers manifest (selfsigned + letsencrypt-prod).
# depends_on apply_app_infrastructure: the letsencrypt-prod HTTP-01 solver needs the
# ingress controller (installed there). The ALB (CCM) is only needed at issuance time (005).
resource "null_resource" "apply_cert_manager" {
  depends_on = [null_resource.apply_app_infrastructure]

  triggers = {
    cert_manager_ref = "v1.19.4+webhook-gate+issuer-retry+issuer-email" # 004-13: v1.20+ CRDs need K8s 1.30+; 004-14: gate issuers on webhook rollout; 004-15: retry ClusterIssuer apply (webhook startup race); 004-16: real ACME contact email (LE rejects example.com)
    instance_id      = module.control_plane.control_plane_instance_id   # 004-10: re-apply on cluster recreation
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
          \"KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.4/cert-manager.yaml && KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=300s && KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=300s\",
          \"for i in 1 2 3 4 5 6 7 8 9 10; do if echo '${base64encode(file("${path.module}/manifests/cert-manager-issuers.yaml"))}' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -; then echo 'ClusterIssuers applied successfully'; exit 0; fi; echo 'ClusterIssuer apply failed, retrying in 5s' >&2; sleep 5; done; echo 'ClusterIssuer apply failed after 10 attempts' >&2; exit 1\"
        ]" \
        --timeout-seconds 600 \
        --comment "Deploy cert-manager v1.19.4 + webhook gate + ClusterIssuers + retry (004-1/004-13/004-14/004-15)" \
        --query 'Command.CommandId' --output text)
      for i in $(seq 1 60); do
        STATUS=$(aws ssm get-command-invocation \
          --instance-id "$${INSTANCE_ID}" \
          --command-id "$${CMD_ID}" \
          --query 'CommandInvocation.Status || Status' --output text 2>/dev/null) || STATUS="Pending"
        if [ "$${STATUS}" = "Success" ]; then
          echo "cert-manager + ClusterIssuers applied successfully"
          exit 0
        fi
        if [ "$${STATUS}" = "Failed" ] || [ "$${STATUS}" = "TimedOut" ] || [ "$${STATUS}" = "Cancelled" ]; then
          echo "cert-manager apply failed with status $${STATUS}" >&2
          exit 1
        fi
        sleep 10
      done
      echo "cert-manager apply timed out waiting for invocation" >&2
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
    instance_id = module.control_plane.control_plane_instance_id # 004-10: re-apply on cluster recreation
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

# Application backend scaffold (006-app-backend) — Deployment + Service in sdd-apps.
# Applied on the control plane via SSM Run Command (same pattern as apply_mysql).
# 012-ecr-image-deploy: the manifest's %%BACKEND_IMAGE%% / %%BACKEND_PULL_SECRET%%
# placeholders are substituted before base64 (locals above). When a tag is set, the
# SSM command first refreshes ecr-pull-secret with a fresh ECR token (12h expiry,
# refresh-on-deploy), then applies the manifest and waits for the rollout.
resource "null_resource" "apply_app_backend" {
  depends_on = [null_resource.apply_mysql]

  triggers = {
    backend_image = local.backend_image                            # 012: re-apply on image tag change
    instance_id   = module.control_plane.control_plane_instance_id # 004-10: re-apply on cluster recreation
    manifest_rev  = "012-5-probe-path"                             # 012-5: tag-conditional probe path (/, /healthz)
    migrate_rev   = "015-4-password-escape-fix"                    # 015-4: payload -p"$VAR" escape fix
    probe_rev     = "015-readyz"                                   # 015: split probes (liveness /healthz, readiness /readyz)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      # Wait for the control plane's SSM agent to register (same as apply_mysql).
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
          \"echo '${base64encode(replace(file("${path.module}/scripts/create-ecr-pull-secret.sh"), "%%ECR_REGISTRY%%", module.ecr.repository_urls["sdd-k8s-platform/frontend"]))}' | base64 -d | bash && if [ '${local.backend_migrate_enabled}' = 'true' ]; then echo '${base64encode("mysql -uroot -p\"$MYSQL_ROOT_PASSWORD\" <<'SQL'\nCREATE DATABASE IF NOT EXISTS sdd_backend;\nGRANT ALL PRIVILEGES ON sdd_backend.* TO 'sdd_app'@'%';\nFLUSH PRIVILEGES;\nSQL")}' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl exec -i mysql-0 -n sdd-apps -- bash -s && echo '${base64encode(replace(file("${path.module}/manifests/backend-db-migrate.yaml"), "%%MIGRATE_IMAGE%%", local.backend_image))}' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f - && KUBECONFIG=/etc/kubernetes/admin.conf kubectl wait --for=condition=complete job/backend-db-migrate -n sdd-apps --timeout=300s; fi && echo '${base64encode(replace(replace(replace(replace(replace(file("${path.module}/manifests/app-backend.yaml"), "%%BACKEND_IMAGE%%", local.backend_image), "%%BACKEND_PULL_SECRET%%", local.backend_pull_secret), "%%BACKEND_PORT%%", local.backend_port), "%%BACKEND_LIVENESS_PATH%%", local.backend_liveness_path), "%%BACKEND_READINESS_PATH%%", local.backend_readiness_path))}' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f - && KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s\"
        ]" \
        --timeout-seconds 600 \
        --comment "Apply app-backend Deployment + Service (006/012)" \
        --query 'Command.CommandId' --output text)
      for i in $(seq 1 60); do
        STATUS=$(aws ssm get-command-invocation \
          --instance-id "$${INSTANCE_ID}" \
          --command-id "$${CMD_ID}" \
          --query 'CommandInvocation.Status || Status' --output text 2>/dev/null) || STATUS="Pending"
        if [ "$${STATUS}" = "Success" ]; then
          echo "App backend applied successfully"
          exit 0
        fi
        if [ "$${STATUS}" = "Failed" ] || [ "$${STATUS}" = "TimedOut" ] || [ "$${STATUS}" = "Cancelled" ]; then
          echo "App backend apply failed with status $${STATUS}" >&2
          exit 1
        fi
        sleep 10
      done
      echo "App backend apply timed out waiting for invocation" >&2
      exit 1
    EOT
  }
}

# Application frontend + Ingress (007-app-frontend-ingress) — Deployment + Service +
# Ingress in sdd-apps. Applied on the control plane via SSM Run Command (same pattern
# as apply_app_backend). The manifest's %%INGRESS_HOST%% token is replaced with
# var.ingress_host before base64 (005 replace pattern, applied to a non-secret).
# 012-ecr-image-deploy: %%FRONTEND_IMAGE%% / %%FRONTEND_PULL_SECRET%% are substituted
# before base64 (locals above). When a tag is set, the SSM command first refreshes
# ecr-pull-secret with a fresh ECR token, then applies and waits for the rollout.
resource "null_resource" "apply_app_frontend_ingress" {
  # 009: the Ingress now carries a tls block + a cert-manager Certificate (letsencrypt-prod
  # HTTP-01). It needs the issuers to exist (apply_cert_manager). It does NOT depend on
  # apply_cloudflare_record — that would be a cycle (cloudflare_record -> apply_aws_ccm -> this
  # resource). The Certificate stays in "Issuing" until DNS is live; cert-manager retries
  # HTTP-01 automatically, so it self-heals once the CNAME record propagates.
  depends_on = [null_resource.apply_app_backend, null_resource.apply_cert_manager]

  triggers = {
    frontend_image = local.frontend_image # 012: re-apply on image tag change
    ingress_host   = var.ingress_host
    instance_id    = module.control_plane.control_plane_instance_id # 004-10: re-apply on cluster recreation
    manifest_rev   = "012-6-annotation-placement"                   # 012-6: annotations in metadata (strict decoding fix)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      # Wait for the control plane's SSM agent to register (same as apply_app_backend).
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
          \"KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s && echo '${base64encode(replace(replace(replace(file("${path.module}/manifests/app-frontend-ingress.yaml"), "%%INGRESS_HOST%%", var.ingress_host), "%%FRONTEND_IMAGE%%", local.frontend_image), "%%FRONTEND_PULL_SECRET%%", local.frontend_pull_secret))}' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f - && KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/app-frontend -n sdd-apps --timeout=180s\"
        ]" \
        --timeout-seconds 600 \
        --comment "Apply app-frontend Deployment + Service + Ingress (007/012)" \
        --query 'Command.CommandId' --output text)
      for i in $(seq 1 60); do
        STATUS=$(aws ssm get-command-invocation \
          --instance-id "$${INSTANCE_ID}" \
          --command-id "$${CMD_ID}" \
          --query 'CommandInvocation.Status || Status' --output text 2>/dev/null) || STATUS="Pending"
        if [ "$${STATUS}" = "Success" ]; then
          echo "App frontend + ingress applied successfully"
          exit 0
        fi
        if [ "$${STATUS}" = "Failed" ] || [ "$${STATUS}" = "TimedOut" ] || [ "$${STATUS}" = "Cancelled" ]; then
          echo "App frontend + ingress apply failed with status $${STATUS}" >&2
          exit 1
        fi
        sleep 10
      done
      echo "App frontend + ingress apply timed out waiting for invocation" >&2
      exit 1
    EOT
  }
}

# ECR pull secret (011-ecr-pull-secret) — dockerconfigjson in sdd-apps so kubelet can
# pull from ECR (kubelet does NOT use the node IAM role for image pulls). The script
# mints a fresh ECR token on the control plane (node role has
# AmazonEC2ContainerRegistryReadOnly -> ecr:GetAuthorizationToken). The ECR token is
# valid ~12h: re-apply (or re-run the script) to refresh.
locals {
  # 012-ecr-image-deploy: empty tag -> public baseline image, no imagePullSecrets;
  # non-empty tag -> ECR image + ecr-pull-secret block (injected into the manifests
  # via single-occurrence %%...%% placeholders, 014 gotcha).
  backend_image        = var.backend_image_tag == "" ? "nginx:alpine" : "${module.ecr.repository_urls["sdd-k8s-platform/backend"]}:${var.backend_image_tag}"
  frontend_image       = var.frontend_image_tag == "" ? "nginx:alpine" : "${module.ecr.repository_urls["sdd-k8s-platform/frontend"]}:${var.frontend_image_tag}"
  backend_pull_secret  = var.backend_image_tag == "" ? "" : "      imagePullSecrets:\n        - name: ecr-pull-secret"
  frontend_pull_secret = var.frontend_image_tag == "" ? "" : "      imagePullSecrets:\n        - name: ecr-pull-secret"
  # 012-4: port is tag-conditional — nginx baseline listens on 80, the Go app on 8080
  backend_port = var.backend_image_tag == "" ? "80" : "8080"
  # 012-5: probe path is tag-conditional — nginx baseline serves /, the Go app
  # exposes /healthz (012-5 contract: backend must implement GET /healthz -> 200)
  backend_probe_path = var.backend_image_tag == "" ? "/" : "/healthz"
  # 015: split probes — liveness /healthz (no DB), readiness /readyz (DB ping,
  # 503 removes pod from endpoints); nginx baseline keeps / for both.
  backend_liveness_path  = var.backend_image_tag == "" ? "/" : "/healthz"
  backend_readiness_path = var.backend_image_tag == "" ? "/" : "/readyz"
  # 015: migrate Job + DB bootstrap only apply when the real Go app is deployed
  # (nginx:alpine baseline has no migrate entrypoint arg and no DB dependency).
  backend_migrate_enabled = var.backend_image_tag != ""
}

# ECR pull secret (011-ecr-pull-secret) — dockerconfigjson in sdd-apps so kubelet can
# pull from ECR (kubelet does NOT use the node IAM role for image pulls). The script
# mints a fresh ECR token on the control plane (node role has
# AmazonEC2ContainerRegistryReadOnly -> ecr:GetAuthorizationToken). The ECR token is
# valid ~12h: re-apply (or re-run the script) to refresh.
resource "null_resource" "apply_ecr_pull_secret" {
  depends_on = [null_resource.apply_app_infrastructure] # creates the sdd-apps namespace (004)

  triggers = {
    ecr_repo_url = module.ecr.repository_urls["sdd-k8s-platform/frontend"] # 010
    instance_id  = module.control_plane.control_plane_instance_id          # 004-10: re-apply on cluster recreation
    script_rev   = "012-2-server-fix"                                      # 012-2: bare-registry-host docker-server fix
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      # Wait for the control plane's SSM agent to register (same as apply_app_backend).
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
        echo "SSM agent did not register for $${INSTANCE_ID}" >&2
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
          \"echo '${base64encode(replace(file("${path.module}/scripts/create-ecr-pull-secret.sh"), "%%ECR_REGISTRY%%", module.ecr.repository_urls["sdd-k8s-platform/frontend"]))}' | base64 -d | bash\"
        ]" \
        --timeout-seconds 600 \
        --comment "Create ECR pull secret in sdd-apps (011)" \
        --query 'Command.CommandId' --output text)
      for i in $(seq 1 60); do
        STATUS=$(aws ssm get-command-invocation \
          --instance-id "$${INSTANCE_ID}" \
          --command-id "$${CMD_ID}" \
          --query 'CommandInvocation.Status || Status' --output text 2>/dev/null) || STATUS="Pending"
        if [ "$${STATUS}" = "Success" ]; then
          echo "ECR pull secret created successfully"
          exit 0
        fi
        if [ "$${STATUS}" = "Failed" ] || [ "$${STATUS}" = "TimedOut" ] || [ "$${STATUS}" = "Cancelled" ]; then
          echo "ECR pull secret creation failed with status $${STATUS}" >&2
          exit 1
        fi
        sleep 10
      done
      echo "ECR pull secret creation timed out waiting for invocation" >&2
      exit 1
    EOT
  }
}

# AWS Cloud Controller Manager (004-4-aws-cloud-controller-manager) — kube-system.
# kubeadm does NOT install the CCM; without it, LoadBalancer Services stay <pending>
# (no ELB is created). Applied on the control plane via SSM Run Command (same pattern
# as apply_app_frontend_ingress). The command: (1) annotates the EXISTING
# ingress-nginx-controller Service with the PUBLIC subnet IDs (forces an
# internet-facing ELB — all nodes are in private subnets), (2) applies the CCM
# manifest, (3) waits for the CCM rollout. Annotate-first avoids a race where the
# CCM creates the ELB in the private node subnets before the annotation is present.
# 004-11: set spec.providerID (aws:///<az>/<id>) on every node BEFORE the CCM
# starts, or the CCM cannot map nodes to EC2 instances and never registers ELB
# targets (log: "node has no providerID" -> ELB Instances: [] -> curl 000).
# Idempotent in-place repair: the bootstrap scripts (004-11) set providerID at
# init/join time for future recreations; this patches the CURRENT cluster's
# nodes without a terraform destroy.
resource "null_resource" "set_node_provider_ids" {
  depends_on = [null_resource.apply_app_frontend_ingress]

  triggers = {
    provider_id_ref = "1"
    instance_id     = module.control_plane.control_plane_instance_id # 004-10: re-run on cluster recreation
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      # Wait for the control plane's SSM agent to register (same as apply_aws_ccm).
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
      # Wait for bootstrap completion (003-11 per-run signal).
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
          \"echo '${base64encode(file("${path.module}/scripts/set-node-provider-ids.sh"))}' | base64 -d | bash\"
        ]" \
        --timeout-seconds 300 \
        --comment "Set node spec.providerID for CCM ELB target registration (004-11)" \
        --query 'Command.CommandId' --output text)
      for i in $(seq 1 30); do
        STATUS=$(aws ssm get-command-invocation \
          --instance-id "$${INSTANCE_ID}" \
          --command-id "$${CMD_ID}" \
          --query 'CommandInvocation.Status || Status' --output text 2>/dev/null) || STATUS="Pending"
        if [ "$${STATUS}" = "Success" ]; then
          echo "Node providerIDs set successfully"
          exit 0
        fi
        if [ "$${STATUS}" = "Failed" ] || [ "$${STATUS}" = "TimedOut" ] || [ "$${STATUS}" = "Cancelled" ]; then
          echo "Node providerID repair failed with status $${STATUS}" >&2
          exit 1
        fi
        sleep 10
      done
      echo "Node providerID repair timed out waiting for invocation" >&2
      exit 1
    EOT
  }
}

resource "null_resource" "apply_aws_ccm" {
  # module.vpc: the VPC must carry the kubernetes.io/cluster/sdd-k8s-platform=owned
  # tag (added in 004-4) BEFORE the CCM starts, or the CCM fails to init with
  # "AWS cloud failed to find ClusterID".
  # set_node_provider_ids: nodes must have spec.providerID BEFORE the CCM starts,
  # or it cannot register ELB targets (004-11).
  depends_on = [null_resource.apply_app_frontend_ingress, null_resource.set_node_provider_ids, module.vpc]

  triggers = {
    ccm_version   = "eks-distro-v1.28.11-eks-1-28-64+vpctag"
    ccm_log_level = "4"
    instance_id   = module.control_plane.control_plane_instance_id # 004-10: re-apply on cluster recreation
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      # Wait for the control plane's SSM agent to register (same as apply_app_frontend_ingress).
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
          \"KUBECONFIG=/etc/kubernetes/admin.conf kubectl annotate svc ingress-nginx-controller -n ingress-nginx service.beta.kubernetes.io/aws-load-balancer-subnets='${join(",", module.vpc.public_subnet_ids)}' --overwrite && echo '${base64encode(file("${path.module}/manifests/aws-ccm.yaml"))}' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f - && KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout restart deployment/aws-cloud-controller-manager -n kube-system && sleep 30 && (KUBECONFIG=/etc/kubernetes/admin.conf kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200 --previous || KUBECONFIG=/etc/kubernetes/admin.conf kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200)\"
        ]" \
        --timeout-seconds 600 \
        --comment "Deploy AWS CCM + annotate ingress Service with public subnets (004-4)" \
        --query 'Command.CommandId' --output text)
      for i in $(seq 1 60); do
        STATUS=$(aws ssm get-command-invocation \
          --instance-id "$${INSTANCE_ID}" \
          --command-id "$${CMD_ID}" \
          --query 'CommandInvocation.Status || Status' --output text 2>/dev/null) || STATUS="Pending"
        if [ "$${STATUS}" = "Success" ]; then
          echo "AWS CCM deployed successfully"
          exit 0
        fi
        if [ "$${STATUS}" = "Failed" ] || [ "$${STATUS}" = "TimedOut" ] || [ "$${STATUS}" = "Cancelled" ]; then
          echo "AWS CCM deploy failed with status $${STATUS}" >&2
          exit 1
        fi
        sleep 10
      done
      echo "AWS CCM deploy timed out waiting for invocation" >&2
      exit 1
    EOT
  }
}

# Cloudflare CNAME record (009-2-cloudflare-dns-record) — demo.vijote.dev -> the CCM-created ALB.
# The ALB is out of Terraform state (CCM-created), so the record is created via SSM on
# the control plane AFTER the CCM has produced the ALB. 009-2: vijote.dev is authoritative
# at Cloudflare (not Route 53), so the record is a CNAME created via the Cloudflare API;
# the token is read from SSM on the control plane (node_ssm_parameters covers the path).
# Idempotent (GET then PUT/POST).
resource "null_resource" "apply_cloudflare_record" {
  depends_on = [null_resource.apply_aws_ccm, module.cluster_plumbing]

  triggers = {
    domain      = var.ingress_host
    instance_id = module.control_plane.control_plane_instance_id # 004-10: re-apply on cluster recreation
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      # Wait for the control plane's SSM agent to register (same as apply_aws_ccm).
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
      # Wait for bootstrap completion (003-11 per-run signal).
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
          \"echo '${base64encode(file("${path.module}/scripts/create-cloudflare-record.sh"))}' | base64 -d | bash\"
        ]" \
        --timeout-seconds 600 \
        --comment "Create Cloudflare CNAME record for demo.vijote.dev (009-2)" \
        --query 'Command.CommandId' --output text)
      for i in $(seq 1 60); do
        STATUS=$(aws ssm get-command-invocation \
          --instance-id "$${INSTANCE_ID}" \
          --command-id "$${CMD_ID}" \
          --query 'CommandInvocation.Status || Status' --output text 2>/dev/null) || STATUS="Pending"
        if [ "$${STATUS}" = "Success" ]; then
          echo "Cloudflare CNAME record created successfully"
          exit 0
        fi
        if [ "$${STATUS}" = "Failed" ] || [ "$${STATUS}" = "TimedOut" ] || [ "$${STATUS}" = "Cancelled" ]; then
          echo "Cloudflare CNAME record creation failed with status $${STATUS}" >&2
          exit 1
        fi
        sleep 10
      done
      echo "Cloudflare CNAME record creation timed out waiting for invocation" >&2
      exit 1
    EOT
  }
}