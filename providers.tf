locals {
  tags = merge(
    {
      ManagedBy = "Terraform"
      GitRepo   = regex("[^/]+$", path.cwd)
      Env       = var.env
    },
    var.tags
  )
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.tags
  }
}
