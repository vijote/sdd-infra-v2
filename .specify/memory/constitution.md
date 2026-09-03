# System & LLM Execution Directives

## Core Principles

### 1. Zero Narrative Policy
Skip all introductory conversational filler, user personas, marketing justifications, and high-level product narratives. Go directly to technical infrastructure contracts, Terraform definitions, Kubernetes manifests, Helm values, and machine-verifiable acceptance criteria.

### 2. Architecture First & Explicit Engineering Contracts
Use explicit engineering jargon, precise file paths, and exact cloud/infrastructure resource names. Every specification and plan MUST define:
- Exact Terraform/HCL resource & variable signatures (with types, defaults, and constraints)
- Exact Kubernetes API versions, CRDs, Helm `values.yaml` schemas, and manifest structures (kubeadm, kubectl, cert-manager, MySQL, NGINX Ingress, Flannel CNI)
- Network topologies, security group rules, IAM policies, and storage specifications (EBS/EFS/CSI)
- GitHub OIDC trust relationships for CI/CD

### 3. Payload & Token Efficiency
Keep spec, plan, and architecture delta artifacts strictly below 200 lines. Use compact markdown tables, bullet points, and code blocks. Non-frontier and local LLMs (e.g. GLM-4.6, Qwen-Coder) must not experience reasoning degradation from bloated context windows.

### 4. Granular Dependency Tree (Micro-DAG)
Write `tasks.md` as an acyclic dependency graph (DAG) where every task corresponds to a 1:1 file edit, Terraform module, Kubernetes manifest, or verification step with explicit dependency pointers:
`- [ ] T001 [Stage] Task description in path/to/file (Depends on Txxx)`

### 5. Machine-Verifiable Acceptance Gates
Never use vague adjectives ("robust", "scalable", "fast"). All acceptance criteria MUST be machine-verifiable through automated CI/CD commands:
- Terraform validation & plan (`terraform validate`, `terraform plan -detailed-exitcode`)
- Manifest & chart linting (`helm lint`, `kubectl apply --dry-run=client`, `kubeconform`)
- Health probes, status rollouts (`kubectl rollout status`, `kubectl wait --for=condition=Ready`)
- Endpoint & database connectivity checks (TLS handshake via cert-manager, MySQL connection & query exit codes)
- **CRITICAL**: All acceptance criteria must be executable in GitHub Actions without manual intervention. No manual SSH, console access, or interactive commands.
- **CRITICAL**: Validation commands are designed for CI/CD workflows, not local testing. No local AWS CLI, GitHub CLI, or other tooling required.

### 6. Testing Policy
- **No Unit Tests**: Do not generate unit test files (e.g., `*_test.go`, `*.spec.ts`, `__tests__/` directories)
- **No E2E Tests**: Do not generate end-to-end test suites or integration test frameworks
- **CI/CD Workflow Validation**: All validation is performed in GitHub Actions workflows (terraform-apply, terraform-destroy) before deployment
- **No Local Tooling Required**: No local AWS CLI, GitHub CLI, kubectl, or other infrastructure tooling required for validation
- **Context Optimization**: Exclude test generation to minimize context usage for LLM agents

### 7. CI/CD Automation Policy
- **No Manual Approval Gates**: All deployments must be fully automated on main branch push without manual intervention or approval workflows
- **Automated Deployment**: Infrastructure changes are applied automatically through GitHub Actions with proper validation gates
- **Security via Automation**: Security is enforced through automated OIDC authentication, least-privilege IAM roles, and machine-verifiable validation - not through manual approval processes
- **Immutable Deployment**: Rollbacks and changes are handled through version-controlled infrastructure code, not manual intervention

## Session Isolation Protocol
When implementing tasks with LLM agents, load only the minimal context payload:
1. Directive: `.specify/memory/constitution.md`
2. Active Single Task: Target file, action goal, and exact data/infrastructure contract
3. Instruction: Output ONLY the implementation code/manifest and verification command. No conversational text outside code blocks.

## Governance
This constitution is the non-negotiable governing standard for all SpecKit artifacts in this repository. All PRs, plans, specifications, and task graphs must strictly adhere to these directives.

**Version**: 2.2.0 | **Ratified**: 2026-08-31 | **Last Amended**: 2026-09-02
