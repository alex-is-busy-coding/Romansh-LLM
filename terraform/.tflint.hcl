# TFLint config for Romansh-LLM Terraform (SageMaker infra).
# Run: tflint (from this dir) or make tf-lint (from repo root).
# Init plugins: tflint --init

tflint {
  required_version = ">= 0.50"
}

plugin "terraform" {
  enabled = true
  version = "0.14.1"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.45.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
