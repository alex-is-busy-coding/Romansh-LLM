variable "aws_region" {
  description = "AWS region for ECR, SageMaker, and S3."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used for resource names (e.g. romansh-llm)."
  type        = string
  default     = "romansh-llm"
}

variable "ecr_image_tag" {
  description = "Default image tag to use in the ECR repository URL output (e.g. latest)."
  type        = string
  default     = "latest"
}

variable "environment" {
  description = "Environment: dev (lighter infra) or prod. Separate ECR, IAM role, S3, and IAM user per environment."
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}
