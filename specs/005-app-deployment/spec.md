# Spec: Application Deployment

**Feature Branch**: `005-app-deployment` | **Date**: 2026-09-01 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: EBS Volumes / Kubernetes Secrets / ConfigMaps / Services
- **Kubernetes / Cluster Scope**: MySQL 8.0 StatefulSet / Application Deployments / Ingress Resources
- **Target Services / Modules**: Database with persistent storage, sample application with TLS
- **Security & CI/CD**: Kubernetes Secrets for credentials, cert-managed TLS certificates

### 1.1 Terraform / HCL Resource Contracts
```hcl
# Input Variables / Schema
variable "mysql_root_password" {
  type        = string
  description = "Base64 encoded MySQL root password"
  sensitive   = true
}

variable "mysql_database" {
  type        = string
  description = "MySQL database name"
  default     = "sdd_app"
}

variable "mysql_username" {
  type        = string
  description = "MySQL application username"
  default     = "sdd_user"
}

variable "mysql_password" {
  type        = string
  description = "Base64 encoded MySQL application password"
  sensitive   = true
}

# Resource / Module Interface
module "application_deployment" {
  source = "./src/modules/application-deployment"
  
  mysql_root_password = var.mysql_root_password
  mysql_database      = var.mysql_database
  mysql_username      = var.mysql_username
  mysql_password      = var.mysql_password
  
  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "5"
  }
}

# Outputs
output "mysql_service_name" {
  value       = module.application_deployment.mysql_service_name
  description = "MySQL service name"
}

output "application_ingress_url" {
  value       = module.application_deployment.application_ingress_url
  description = "Application ingress URL"
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# MySQL Secret
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
  namespace: sdd-apps
type: Opaque
data:
  mysql-root-password: {{ MYSQL_ROOT_PASSWORD_BASE64 }}
  mysql-password: {{ MYSQL_PASSWORD_BASE64 }}

# MySQL StatefulSet
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  namespace: sdd-apps
spec:
  serviceName: mysql
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: mysql-root-password
        - name: MYSQL_DATABASE
          value: {{ MYSQL_DATABASE }}
        - name: MYSQL_USER
          value: {{ MYSQL_USERNAME }}
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: mysql-password
        ports:
        - containerPort: 3306
          name: mysql
        volumeMounts:
        - name: mysql-persistent-storage
          mountPath: /var/lib/mysql
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
  volumeClaimTemplates:
  - metadata:
      name: mysql-persistent-storage
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: "ebs-gp3"
      resources:
        requests:
          storage: 20Gi

# Sample Application Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sdd-app
  namespace: sdd-apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sdd-app
  template:
    metadata:
      labels:
        app: sdd-app
    spec:
      containers:
      - name: app
        image: nginx:1.25
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"

# Ingress with TLS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sdd-app-ingress
  namespace: sdd-apps
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  tls:
  - hosts:
    - app.sdd-platform.com
    secretName: sdd-app-tls
  rules:
  - host: app.sdd-platform.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sdd-app-service
            port:
              number: 80
```

### 1.3 Data & Storage Contracts
- **MySQL Storage**: 20Gi EBS gp3 volume with Retain policy
- **Database**: MySQL 8.0 with single instance, no replication
- **Backups**: Not configured in this phase (manual snapshots required)

### 1.4 Network & Security Contracts
- **MySQL Service**: ClusterIP only, no external exposure
- **Application Ingress**: TLS termination with Let's Encrypt certificate
- **Secrets Management**: Kubernetes Secrets with base64 encoding

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD:
- [ ] AC-001: MySQL StatefulSet running (`kubectl wait --for=condition=Ready statefulset/mysql -n sdd-apps --timeout=300s`)
- [ ] AC-002: MySQL PVC bound (`kubectl wait --for=condition=Bound pvc/mysql-persistent-storage-mysql-0 -n sdd-apps --timeout=300s`)
- [ ] AC-003: MySQL connectivity (`kubectl wait --for=condition=Ready pod -l app=mysql -n sdd-apps --timeout=300s && kubectl exec -n sdd-apps mysql-0 -- mysqladmin ping -u root -p"$MYSQL_ROOT_PASSWORD" --silent`)
- [ ] AC-004: Application deployment ready (`kubectl wait --for=condition=Available deployment/sdd-app -n sdd-apps --timeout=300s`)
- [ ] AC-005: Ingress created (`kubectl wait --for=condition=Ready ingress/sdd-app-ingress -n sdd-apps --timeout=300s`)
- [ ] AC-006: TLS certificate issued (`kubectl wait --for=condition=Ready certificate/sdd-app-tls -n sdd-apps --timeout=600s`)
- [ ] AC-007: Database accessible from app pod (`kubectl wait --for=condition=Ready pod -l app=sdd-app -n sdd-apps --timeout=300s && kubectl exec -n sdd-apps deployment/sdd-app -- mysql -h mysql.sdd-apps.svc.cluster.local -u sdd_user -p"$MYSQL_PASSWORD" -e "SELECT 1" --silent`)
- [ ] AC-008: HTTPS endpoint accessible (`kubectl wait --for=condition=Ready ingress/sdd-app-ingress -n sdd-apps --timeout=300s && INGRESS_IP=$(kubectl get ingress sdd-app-ingress -n sdd-apps -o jsonpath='{.status.loadBalancer.ingress[0].ip}') && curl -k -s -o /dev/null -w "%{http_code}" https://app.sdd-platform.com --resolve app.sdd-platform.com:443:$INGRESS_IP | grep -q '200'`)

## 3. Assumptions & Technical Constraints
- **Database**: Single instance MySQL 8.0, no HA or replication
- **Storage**: 20Gi persistent volume, manual backup strategy
- **IAM / Security Boundaries**: No external database access, internal service communication only
- **Certificates**: Let's Encrypt for production, domain must be configured
- **Testing Policy**: No unit or E2E test generation - validation performed directly against AWS infrastructure using CLI tools
- **Provider Versions**: Terraform >= 1.5.0, AWS provider >= 5.0.0