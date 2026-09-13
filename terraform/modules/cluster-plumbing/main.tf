# Control plane security group
resource "aws_security_group" "control_plane" {
  name_prefix = "sdd-k8s-control-plane-"
  description = "EKS control plane security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "etcd"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Flannel VXLAN data plane (pod-to-pod traffic across nodes) — 003-14
  ingress {
    description = "Flannel VXLAN"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Flannel API (subnet lease coordination) — 003-14
  ingress {
    description = "Flannel API"
    from_port   = 4240
    to_port     = 4240
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "sdd-k8s-control-plane"
  })
}

# Worker node security group
resource "aws_security_group" "worker" {
  name_prefix = "sdd-k8s-worker-"
  description = "EKS worker node security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "Kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "NodePort services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Flannel VXLAN data plane (pod-to-pod traffic across nodes) — 003-14
  ingress {
    description = "Flannel VXLAN"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Flannel API (subnet lease coordination) — 003-14
  ingress {
    description = "Flannel API"
    from_port   = 4240
    to_port     = 4240
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "sdd-k8s-worker"
  })
}

# IAM role for EKS worker nodes
resource "aws_iam_role" "node" {
  name = "sdd-k8s-platform-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Inline policy: Parameter Store read/write for the kubeadm join command channel
# (003-2 control plane publishes, 003-3 workers read)
resource "aws_iam_role_policy" "node_ssm_parameters" {
  name = "sdd-k8s-platform-node-ssm-parameters"
  role = aws_iam_role.node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:PutParameter", "ssm:GetParameter"]
      Resource = "arn:aws:ssm:*:*:parameter/sdd-k8s-platform/*"
    }]
  })
}

# Inline policy: EBS volume lifecycle for the EBS CSI driver (004-app-infrastructure).
# The EBS CSI controller (Deployment) + node plugin (DaemonSet) run as pods on the nodes and
# use the node's instance-profile credentials via IMDS (no IRSA — kubeadm has no OIDC provider).
resource "aws_iam_role_policy" "node_ebs_csi" {
  name = "sdd-k8s-platform-node-ebs-csi"
  role = aws_iam_role.node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:CreateVolume", "ec2:DeleteVolume", "ec2:AttachVolume", "ec2:DetachVolume",
        "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeVolumes", "ec2:DescribeTags",
        "ec2:DescribeInstances", "ec2:DescribeSnapshots", "ec2:ModifyVolume"
      ]
      Resource = "*"
    }]
  })
}

# Inline policy: ELB + EC2 lifecycle for the AWS Cloud Controller Manager (004-4).
# The CCM runs as a pod on the nodes and uses the node's instance-profile credentials
# via IMDS (no IRSA — kubeadm has no OIDC provider). Mirrors the node_ebs_csi pattern.
resource "aws_iam_role_policy" "node_aws_ccm" {
  name = "sdd-k8s-platform-node-aws-ccm"
  role = aws_iam_role.node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        # EC2 — node registration, ENI, volume + tag lifecycle
        "ec2:AssociateRouteTable", "ec2:CreateTags", "ec2:CreateVolume",
        "ec2:CreateNetworkInterface", "ec2:DeleteNetworkInterface",
        "ec2:DeleteSecurityGroup", "ec2:DeleteVolume",
        "ec2:DeregisterInstancesFromLoadBalancer", "ec2:Describe*",
        "ec2:DetachVolume", "ec2:ModifyInstanceAttribute",
        "ec2:RegisterInstancesWithLoadBalancer",
        # ELB — listener / target group / LB lifecycle
        "elasticloadbalancing:AddTags", "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteListener", "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DeleteTargetGroup", "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeTags",
        "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:ModifyTargetGroup", "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:RemoveTags", "elasticloadbalancing:SetSecurityGroups",
        "elasticloadbalancing:SetSubnets",
        # ASG — describe only (CCM reads group membership)
        "autoscaling:DescribeAutoScalingGroups"
      ]
      Resource = "*"
    }]
  })
}

# Instance profile for worker nodes
resource "aws_iam_instance_profile" "node" {
  name = "sdd-k8s-platform-node-profile"
  role = aws_iam_role.node.name

  tags = var.tags
}
