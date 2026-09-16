## High‑level Plan

1. **Update the Service manifest** (`app-frontend-ingress.yaml`) to include a proper `spec.ports` block.
2. **Add optional health‑check annotations** (commented out) so downstream teams can enable an HTTP probe if desired.
3. **Run a Terraform apply** for the `null_resource.apply_app_frontend_ingress` provisioner – this will re‑apply the Service via SSM, causing the CCM to recreate the ELB with the corrected health‑check.
4. **Validate**: run the AC checks listed in `spec.md` in an automated test step (`terraform-apply.yml` job).
5. **Document** the change in the spec’s `README` and update the changelog.

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Mis‑typed port numbers could break the Ingress controller. | Service becomes unavailable. | Use explicit `port: 80` / `port: 443` and `targetPort` identical to container ports (the NGINX controller already listens on those). |
| The health‑check annotation could be applied accidentally on a cluster that forbids HTTP probes. | ELB health‑checks could fail. | Keep the HTTP annotations **commented** by default; enable only after explicit review. |
| Re‑creating the ELB may momentarily drop traffic. | Brief outage for the frontend. | The ELB recreation is fast (< 30 s) and occurs in a CI run; acceptable for dev/staging environments. |
