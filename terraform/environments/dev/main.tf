module "terraform_backend" {
  source = "../../modules/terraform-backend"

  state_bucket_name = var.state_bucket_name
  region            = var.region
}

module "vpc" {
  source = "../../modules/vpc"

  region             = var.region
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "1"
  }
}

module "cluster_plumbing" {
  source = "../../modules/cluster-plumbing"

  region   = var.region
  vpc_id   = module.vpc.vpc_id
  vpc_cidr = var.vpc_cidr

  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "3"
  }
}

module "control_plane" {
  source = "../../modules/control-plane"

  region                           = var.region
  vpc_id                           = module.vpc.vpc_id
  private_subnet_ids               = module.vpc.private_subnet_ids
  control_plane_security_group_id  = module.cluster_plumbing.control_plane_security_group_id
  node_iam_instance_profile_name   = module.cluster_plumbing.node_iam_instance_profile_name

  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "3"
  }
}