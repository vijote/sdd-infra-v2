# Latest Amazon Linux 2023 x86_64 AMI (AWS-owned)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Worker nodes: one per private subnet (indices 1 and 2; index 0 is the control plane)
locals {
  worker_subnets = {
    "worker-0" = var.private_subnet_ids[1]
    "worker-1" = var.private_subnet_ids[2]
  }
}

resource "aws_instance" "worker" {
  for_each = local.worker_subnets

  ami                    = data.aws_ami.al2023.id
  instance_type          = "t2.medium"
  subnet_id              = each.value
  vpc_security_group_ids = [var.worker_security_group_id]
  iam_instance_profile   = var.node_iam_instance_profile_name

  # No public IP — private subnet, reached via NAT for outbound only
  associate_public_ip_address = false

  user_data = file("${path.module}/bootstrap.sh")

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  tags = merge(var.tags, {
    Name = "sdd-k8s-${each.key}"
  })
}
