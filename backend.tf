terraform {
  backend "s3" {
    bucket       = "radioscan-tfstate-local"
    key          = "statefile/terraform.tfstate"
    region       = "sa-east-1"
    use_lockfile = true

    // Localstack configs
    endpoints = {
      s3  = "http://localhost:4566"
      iam = "http://localhost:4566"
      ec2 = "http://localhost:4566"
      sts = "http://localhost:4566"
    }

    // Localstack configs
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
  }
}
