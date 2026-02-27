# Terraform: SageMaker training infrastructure

This directory defines the AWS resources needed to run Romansh-LLM continued pretraining on SageMaker:

- **ECR repository** – holds the training Docker image
- **IAM role** – used by SageMaker to pull the image, read/write S3, and write logs
- **S3 bucket** – optional dedicated bucket for training output (SageMaker can also use its default bucket)
- **IAM user** – `{project_name}-{environment}-terraform` with a single policy for Terraform, ECR push, and SageMaker launcher; recreate in any account by running Terraform

Resources are **per environment** (`dev` or `prod`): e.g. `romansh-llm-dev-*` vs `romansh-llm-prod-*`. Pass `-var=environment=dev` or `-var=environment=prod` (or set `ENV=dev` / `ENV=prod` when using the Makefile). The same state file holds one environment at a time; to have both dev and prod infra in the same account, use [Terraform workspaces](https://developer.hashicorp.com/terraform/language/state/workspaces) (e.g. `terraform workspace new dev`, `terraform workspace new prod`) and run apply with the workspace selected and the same `-var=environment=<workspace>`.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- AWS CLI configured: run `uv sync --extra aws` then `uv run aws configure` (or set `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_REGION` in CI)

## Make targets (from repo root)

| Target | Description |
|--------|-------------|
| `make tf-init` | Terraform init |
| `make tf-plan ENV=prod` | Plan (use `ENV=dev` for dev) |
| `make tf-apply ENV=prod` | Create/update infra for that environment |
| `make tf-output` | Show all Terraform outputs |
| `make tf-destroy ENV=prod` | Destroy infra for that environment |
| `make docker-push ENV=prod` | Build and push training image to ECR |
| `make sagemaker-launch ENV=prod` | Start SageMaker training job (uses config and bucket from Terraform) |

One-shot full flow: `make aws-pretrain ENV=prod` (optionally with `YES=1`, `SKIP_TERRAFORM=1`, `SKIP_PUSH=1`). See main [README](../README.md#quick-start) for `make job-status`, `make job-logs`, `make download-model`.

## Usage

1. **Initialize and plan**
   From repo root (recommended): `make tf-init` then `make tf-plan ENV=prod` (or `ENV=dev`). Or from this directory:
   ```bash
   cd terraform
   terraform init
   terraform plan -out=tfplan -var=environment=prod
   ```
   Always pass `-var=environment=dev` or `-var=environment=prod` so plan matches the environment you will apply/destroy.

2. **Apply** (creates ECR repo, IAM role, S3 bucket, and IAM user for the chosen **environment**). You need credentials that can create IAM users (e.g. root or an admin) for the first run.
   ```bash
   terraform apply -var=environment=prod
   # or from repo root: make tf-apply ENV=prod   (use ENV=dev for dev infra)
   ```

3. **Create the training IAM user’s access key** (one-time after first apply). Terraform creates the user and attaches the policy; it does not create an access key. In the AWS console: IAM → Users → *user name from `terraform output iam_training_user_name`* → Security credentials → Create access key. Then run `uv run aws configure` and use that key so all later commands (Terraform, docker push, launcher) use the least-privilege user.

4. **Use the outputs** after apply:
   ```bash
   terraform output ecr_image_uri          # full image URI for SageMaker
   terraform output ecr_repository_url     # ECR URL without tag (for docker login)
   terraform output sagemaker_role_arn     # IAM role for training jobs
   terraform output s3_training_bucket     # bucket for training output and config channel (launcher uploads config here)
   terraform output region                 # AWS region
   terraform output iam_training_user_name # user to create access key for
   ```
   From repo root: `make tf-output` shows all outputs.

5. **Build, tag, push the image** (from repo root):
   **Recommended:** `make docker-push ENV=prod` (or `ENV=dev`). This uses Terraform outputs for the current environment.
   Or manually:
   ```bash
   aws ecr get-login-password --region $(terraform -chdir=terraform output -raw region) | \
     docker login --username AWS --password-stdin $(terraform -chdir=terraform output -raw ecr_repository_url | cut -d/ -f1)
   docker build -t romansh-llm .
   docker tag romansh-llm:latest $(terraform -chdir=terraform output -raw ecr_image_uri)
   docker push $(terraform -chdir=terraform output -raw ecr_image_uri)
   ```

6. **Launch a training job** (from repo root):
   **Recommended:** `make sagemaker-launch ENV=prod` (or `ENV=dev`). This picks the right image, role, S3 bucket (for the config channel), and config (`configs/prod.yaml` or `configs/dev.yaml`) from Terraform outputs. Set `HF_TOKEN` for gated models. The launcher prints `make job-status`, `make job-logs`, and `make download-model` with the job name.
   Or manually:
   ```bash
   uv sync --extra aws
   export HF_TOKEN=your_token   # optional, for gated models
   python scripts/launch_sagemaker_job.py \
     --image-uri $(terraform -chdir=terraform output -raw ecr_image_uri) \
     --role $(terraform -chdir=terraform output -raw sagemaker_role_arn) \
     --s3-bucket $(terraform -chdir=terraform output -raw s3_training_bucket) \
     --config configs/prod.yaml
   ```

## Variables

| Variable        | Description                          | Default      |
|----------------|--------------------------------------|--------------|
| `aws_region`   | AWS region for all resources         | `us-east-1`  |
| `project_name` | Prefix for resource names            | `romansh-llm`|
| `environment`  | `dev` or `prod`; separate ECR/IAM/S3 per env | `prod` |
| `ecr_image_tag`| Tag used in `ecr_image_uri` output   | `latest`     |

Override with `-var` or a `terraform.tfvars` file, e.g.:

```hcl
aws_region   = "eu-central-1"
project_name = "romansh-llm"
```

## Destroy

To remove all created resources for an environment, use the **same** `environment` (or `ENV`) you used for apply; otherwise you may leave resources in state or destroy the wrong env.

From repo root (recommended):
```bash
make tf-destroy ENV=prod
# or make tf-destroy ENV=dev
```

Or from this directory:
```bash
cd terraform
terraform destroy -var=environment=prod
```

If you created an access key for the IAM user, delete it in the console (IAM → Users → *user* → Security credentials) first, or destroy will fail when removing the user. Empty the S3 bucket first if Terraform fails to delete it (e.g. versioning or objects present).
