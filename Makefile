# Romansh-LLM: run data and training scripts from repo root.
# Use ENV=dev or ENV=prod to select config and Terraform environment (default: prod).

.PHONY: download-data pretrain all help
.PHONY: tf-init tf-plan tf-apply tf-destroy tf-output
.PHONY: docker-build docker-push sagemaker-launch aws-pretrain download-model job-status job-logs

ENV ?= prod
CONFIG ?= configs/$(ENV).yaml
SCRIPTS := scripts
TF_DIR := terraform
TF_VAR_ENV = -var=environment=$(ENV)

help:
	@echo "Romansh-LLM targets (ENV=dev or prod, default: prod):"
	@echo "  make download-data     Cache ZurichNLP/quotidiana from Hugging Face"
	@echo "  make pretrain          Run CPT with QLoRA (ENV=$(ENV), CONFIG=$(CONFIG))"
	@echo "  make all               download-data then pretrain"
	@echo ""
	@echo "Terraform (SageMaker infra; separate per ENV):"
	@echo "  make tf-init           terraform init"
	@echo "  make tf-plan           terraform plan (ENV=$(ENV))"
	@echo "  make tf-apply          terraform apply (ENV=$(ENV))"
	@echo "  make tf-destroy        terraform destroy (ENV=$(ENV))"
	@echo "  make tf-output         show terraform outputs"
	@echo ""
	@echo "Docker & SageMaker:"
	@echo "  make docker-build      Build training image (local)"
	@echo "  make docker-push       Push image to ECR (requires tf-apply for current ENV)"
	@echo "  make sagemaker-launch  Start CPT job (ENV=$(ENV); optional: HF_TOKEN, INSTANCE_TYPE)"
	@echo "  make aws-pretrain      Full AWS flow for ENV (optional: YES=1, SKIP_TERRAFORM=1, SKIP_PUSH=1)"
	@echo "  make download-model    Download model from SageMaker S3 (requires JOB_NAME=...)"
	@echo "  make job-status        Check SageMaker training job status (requires JOB_NAME=...)"
	@echo "  make job-logs          Stream training job logs from CloudWatch (requires JOB_NAME=...; Ctrl+C to stop)"
	@echo ""
	@echo "Examples: make pretrain ENV=dev | make aws-pretrain ENV=dev | make download-model JOB_NAME=... | make job-status JOB_NAME=... | make job-logs JOB_NAME=..."

download-data:
	$(SCRIPTS)/download_data.sh

pretrain:
	CONFIG=$(CONFIG) $(SCRIPTS)/pretrain.sh

all: download-data pretrain

# --- Terraform (pass environment so resource names match ENV) ---
tf-init:
	terraform -chdir=$(TF_DIR) init

tf-plan: tf-init
	terraform -chdir=$(TF_DIR) plan -out=tfplan $(TF_VAR_ENV)

tf-apply:
	terraform -chdir=$(TF_DIR) apply $(TF_VAR_ENV)

tf-destroy:
	terraform -chdir=$(TF_DIR) destroy $(TF_VAR_ENV)

tf-output:
	terraform -chdir=$(TF_DIR) output

# --- Docker (local build; push uses ECR from Terraform) ---
# Build for linux/amd64 so the image runs on SageMaker (required when building on ARM e.g. Mac)
docker-build:
	docker build --platform linux/amd64 -t romansh-llm .

docker-push: docker-build
	@reg=$$(terraform -chdir=$(TF_DIR) output -raw ecr_repository_url 2>/dev/null | cut -d/ -f1); \
	uri=$$(terraform -chdir=$(TF_DIR) output -raw ecr_image_uri 2>/dev/null); \
	if [ -z "$$uri" ]; then echo "Run 'make tf-apply ENV=$(ENV)' first."; exit 1; fi; \
	uv run aws ecr get-login-password --region $$(terraform -chdir=$(TF_DIR) output -raw region) | docker login --username AWS --password-stdin $$reg; \
	docker tag romansh-llm:latest $$uri; \
	docker push $$uri

