# AGENTS.md

## Project Overview
Spec-driven infrastructure monorepo using SpecKit methodology. Infrastructure code is generated from specifications, not traditional source files. Uses Terraform, AWS, Kubernetes, and GitHub Actions with OIDC authentication.

## Agent Behavior Rules

### Bias Towards Action and Simplicity
Do not fall into long, iterative thinking loops or self-doubt. Avoid over-complicating tasks or debating multiple complex alternatives in your thoughts (e.g., going back and forth with "Wait...", "Actually...", "Alternative...").

If you find yourself:
1. Re-evaluating the same decision multiple times.
2. Trying to script or execute a highly complex workaround for a simple goal.
3. Second-guessing the simplest interpretation of the user's prompt.

**Stop immediately.** Do not proceed with a convoluted plan. Instead, pick the most straightforward and simple approach. If no simple approach is clear, ask the user for direction. It is always better to pause and ask the user than to waste time and tokens agonizing over the "perfect" solution.

## Critical Setup Requirements
- **CloudFormation first**: Must deploy `cloudformation/bootstrap-role.yaml` and `cloudformation/assume-role.yaml` before any Terraform workflows
- **No src/ directory**: Infrastructure code is generated from specs, not traditional source files
- **Role chaining**: Two-tier security model (bootstrap → assume roles) with 1-hour sessions

## Build, Test, and Lint Commands

### Terraform
```bash
terraform fmt -check -recursive  # Format validation
terraform init                    # Initialize backend
terraform validate                # Syntax validation
terraform plan -out=tfplan        # Generate execution plan
terraform apply -auto-approve     # Apply changes
terraform output -json            # Extract outputs
```

### Kubernetes
```bash
kubectl get nodes -o wide
kubectl rollout status deployment/<name>
kubectl wait --for=condition=Ready
```

### Helm
```bash
helm lint <chart-path>
helm template <release> <chart-path>
```

### Custom Validation
- Run `specs/*/validate.sh` scripts for post-deployment validation
- Scripts use `set -euo pipefail` for robust error handling
- Exit codes indicate success/failure for CI/CD integration

## Required Environment Variables

### GitHub Repository Variables
- `AWS_BOOTSTRAP_ROLE_ARN` - Bootstrap role for OIDC authentication
- `AWS_TERRAFORM_ROLE` - Infrastructure deployment role (assumed via role chaining from bootstrap)
- `AWS_REGION` - Target AWS region (default: us-east-1)
- `TF_VAR_state_bucket_name` - Terraform S3 state bucket name

### GitHub Secrets
- `MYSQL_ROOT_PASSWORD` - Database root password
- `MYSQL_PASSWORD` - Application database password

### Terraform Variables
- `TF_VAR_region` - AWS region
- `TF_VAR_github_owner` - Repository owner
- `TF_VAR_github_repo` - Repository name
- `TF_VAR_mysql_root_password` - MySQL root password
- `TF_VAR_mysql_password` - MySQL user password

## SpecKit Workflow Constraints
- **Spec size limit**: Must be under 200 lines for token efficiency
- **Task limit**: Maximum 31 tasks per feature (micro-DAG)
- **No tests allowed**: Direct AWS validation only, no unit/integration tests
- **Zero narrative policy**: Strict technical content only, no conversational filler
- **Session isolation**: Minimal context loading for LLM agents (constitution + single task)

## Automation Policies
- **No manual approvals**: Fully automated deployments on main branch push
- **Machine-verifiable criteria**: All acceptance criteria must be executable in CI/CD
- **Sequential numbering**: Features numbered 000-*, 001-*, etc.
- **Spec-driven cycle**: specify → plan → tasks → implement

## Spec File Conventions
- **Standard files**: spec.md, checklists/requirements.md (required); plan.md, tasks.md, README.md, validate.sh (optional)
- **Acceptance Criteria**: Use `AC-###` format with executable CLI commands
- **Checklist Items**: Use `CHK###` format
- **Tasks**: Use `T###` format with stage grouping
- **Metadata**: Feature branch names match spec folder names, dates in ISO format (YYYY-MM-DD)

