## Tasks (ordered)

1. **Modify Service manifest**
   - File: `terraform/environments/dev/manifests/app-frontend-ingress.yaml`
   - Add the `spec.ports` block (see diff below) and optional health‑check annotations as commented lines.

   ```diff
   @@
    metadata:
      name: ingress-nginx-controller
      namespace: ingress-nginx
   -  annotations: {}
   +  annotations:
   +    # (keep any existing annotations you need, e.g. subnet annotation)
   +    # service.beta.kubernetes.io/aws-load-balancer-subnets: "<public‑subnet‑ids>"
   +    # Optional HTTP health‑check (uncomment to enable)
   +    # service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: "HTTP"
   +    # service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "80"
   +    # service.beta.kubernetes.io/aws-load-balancer-healthcheck-path: "/healthz"
      
    spec:
      type: LoadBalancer
   +  ports:
   +    - name: http
   +      protocol: TCP
   +      port: 80
   +      targetPort: 80
   +    - name: https
   +      protocol: TCP
   +      port: 443
   +      targetPort: 443
   +  selector:
   +    app.kubernetes.io/name: ingress-nginx
   +    app.kubernetes.io/component: controller
   ```

2. **Commit the change**
   - Branch: `spec/005-ingress-nginx-service-ports-fix`
   - PR title: `spec: 005 – add required ports to ingress‑nginx Service`

3. **Run CI** (`terraform-apply.yml`)
   - The CI job will invoke the `null_resource.apply_app_frontend_ingress` provisioner, which uses SSM to re‑apply the manifest on the control‑plane. This triggers the CCM to recreate the ELB with the corrected health‑check.

4. **Automated verification** (added to the CI job)
   - `kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.ports}'` → non‑empty array with ports 80 and 443.
   - `aws elb describe-load-balancers … --query 'LoadBalancerDescriptions[0].HealthCheck'` → contains either `TCP:80` or `HTTP:80/healthz`.
   - `aws elb describe-instance-health …` → both backend instances `InService`.
   - `curl -s -o /dev/null -w "%{http_code}" -H "Host: frontend.example.com" http://<elb‑dns>/` → `200`.

5. **Document** in `CHANGELOG.md` under the next version bump.

6. **Optional cleanup** – If the team decides to enable the HTTP health‑check, remove the comment markers from the annotations and re‑run the CI.

## Definition of Done
- All tasks above are completed and merged.
- CI reports **green** (all acceptance criteria pass).
- The spec folder (`specs/005-ingress-nginx-service-ports-fix`) contains `spec.md`, `plan.md`, and `tasks.md`.
- No regression is introduced (existing tests still pass).
