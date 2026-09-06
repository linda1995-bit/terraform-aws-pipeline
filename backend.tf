terraform {
  backend "s3" {
    bucket       = "linda-terraform-state-470880515561"
    key          = "dev/network/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}