## Infrastructure Patterns
- **Security**: OIDC authentication, role chaining, least privilege IAM policies
- **State Management**: S3 backend with DynamoDB locking, object lock configuration
- **Network**: VPC design with 10.0.0.0/16 CIDR, multi-AZ deployment
- **Modular Design**: Separate modules for networking, state backend, Kubernetes, application infrastructure

## Operational Notes
- **Terraform version**: >=1.5.0 required
- **State bucket**: `sdd-k8s-platform-terraform-state` (hardcoded in workflows)
- **Validation scripts**: Automatically run after deployment for phases 001-005
- **No network tests**: Skip nslookup checks per constitution
- **Single environment**: Dev environment only, no multi-environment setup

## Code Style Rules
- **Terraform**: Follow HCL standards, use `terraform fmt -check -recursive` for validation
- **Spec files**: Machine-verifiable acceptance criteria with exact commands
- **Infrastructure contracts**: Explicit Terraform variable definitions with types and defaults
- **Security groups**: Specific CIDRs and ports clearly defined

## Repo Etiquette
- **Branch naming**: Match spec folder names (e.g., `000-5-github-vars-aws-roles`, `001-vpc-foundation`)
- **Commit style**: Add `Co-Authored-By: CODA <coda@globant.com>` trailer as last line
- **PR conventions**: Add "Made with CODA" signature at end of PR description
- **Tagging**: Consistent `Purpose` and `ManagedBy` tags on resources

## AI Agent Guidelines
- **Project constitution**: @.specify/memory/constitution.md serves as primary AI guidelines
- **Coda skills**: 10 specialized skills in `.coda/skills/` for spec-driven development
- **SpecKit integration**: Full framework in `.specify/` with template-driven generation
- **Context loading**: Minimal context (constitution + single task) for LLM agents

## Non-Obvious Gotchas
- **No traditional package manager**: Infrastructure dependencies managed via Terraform modules
- **No traditional formatters**: Only Terraform formatting enforced
- **Spec-driven development**: Code is generated from specifications, not written directly
- **Phase dependencies**: Earlier phases provide outputs consumed by later phases
- **Cross-spec references**: Specs reference outputs from previous phases

## Spec Map (all specs Implemented; dates 2026-09)
One-glance index of every spec under `specs/`, grouped by phase. Active spec tracked in `.specify/feature.json`.

### 000 — CI/CD & CloudFormation bootstrap
- `000-0-cicd-workflows` (09-01): Terraform apply GH Actions workflow — OIDC, phase detection via plan JSON, job dependencies.
- `000-5-github-vars-aws-roles` (09-01): GitHub repo variables + two-tier AWS role chaining via CloudFormation.
- `000-6-terraform-workflow-fix` (09-02): Fix apply workflow plan step — binary plan file + JSON output parsing.
- `000-7-github-actions-role-chaining` (09-02): Native AWS role chaining via configure-aws-credentials@v4 in all workflows.
- `000-8-cloudformation-circular-dependency-fix` (09-02): Split CFN stack into two sequential stacks to break role circular dependency.

### 001 — Terraform state backend
- `001-state-backend` (09-01): S3 state backend — versioning, SSE, public access block, bucket policy.
- `001-1-ci-workflow-bootstrap` (09-02): Bootstrap apply workflow with repo variables + 2-step AWS credentials.
- `001-2-sts-tagsession-role` (09-02): Add sts:TagSession to assume role trust policy for session tags.
- `001-3-remove-trust-condition` (09-02): Remove ExternalId/PrincipalArn conditions blocking role chaining.
- `001-4-remove-tags-property` (09-02): Remove unsupported tags property from terraform-backend module call.
- `001-5-backend-config-cli` (09-02): Move S3 backend config to -backend-config CLI args (vars disallowed in backend block).
- `001-6-existing-bucket-data-source` (09-02): Replace aws_s3_bucket with data source for pre-existing state bucket.

