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

# Control plane node (single, dev environment)
resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t2.medium"
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.control_plane_security_group_id]
  iam_instance_profile   = var.node_iam_instance_profile_name

  # No public IP — private subnet, reached via NAT for outbound only
  associate_public_ip_address = false

  user_data = file("${path.module}/bootstrap.sh")

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  tags = merge(var.tags, {
    Name = "sdd-k8s-control-plane"
  })
}
