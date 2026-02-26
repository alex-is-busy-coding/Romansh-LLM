#!/usr/bin/env bash
# Run full AWS pretraining: Terraform apply, push image to ECR, launch SageMaker job.
# Run from repo root. Optional: source .env for HF_TOKEN (gated models).
#
# Usage:
#   ENV=dev ./scripts/run_aws_pretrain.sh [OPTIONS]
#   ENV=prod ./scripts/run_aws_pretrain.sh [OPTIONS]
#
# ENV=dev or prod selects configs/dev.yaml or configs/prod.yaml and Terraform environment (separate infra per env).
# Options:
#   --yes              Terraform apply -auto-approve (non-interactive)
#   --skip-terraform   Skip terraform init/apply (infra already exists)
#   --skip-push        Skip docker build and push (image already in ECR)
#
# For dev, a smaller instance type is used unless INSTANCE_TYPE is set.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

ENV="${ENV:-prod}"
if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
  echo "Error: ENV must be 'dev' or 'prod' (got: $ENV)." >&2
  exit 1
fi
CONFIG="${CONFIG:-configs/${ENV}.yaml}"
TF_DIR="${TF_DIR:-terraform}"
TF_VAR_ENV="-var=environment=${ENV}"
SKIP_TERRAFORM=
SKIP_PUSH=
TF_AUTO_APPROVE=

if [[ "$ENV" = "dev" ]]; then
  INSTANCE_TYPE="${INSTANCE_TYPE:-ml.g4dn.xlarge}"
else
  INSTANCE_TYPE="${INSTANCE_TYPE:-ml.g5.xlarge}"
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --yes)
      TF_AUTO_APPROVE="-auto-approve"
      shift
      ;;
    --skip-terraform)
      SKIP_TERRAFORM=1
      shift
      ;;
    --skip-push)
      SKIP_PUSH=1
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      CONFIG="$1"
      shift
      ;;
  esac
done

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

echo "==> ENV: $ENV, Config: $CONFIG, Instance: $INSTANCE_TYPE"

if [[ -z "$SKIP_PUSH" ]]; then
  _docker_path=""
  if [[ -n "${DOCKER:-}" && -x "${DOCKER}" ]]; then
    _docker_path="$DOCKER"
  else
    _docker_path="$(command -v docker 2>/dev/null)" || true
    if [[ -z "$_docker_path" ]]; then
      for _d in /usr/local/bin /opt/homebrew/bin "/Applications/Docker.app/Contents/Resources/bin"; do
        [[ -x "${_d}/docker" ]] && _docker_path="${_d}/docker" && break
      done
    fi
  fi
  if [[ -z "$_docker_path" ]]; then
    echo "Warning: docker was not found. Install Docker (e.g. Docker Desktop) or add it to PATH." >&2
    echo "  This run will fail at the 'Docker build and push' step unless you use --skip-push." >&2
    echo "" >&2
  fi
fi

echo ""

if ! uv run aws sts get-caller-identity >/dev/null 2>&1; then
  echo "Error: AWS credentials not found or invalid."
  echo "Install the AWS CLI: uv sync --extra aws"
  echo "Then run: uv run aws configure"
  echo "See README section 'Train on AWS SageMaker' for details."
  exit 1
fi

if [[ -z "$SKIP_TERRAFORM" ]]; then
  echo "==> Terraform init and apply (environment=$ENV)"
  terraform -chdir="$TF_DIR" init
  terraform -chdir="$TF_DIR" apply $TF_AUTO_APPROVE $TF_VAR_ENV
  echo ""
fi

if [[ -z "$SKIP_PUSH" ]]; then
  echo "==> Docker build and push to ECR"
  if [[ -n "${DOCKER:-}" && -x "${DOCKER}" ]]; then
    :
  else
    if ! command -v docker >/dev/null 2>&1; then
      for _d in /usr/local/bin /opt/homebrew/bin "/Applications/Docker.app/Contents/Resources/bin"; do
        if [[ -x "${_d}/docker" ]]; then
          export PATH="${_d}:${PATH}"
          break
        fi
      done
    fi
    if ! command -v docker >/dev/null 2>&1; then
      echo "Error: docker not found. Install Docker (e.g. Docker Desktop) or ensure docker is in your PATH." >&2
      echo "  If Docker is installed, try running this script directly: ENV=dev $REPO_ROOT/scripts/run_aws_pretrain.sh" >&2
      echo "  Or set DOCKER=/path/to/docker and re-run make." >&2
      exit 127
    fi
    DOCKER=docker
  fi
  reg=$(terraform -chdir="$TF_DIR" output -raw ecr_repository_url | cut -d/ -f1)
  uri=$(terraform -chdir="$TF_DIR" output -raw ecr_image_uri)
  region=$(terraform -chdir="$TF_DIR" output -raw region)
  "$DOCKER" build --platform linux/amd64 -t romansh-llm:latest .
  uv run aws ecr get-login-password --region "$region" | "$DOCKER" login --username AWS --password-stdin "$reg"
  "$DOCKER" tag romansh-llm:latest "$uri"
  "$DOCKER" push "$uri"
  echo ""
fi

echo "==> Launch SageMaker training job"
uri=$(terraform -chdir="$TF_DIR" output -raw ecr_image_uri)
role=$(terraform -chdir="$TF_DIR" output -raw sagemaker_role_arn)
bucket=$(terraform -chdir="$TF_DIR" output -raw s3_training_bucket)
uv run python scripts/launch_sagemaker_job.py --image-uri "$uri" --role "$role" --config "$CONFIG" --instance-type "$INSTANCE_TYPE" --s3-bucket "$bucket"

echo ""
echo "Done. Check the SageMaker console for job status."