### 002 — VPC
- `002-vpc-foundation` (09-01): VPC with public/private subnets across 3 AZs, IGW, NAT, route tables.
- `002-0-terraform-destroy-fix` (09-05): Mirror destroy workflow on working apply workflow (dev dir, backend config, role chain).

### 003 — Kubernetes cluster (kubeadm on EC2)
- `003-0-assume-role-iam-permissions` (09-05): Wildcard iam:* (TerraformIamAccess) on assume role; PowerUserAccess excludes iam:*.
- `003-0-imds-v2-private-ip-fix` (09-05): Fetch private IP via IMDSv2 token; fix KubeletConfiguration apiVersion.
- `003-0-kubeadm-preflight-sysctl-fix` (09-05): Load br_netfilter, persist ip_forward/bridge-nf-call-iptables sysctls.
- `003-0-kubeadm-repo-gpg-fix` (09-05): Explicit kubernetes.repo with gpgcheck=1 + gpgkey (dnf config-manager omits gpgkey).
- `003-0-node-role-ssm-permissions` (09-05): Scoped ssm:Get/PutParameter on /sdd-k8s-platform/* for join command.
- `003-0-worker-output-splat-fix` (09-06): Sorted for expression instead of invalid splat on for_each map.
- `003-1-cluster-plumbing` (09-05): Cluster security groups (control plane + worker) and node IAM role/profile.
- `003-2-control-plane` (09-05): Control plane EC2 — containerd + kubeadm v1.28.0, kubeadm init, join command to SSM.
- `003-3-worker-nodes` (09-05): Two workers join via SSM join command; Flannel CNI applied → 3-node cluster.
- `003-4-flannel-ssm-readiness-wait-fix` (09-06): SSM agent registration wait before send-command (InvalidInstanceId).
- `003-5-flannel-local-exec-bash-fix` (09-06): interpreter = ["/bin/bash", "-c"] so pipefail works on dash /bin/sh.
- `003-6-flannel-ssm-params-json-fix` (09-06): Fix over-escaped quotes in send-command --parameters JSON.
- `003-7-flannel-wait-bootstrap-complete` (09-06): Gate Flannel on join-command parameter (bootstrap-complete signal).
- `003-8-flannel-join-param-delete-removal` (09-06): Remove param delete — control plane persistent, never re-publishes.
- `003-9-flannel-ssm-kubeconfig-fix` (09-09): Prefix kubectl with KUBECONFIG=/etc/kubernetes/admin.conf in SSM.
- `003-10-flannel-ssm-poll-query-fix` (09-09): Correct status-poll JMESPath to flat Status key of get-command-invocation.
- `003-11-flannel-per-run-bootstrap-signal` (09-09): Per-run bootstrap signal (CP instance ID in SSM) — no stale join command.
- `003-12-flannel-cidr-mismatch` (09-10): Sed Flannel manifest CIDR to kubeadm podSubnet 192.168.0.0/16.
- `003-13-imds-token-expiry` (09-11): Move instance-id IMDS fetch to top of bootstrap while token fresh.
- `003-14-flannel-vxlan-sg` (09-12): Flannel VXLAN UDP 8472 + API TCP 4240 ingress from VPC CIDR on both SGs.

### 004 — App infrastructure (CSI, CCM, cert-manager)
- `004-app-infrastructure` (09-09): EBS CSI driver + ebs-gp3 StorageClass, ingress-nginx, sdd-apps namespace.
- `004-1-cert-manager` (09-09): cert-manager with selfsigned + letsencrypt-prod (HTTP-01) ClusterIssuers.
- `004-2-ebs-csi-git-missing` (09-10): Install git on control plane for kustomize fetch; set -e in SSM steps.
- `004-3-ebs-csi-k8s-version-skew` (09-12): Pin EBS CSI to v1.28.0 (CSIDriver manifest rejected by K8s 1.28).
- `004-4-aws-cloud-controller-manager` (09-12): CCM v1.28.x + node-role ELB/EC2 IAM + public-subnet annotation.
- `004-5-ccm-clusterid-diagnostic` (09-13): --v=4 CCM logging to diagnose ClusterID init failure.
- `004-6-ccm-instance-cluster-tag` (09-13): kubernetes.io/cluster/<name>=owned tag on EC2 instances for ClusterID().
- `004-7-ccm-create-security-group` (09-14): Full EC2 SG lifecycle actions in node CCM policy for ELB SG.
- `004-8-ccm-elb-wildcard` (09-14): elasticloadbalancing:* wildcard to end per-action 403 whack-a-mole.
- `004-9-ccm-liveness-probe-scheme` (09-14): scheme: HTTPS on CCM liveness probe (port 10258 is TLS-only).
- `004-10-reapply-manifests-on-recreation` (09-15): Control-plane instance ID in triggers of all manifest-apply null_resources.
- `004-11-ccm-elb-target-registration` (09-15): spec.providerID on nodes + get+watch on services in CCM ClusterRole.
- `004-12-pre-destroy-elb-cleanup` (09-16): Pre-destroy step deletes CCM-created Classic ELBs before subnet/IGW destroy.
- `004-13-cert-manager-k8s-version-skew` (09-16): Pin cert-manager to v1.19.4 (v1.20+ selectableFields rejected by 1.28).
- `004-14-cert-manager-webhook-gate` (09-16): Gate ClusterIssuer apply on cert-manager webhook/cainjector rollout.
- `004-15-cert-manager-issuer-apply-retry` (09-17): Bounded retry (10x5s) on ClusterIssuer apply for webhook window.
- `004-16-letsencrypt-contact-email` (09-19): Real ACME contact email replaces admin@example.com placeholder.

### 005–007 — Applications & ops
- `005-app-deployment` (09-01): MySQL StatefulSet + sample apps with cert-managed TLS (umbrella).
- `005-ingress-nginx-service-ports-fix` (09-12): Add missing spec.ports (80/443) to ingress-nginx Service.
- `005-mysql-statefulset` (09-12): MySQL 8.0.36 StatefulSet + PVC/Secret/Service; SSM Parameter Store as secrets source of truth.
- `006-main-config` (09-01): Root Terraform composition — remote state, data sources, provider, kubeconfig.
- `006-app-backend` (09-12): app-backend scaffold (2 replicas) + ClusterIP Service, public image, ECR deferred.
- `006-1-app-backend-nginx-image` (09-12): Re-image app-backend from crccheck/hello-world to nginx:alpine.
- `007-app-frontend-ingress` (09-12): app-frontend (2 replicas) + app-ingress Ingress — path-based routing via ingress-nginx.
- `007-1-ingress-webhook-readiness-gate` (09-13): kubectl rollout status gate before Ingress apply (webhook connection refused).
- `007-ops-tooling` (09-01): Validation scripts, health checks, operational procedures.

### 008–014 — Docs, DNS, ECR
- `008-final-docs` (09-01): Final architecture docs, runbooks, security model.
- `009-route53-domain` (09-16): Route 53 ALIAS for demo.vijote.dev + Let's Encrypt TLS on Ingress.
- `009-1-node-route53-wildcard` (09-17): route53:* wildcard on node role (ListHostedZones needed) + trigger bump.
- `009-2-cloudflare-dns-record` (09-17): Cloudflare CNAME for demo.vijote.dev (domain authoritative at Cloudflare); delete node_route53 policy.
- `010-ecr-repositories` (09-19): Frontend/backend ECR repos in new ecr module, mutable tags, URL outputs.
- `011-ecr-pull-secret` (09-19): ecr-pull-secret dockerconfigjson in sdd-apps minted on control plane via SSM.
- `013-ecr-url-diagnostic` (09-19): Manual-dispatch workflow printing ECR URL outputs (one-off diagnostic; removable).
- `014-ecr-pull-secret-guard-fix` (09-19): Fix self-defeating REGISTRY guard → empty-check only + trigger bump.