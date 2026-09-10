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
      Effect   = "Allow"
      Action   = [
        "ec2:CreateVolume", "ec2:DeleteVolume", "ec2:AttachVolume", "ec2:DetachVolume",
        "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeVolumes", "ec2:DescribeTags",
        "ec2:DescribeInstances", "ec2:DescribeSnapshots", "ec2:ModifyVolume"
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
