# Requirements Checklist: Terraform Working Directory Fix

## Technical Contracts
- [ ] Terraform working directory contract defined (`cd terraform && terraform init`)
- [ ] Terraform plan command contract defined with working directory context
- [ ] Terraform show JSON conversion contract defined in working directory
- [ ] Terraform apply command contract defined with working directory context
- [ ] GitHub Actions workflow step contract specified with working-directory parameter
- [ ] Module source resolution contract defined from working directory
- [ ] State file and plan file storage contract defined

## Machine-Verifiable Acceptance Criteria
- [ ] AC-001: Terraform init executes successfully from working directory
- [ ] AC-002: Terraform plan generates expected resources from working directory
- [ ] AC-003: Terraform show JSON conversion succeeds in working directory
- [ ] AC-004: Terraform apply executes successfully from working directory
- [ ] AC-005: GitHub Actions workflow steps complete with working-directory parameter
- [ ] AC-006: Module sources resolve correctly from working directory
- [ ] AC-007: State file and plan files generated in correct directory

## Security & CI/CD
- [ ] GitHub Actions runner environment specified (Ubuntu latest)
- [ ] Working directory context requirements documented
- [ ] Path resolution requirements defined
- [ ] Artifact storage and retention policy specified
- [ ] Workflow path and dependencies specified

## Technical Constraints
- [ ] Terraform version requirement specified (>=1.5.0)
- [ ] Directory structure requirements defined
- [ ] Module source path resolution documented
- [ ] Working directory assumptions specified
- [ ] Backward compatibility considerations addressed
- [ ] Testing policy specified (workflow execution validation)

## Specification Quality
- [ ] Zero conversational narrative or marketing fluff
- [ ] All technical contracts are explicit and machine-verifiable
- [ ] Acceptance criteria are executable CLI commands
- [ ] Infrastructure boundaries clearly defined
- [ ] Security and IAM considerations documented