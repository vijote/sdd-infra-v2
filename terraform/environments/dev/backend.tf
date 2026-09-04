terraform {
  backend "s3" {
    key     = "terraform.tfstate"
    encrypt = true
    # bucket and region will be provided via -backend-config
  }
}