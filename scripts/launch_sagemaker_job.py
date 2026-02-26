#!/usr/bin/env python3
"""
Launch Romansh-LLM continued pretraining as an AWS SageMaker training job.

Requires: uv sync --extra aws (SageMaker Python SDK v3 with train extra)
Uses your default AWS credentials and the SageMaker role you specify.

Example:
  python scripts/launch_sagemaker_job.py \\
    --image-uri 123456789012.dkr.ecr.us-east-1.amazonaws.com/romansh-llm:latest \\
    --role arn:aws:iam::123456789012:role/MySageMakerRole \\
    --config configs/prod.yaml
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
_SRC = _REPO_ROOT / "src"
if _SRC.exists() and str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from romansh_llm.utils.logging import configure_logging, get_logger

logger = get_logger(__name__)


def _upload_config_to_s3(
    config_path: Path,
    region: str,
    account_id: str,
    bucket: str | None = None,
) -> str:
    """Upload config file to S3; return S3 URI for the config channel.
    If bucket is None, uses default sagemaker-{region}-{account} (may not exist; prefer passing Terraform s3_training_bucket).
    """
    import boto3

    if bucket is None:
        bucket = f"sagemaker-{region}-{account_id}"

    key = "input-config/config.yaml"
    s3 = boto3.client("s3", region_name=region)
    s3.upload_file(str(config_path.resolve()), bucket, key)
    return f"s3://{bucket}/{key}"


def main() -> None:
    parser = argparse.ArgumentParser(description="Launch CPT training job on SageMaker.")
    parser.add_argument("--image-uri", required=True, help="ECR URI of the training image (e.g. account.dkr.ecr.region.amazonaws.com/romansh-llm:latest)")
    parser.add_argument("--role", required=True, help="SageMaker execution IAM role ARN")
    parser.add_argument("--config", default="configs/prod.yaml", help="Path to config YAML (uploaded as config channel)")
    parser.add_argument("--instance-type", default="ml.g5.xlarge", help="SageMaker instance type (single GPU)")
    parser.add_argument("--job-name", default=None, help="Training job name (default: auto-generated)")
    parser.add_argument("--hf-token-env", default="HF_TOKEN", help="Env var name for HF token (set in job environment from your env)")
    parser.add_argument("--s3-bucket", default=None, help="S3 bucket for config upload (e.g. from Terraform s3_training_bucket; if unset, uses default SageMaker bucket which may not exist)")
    parser.add_argument("--log-level", default=None, metavar="LEVEL", help="Logging level (DEBUG, INFO, WARNING, ERROR). Default: LOG_LEVEL env or INFO.")
    args = parser.parse_args()

    configure_logging(level=args.log_level)

    _sdk_config = _REPO_ROOT / "configs" / "sagemaker_sdk_config.yaml"
    if _sdk_config.exists():
        os.environ["SAGEMAKER_USER_CONFIG_OVERRIDE"] = str(_sdk_config.resolve())

    from sagemaker.train import ModelTrainer
    from sagemaker.train.configs import Compute, InputData

    import boto3

    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = Path.cwd() / config_path
    if not config_path.exists():
        raise SystemExit(f"Config not found: {config_path}")

    session = boto3.Session()
    region = session.region_name or os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
    account_id = boto3.client("sts").get_caller_identity()["Account"]

    logger.info("Uploading config to S3...")
    config_uri = _upload_config_to_s3(config_path, region, account_id, bucket=args.s3_bucket)

    env = {}
    if args.hf_token_env and os.environ.get(args.hf_token_env):
        env[args.hf_token_env] = os.environ[args.hf_token_env]

    compute = Compute(instance_type=args.instance_type, instance_count=1)
    config_input = InputData(channel_name="config", data_source=config_uri)

    trainer_kw: dict = {
        "training_image": args.image_uri,
        "role": args.role,
        "compute": compute,
        "environment": env if env else None,
    }
    if args.job_name is not None:
        trainer_kw["base_job_name"] = args.job_name

    trainer = ModelTrainer(**trainer_kw)

    trainer.train(
        input_data_config=[config_input],
        wait=False,
    )

    job_name = trainer._latest_training_job.training_job_name
    logger.info("Training job started: %s", job_name)
    logger.info("Check status:  make job-status JOB_NAME=%s", job_name)
    logger.info("Stream logs:   make job-logs JOB_NAME=%s", job_name)
    logger.info("When complete, download the model with: make download-model JOB_NAME=%s", job_name)


if __name__ == "__main__":
    main()