# --- Download trained model from SageMaker S3 (default output path) ---
# Requires JOB_NAME=... (the SageMaker training job name, e.g. from console or launcher output).
# Downloads to output/sagemaker/$(JOB_NAME)/ and unpacks model.tar.gz -> final/
download-model:
	@if [ -z "$(JOB_NAME)" ]; then echo "Error: pass JOB_NAME=... (the SageMaker training job name)."; exit 1; fi; \
	region=$${AWS_REGION:-$$AWS_DEFAULT_REGION}; [ -z "$$region" ] && region=$$(aws configure get region 2>/dev/null); \
	if [ -z "$$region" ]; then echo "Error: set AWS_REGION or run 'aws configure'."; exit 1; fi; \
	account=$$(aws sts get-caller-identity --query Account --output text 2>/dev/null); \
	if [ -z "$$account" ]; then echo "Error: AWS credentials not configured (run 'uv run aws configure')."; exit 1; fi; \
	s3_uri="s3://sagemaker-$$region-$$account/output/$(JOB_NAME)/output/model.tar.gz"; \
	dest_dir="output/sagemaker/$(JOB_NAME)"; \
	mkdir -p "$$dest_dir"; \
	echo "Downloading $$s3_uri to $$dest_dir/..."; \
	uv run aws s3 cp "$$s3_uri" "$$dest_dir/model.tar.gz" && \
	(cd "$$dest_dir" && tar -xzf model.tar.gz && echo "Unpacked model to $$dest_dir/final/") || \
	{ echo "Download failed. Check JOB_NAME and that the job has completed."; exit 1; }

# --- Check SageMaker training job status (requires JOB_NAME=...) ---
job-status:
	@if [ -z "$(JOB_NAME)" ]; then echo "Error: pass JOB_NAME=... (the SageMaker training job name)."; exit 1; fi; \
	echo "Training job: $(JOB_NAME)"; echo ""; \
	r=$$(uv run aws sagemaker describe-training-job --training-job-name "$(JOB_NAME)" \
		--query '[TrainingJobStatus,SecondaryStatus,CreationTime,TrainingEndTime,FailureReason]' --output text 2>/dev/null) || exit 1; \
	IFS=$$'\t' read -r status secondary started ended failure <<< "$$r"; \
	started_fmt=$$( [ "$$started" = "None" ] && echo "None" || (date -r "$${started%%.*}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$${started%%.*}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || echo "$$started"); \
	ended_fmt=$$( [ "$$ended" = "None" ] && echo "None" || (date -r "$${ended%%.*}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$${ended%%.*}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || echo "$$ended"); \
	echo "Status:    $$status"; echo "Secondary: $$secondary"; echo "Started:   $$started_fmt"; echo "Ended:     $$ended_fmt"; echo "Failure:   $$failure"

# --- Show SageMaker training job logs from CloudWatch (requires JOB_NAME=...; works with AWS CLI v1 and v2) ---
# For live streaming with AWS CLI v2: aws logs tail /aws/sagemaker/TrainingJobs --log-stream-name-prefix $(JOB_NAME) --follow
job-logs:
	@if [ -z "$(JOB_NAME)" ]; then echo "Error: pass JOB_NAME=... (the SageMaker training job name)."; exit 1; fi; \
	start=$$(($$(date +%s) - 7200)); start_ms=$$((start * 1000)); \
	uv run aws logs filter-log-events --log-group-name /aws/sagemaker/TrainingJobs --log-stream-name-prefix "$(JOB_NAME)" --start-time $$start_ms --query 'events[*].message' --output text

# --- SageMaker training job (uses Terraform outputs for image and role) ---
sagemaker-launch:
	@uri=$$(terraform -chdir=$(TF_DIR) output -raw ecr_image_uri 2>/dev/null); \
	role=$$(terraform -chdir=$(TF_DIR) output -raw sagemaker_role_arn 2>/dev/null); \
	bucket=$$(terraform -chdir=$(TF_DIR) output -raw s3_training_bucket 2>/dev/null); \
	inst=$${INSTANCE_TYPE}; [ -z "$$inst" ] && inst=$$([ "$(ENV)" = "dev" ] && echo ml.g4dn.xlarge || echo ml.g5.xlarge); \
	if [ -z "$$uri" ] || [ -z "$$role" ]; then echo "Run 'make tf-apply ENV=$(ENV)' first."; exit 1; fi; \
	python $(SCRIPTS)/launch_sagemaker_job.py --image-uri $$uri --role $$role --config $(CONFIG) --instance-type "$$inst" --s3-bucket "$$bucket"

# Full AWS pretraining: infra + push image + launch job for ENV (optional: YES=1, SKIP_TERRAFORM=1, SKIP_PUSH=1)
# Prepend common Docker locations to PATH so "docker" is found when make runs with a minimal environment
aws-pretrain:
	@opts=""; \
	[ "$(YES)" = "1" ] && opts="$$opts --yes"; \
	[ "$(SKIP_TERRAFORM)" = "1" ] && opts="$$opts --skip-terraform"; \
	[ "$(SKIP_PUSH)" = "1" ] && opts="$$opts --skip-push"; \
	PATH="/usr/local/bin:/opt/homebrew/bin:$${PATH}" ENV=$(ENV) CONFIG=$(CONFIG) INSTANCE_TYPE=$${INSTANCE_TYPE} DOCKER=$${DOCKER} $(SCRIPTS)/run_aws_pretrain.sh $$opts
