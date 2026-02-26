output "ecr_repository_url" {
  description = "ECR repository URL for the training image (without tag)."
  value       = aws_ecr_repository.training.repository_url
}

output "ecr_image_uri" {
  description = "Full ECR image URI to use for SageMaker training (with default tag)."
  value       = "${aws_ecr_repository.training.repository_url}:${var.ecr_image_tag}"
}

output "sagemaker_role_arn" {
  description = "IAM role ARN for SageMaker training jobs. Use with --role in the launcher."
  value       = aws_iam_role.sagemaker_training.arn
}

output "s3_training_bucket" {
  description = "S3 bucket name for training output (optional; SageMaker can also use the default bucket)."
  value       = aws_s3_bucket.training_output.id
}

output "region" {
  description = "AWS region used for resources."
  value       = local.region
}

output "iam_training_user_name" {
  description = "IAM user created for Terraform, docker push, and SageMaker launcher. Create an access key for this user and run uv run aws configure."
  value       = aws_iam_user.training.name
}

output "environment" {
  description = "Terraform environment (dev or prod)."
  value       = var.environment
}
