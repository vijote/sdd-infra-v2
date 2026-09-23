# Checklist: 012-ecr-image-deploy

| CHK# | Requirement | Status |
|------|-------------|--------|
| CHK001 | Terraform variable contracts declared with types/defaults (`backend_image_tag`, `frontend_image_tag`) | ✅ |
| CHK002 | null_resource contract defined (triggers, SSM steps, rollout status) | ✅ |
| CHK003 | Kubernetes manifest contracts declared (image refs, imagePullSecrets, conditional swap) | ✅ |
| CHK004 | Acceptance criteria machine-verifiable (terraform fmt/validate/plan, kubectl jsonpath/rollout) | ✅ |
| CHK005 | Security boundaries specified (no API exposure, PAT scope, SSM-only kubectl) | ✅ |
| CHK006 | ECR token refresh strategy + documented risk | ✅ |
| CHK007 | Placeholder single-occurrence rule respected (014 gotcha) | ✅ |
| CHK008 | Zero conversational narrative; technical content only | ✅ |
| CHK009 | No validation/test steps in workflow definitions (constitution §6) | ✅ |
| CHK010 | Spec under 200 lines | ✅ (71 lines) |
