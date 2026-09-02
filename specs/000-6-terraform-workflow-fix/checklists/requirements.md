# Requirements Checklist: Terraform Workflow Fix

## Technical Contracts
- [ ] Terraform plan command contract defined (`terraform plan -out=tfplan`)
- [ ] Terraform show JSON conversion contract defined (`terraform show -json tfplan > plan.json`)
- [ ] jq processing contract defined for resource mode extraction
- [ ] GitHub Actions workflow step contract specified
- [ ] Binary plan file storage contract defined
- [ ] JSON plan file processing contract defined

## Machine-Verifiable Acceptance Criteria
- [ ] AC-001: Terraform plan command executes without syntax errors
- [ ] AC-002: Terraform show JSON conversion succeeds
- [ ] AC-003: jq processing extracts resource modes successfully
- [ ] AC-004: GitHub Actions workflow step completes successfully
- [ ] AC-005: Binary plan file is valid for apply execution
- [ ] AC-006: Phase detection output is properly set

## Security & CI/CD
- [ ] GitHub Actions runner environment specified (Ubuntu latest)
- [ ] AWS credentials configuration via OIDC documented
- [ ] Artifact storage and retention policy defined
- [ ] Workflow path and dependencies specified

## Technical Constraints
- [ ] Terraform version requirement specified (>=1.5.0)
- [ ] jq availability assumption documented
- [ ] Plan file compatibility requirements defined
- [ ] Backward compatibility considerations addressed
- [ ] Testing policy specified (workflow execution validation)

## Specification Quality
- [ ] Zero conversational narrative or marketing fluff
- [ ] All technical contracts are explicit and machine-verifiable
- [ ] Acceptance criteria are executable CLI commands
- [ ] Infrastructure boundaries clearly defined
- [ ] Security and IAM considerations documented