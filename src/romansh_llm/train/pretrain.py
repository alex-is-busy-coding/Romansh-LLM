"""
Continued pretraining (CPT) with QLoRA on dialect-tagged quotidiana.
Entry point: loads config, builds model and data, runs training.
"""

from __future__ import annotations

import argparse
import importlib.metadata
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from romansh_llm.config import load_settings
from romansh_llm.data.load_quotidiana import load_quotidiana
from romansh_llm.train.collator import CausalLMCollator
from romansh_llm.train.model import build_tokenizer, build_qlora_model
from romansh_llm.utils.logging import configure_logging, get_logger
from romansh_llm.train.training import build_training_arguments, run_training

logger = get_logger(__name__)


def _get_version() -> str:
    try:
        return importlib.metadata.version("romansh-llm")
    except importlib.metadata.PackageNotFoundError:
        return "0.0.0+dev"


def _ensure_hf_auth() -> None:
    """Log in to Hugging Face if HF_TOKEN or HUGGING_FACE_HUB_TOKEN is set (for gated models)."""
    token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    if token:
        from huggingface_hub import login
        login(token=token)
        logger.debug("Hugging Face authentication enabled (token from env)")


def main() -> None:
    from dotenv import load_dotenv
    load_dotenv(REPO_ROOT / ".env")

    parser = argparse.ArgumentParser(description="CPT with QLoRA on quotidiana.")
    parser.add_argument(
        "--version",
        "-V",
        action="version",
        version=f"%(prog)s {_get_version()}",
        help="Show version and exit.",
    )
    parser.add_argument(
        "--config",
        type=str,
        default="configs/prod.yaml",
        help="Path to config YAML (relative to repo root)",
    )
    parser.add_argument(
        "--log-level",
        type=str,
        default=None,
        metavar="LEVEL",
        help="Logging level (DEBUG, INFO, WARNING, ERROR). Default: LOG_LEVEL env or INFO.",
    )
    args = parser.parse_args()

    configure_logging(level=args.log_level)

    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = REPO_ROOT / config_path
    settings = load_settings(config_path, base_dir=None)
    logger.info("Loaded config from %s", config_path)
    logger.info("Model: %s, output_dir: %s", settings.model.name_or_path, settings.paths.output_dir)

    sm_model_dir = os.environ.get("SM_MODEL_DIR")
    if sm_model_dir:
        settings.paths.output_dir = sm_model_dir
        logger.info("SageMaker: using SM_MODEL_DIR=%s for output", sm_model_dir)

    _ensure_hf_auth()

    if settings.training.report_to == "wandb" and settings.training.wandb_project:
        os.environ.setdefault("WANDB_PROJECT", settings.training.wandb_project)
        logger.info("Reporting to wandb project: %s", settings.training.wandb_project)

    logger.info("Loading tokenizer and model...")
    tokenizer = build_tokenizer(settings.model.name_or_path)
    model = build_qlora_model(settings.model.name_or_path, settings.qlora)
    logger.info("Loading dataset...")
    train_dataset, eval_dataset = load_quotidiana(settings, tokenizer)
    logger.info(
        "Train examples: %s, eval examples: %s",
        len(train_dataset),
        len(eval_dataset),
    )

    training_args = build_training_arguments(
        settings.paths.output_dir,
        settings.paths.run_name,
        settings.training,
    )
    collator = CausalLMCollator()
    logger.info("Starting training (run_name=%s)", settings.paths.run_name)
    run_training(
        model,
        tokenizer,
        train_dataset,
        eval_dataset,
        training_args,
        collator,
        final_save_dir=Path(settings.paths.output_dir) / "final",
    )
    logger.info("Training complete. Model and tokenizer saved to %s/final", settings.paths.output_dir)


if __name__ == "__main__":
    main()
