# Spec: ECR Pull Secret (in-cluster)

**Feature Branch**: `011-ecr-pull-secret` | **Date**: 2026-09-19 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no new AWS resources; no IAM change)
- **Kubernetes / Cluster Scope**: 1 new K8s `Secret` (`ecr-pull-secret`, type `kubernetes.io/dockerconfigjson`) in `sdd-apps`, created on the control plane via SSM Run Command
- **Target Services / Modules**: new `null_resource.apply_ecr_pull_secret` (dev environment); no existing module touched
- **Security & CI/CD**: no workflow change — the existing `terraform-apply.yml` (push to `main`) applies this spec

> **Why**: kubelet does not use the node's IAM role for image pulls — it authenticates to the registry with a `dockerconfigjson` secret. The node role already carries `AmazonEC2ContainerRegistryReadOnly` (includes `ecr:GetAuthorizationToken`), so the control plane can mint an ECR token and build the secret. This spec makes the cluster **ready to pull** from ECR. The manifest image swap (public baseline → ECR images) is a separate follow-up spec that runs after the first real push from the app repos — swapping now would put the deployments in `ImagePullBackOff` (no images exist yet) and break `demo.vijote.dev`.

### 1.1 Terraform / HCL Resource Contracts

Dev environment `terraform/environments/dev/main.tf` — new null_resource (same SSM pattern as `apply_app_backend`: SSM-agent wait → bootstrap-instance-id gate → send-command → poll):

```hcl
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
```

- `%%ECR_REGISTRY%%` is replaced with the **frontend** repository URL (`<account_id>.dkr.ecr.us-east-1.amazonaws.com/sdd-k8s-platform/frontend`) — the registry host is account-level, so one secret covers both repos.
- `--comment` is 41 chars (under the 100-char SSM cap).
- No `data "aws_caller_identity"` needed — the registry URL comes from the 010 module output.

### 1.2 SSM Script Contract

New `terraform/environments/dev/scripts/create-ecr-pull-secret.sh` (full content):

```bash
#!/usr/bin/env bash
# ECR pull secret (011-ecr-pull-secret) — runs on the control plane via SSM.
# Creates/refreshes the dockerconfigjson secret `ecr-pull-secret` in sdd-apps so
# kubelet can pull from ECR. The ECR token is valid ~12h; re-run to refresh.
set -euo pipefail

REGISTRY="%%ECR_REGISTRY%%" # replaced by Terraform with the 010 ECR repository URL

if [ -z "$REGISTRY" ] || [ "$REGISTRY" = "%%ECR_REGISTRY%%" ]; then
  echo "ERROR: REGISTRY not substituted" >&2
  exit 1
fi

# Mint a fresh ECR token (node role has AmazonEC2ContainerRegistryReadOnly).
PASSWORD=$(aws ecr get-login-password)
if [ -z "$PASSWORD" ]; then
  echo "ERROR: aws ecr get-login-password returned empty" >&2
  exit 1
fi

# Idempotent: delete then create (kubectl apply cannot update dockerconfigjson data).
KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete secret ecr-pull-secret -n sdd-apps --ignore-not-found
KUBECONFIG=/etc/kubernetes/admin.conf kubectl create secret docker-registry ecr-pull-secret \
  -n sdd-apps \
  --docker-server="$REGISTRY" \
  --docker-username=AWS \
  --docker-password="$PASSWORD"

echo "ECR pull secret created in sdd-apps (registry: $REGISTRY)"
```

### 1.3 Kubernetes Manifest Contracts
- No manifest file changes. `app-backend.yaml` / `app-frontend-ingress.yaml` keep `image: nginx:alpine` and gain **no** `imagePullSecrets` in this spec — the swap (image + `imagePullSecrets: [ecr-pull-secret]`) is the follow-up spec, after the first real push.

### 1.4 Data & Storage Contracts
- None (no SSM parameters, no new secrets in Parameter Store).

### 1.5 Network & Security Contracts
- **IAM**: no change. The control plane instance uses the node IAM profile, which already carries `AmazonEC2ContainerRegistryReadOnly` (`cluster-plumbing/main.tf:144-147`) — includes `ecr:GetAuthorizationToken` + `ecr:BatchCheckLayerAvailability`/`ecr:GetDownloadUrlForLayer` needed by the script and by kubelet pulls.
- **Network**: the script calls the ECR API (regional, over NAT egress — same path as the current public image pulls); no SG rules.

## 2. Technical Acceptance Criteria

AC-001/AC-002 run in the existing `terraform-apply.yml`. AC-003 is **user-managed via CLI** (P5/P6).

- [ ] AC-001: `terraform fmt -check -recursive && terraform validate`
- [ ] AC-002: `terraform plan -detailed-exitcode` — plan shows ONLY the new `null_resource.apply_ecr_pull_secret`; zero changes to existing resources
- [ ] AC-003: the secret exists in-cluster with the correct type and registry
  ```bash
  kubectl get secret ecr-pull-secret -n sdd-apps -o jsonpath='{.type}'
  # -> kubernetes.io/dockerconfigjson
  kubectl get secret ecr-pull-secret -n sdd-apps -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | python3 -m json.tool
  # -> .auths key = <account_id>.dkr.ecr.us-east-1.amazonaws.com/sdd-k8s-platform/frontend, username "AWS"
  ```

## 3. Assumptions & Technical Constraints

- **Token staleness**: the ECR token is valid ~12h. The secret is (re)created on every apply of this resource (trigger: ECR repo URL + control-plane instance ID). If the cluster sits idle >12h, refresh by re-running the script (one SSM command) or re-applying.
- **One secret, both repos**: the registry host is account-level; the single `ecr-pull-secret` covers `sdd-k8s-platform/frontend` and `sdd-k8s-platform/backend`.
- **Pull-path proof deferred**: a real pull test (pod pulling an ECR image) is impossible until the first image is pushed — it is verified in the follow-up manifest-swap spec.
- **Downstream consumers**: the follow-up manifest-swap spec (012) adds `imagePullSecrets: [ecr-pull-secret]` + ECR image refs to the two app manifests.
- **External prerequisites**: none (no manual AWS resources, no SSM parameters, no GitHub vars).
- **Testing Policy**: no unit or E2E test generation — validation performed directly against AWS/K8s using CLI tools; all testing is user-managed.
