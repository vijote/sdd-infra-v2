module "terraform_backend" {
  source = "../../modules/terraform-backend"
  
  state_bucket_name = var.state_bucket_name
  region            = var.region
  
  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "2"
  }
}