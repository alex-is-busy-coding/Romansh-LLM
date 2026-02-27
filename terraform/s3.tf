resource "aws_s3_bucket" "training_output" {
  bucket = "${local.env_prefix}-training-${local.account_id}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "training_output" {
  bucket = aws_s3_bucket.training_output.id

  versioning_configuration {
    status = "Disabled"
  }
}

# Block public access (recommended for model artifacts)
resource "aws_s3_bucket_public_access_block" "training_output" {
  bucket = aws_s3_bucket.training_output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
