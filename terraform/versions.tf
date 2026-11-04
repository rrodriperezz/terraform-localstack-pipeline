# No backend block: state stays local and .gitignore excludes it. This repository is
# never applied against a real AWS account, so a remote backend would add a bucket and a
# lock table that nobody would use.
terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6"
    }
  }
}
