# Romansh-LLM: CPT with QLoRA. GPU image (CUDA 12.1 + PyTorch).
# For SageMaker, build with: docker build --platform linux/amd64 ...
FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

WORKDIR /app

# Install system deps if needed (optional)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy project
COPY pyproject.toml ./
COPY configs ./configs/
COPY src ./src/
COPY scripts ./scripts/

# Install uv (avoids pip hash-mismatch issues when PyPI re-serves packages)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Pin torch/torchvision from PyTorch CUDA index so they match (avoids "operator torchvision::nms does not exist")
RUN pip install --no-cache-dir torch==2.2.0 torchvision==0.17.0 --index-url https://download.pytorch.org/whl/cu121

# Install project and deps with uv (no lock file copied = no hash verification; prevents "THESE PACKAGES DO NOT MATCH THE HASHES" from pip)
RUN uv pip install --system --no-cache -e . \
    && chmod +x /app/scripts/sagemaker_train.sh /app/scripts/docker_entry.sh

# When SM_MODEL_DIR is set (SageMaker), entry runs sagemaker_train.sh; otherwise runs pretrain with CMD.
ENTRYPOINT ["/app/scripts/docker_entry.sh"]
CMD ["--config", "/app/configs/prod.yaml"]
