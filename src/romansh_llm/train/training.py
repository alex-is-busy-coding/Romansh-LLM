"""Training arguments and runner for CPT."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from datasets import Dataset
from transformers import Trainer, TrainingArguments

from romansh_llm.config import TrainingSettings
from romansh_llm.utils.logging import get_logger

logger = get_logger(__name__)


def build_training_arguments(
    output_dir: str,
    run_name: str,
    training_settings: TrainingSettings,
) -> TrainingArguments:
    """Build TrainingArguments from Pydantic settings."""
    return TrainingArguments(
        output_dir=output_dir,
        run_name=run_name,
        num_train_epochs=training_settings.num_epochs,
        per_device_train_batch_size=training_settings.per_device_train_batch_size,
        per_device_eval_batch_size=training_settings.per_device_train_batch_size,
        gradient_accumulation_steps=training_settings.gradient_accumulation_steps,
        learning_rate=training_settings.learning_rate,
        warmup_ratio=training_settings.warmup_ratio,
        logging_steps=training_settings.logging_steps,
        save_steps=training_settings.save_steps,
        eval_steps=training_settings.eval_steps,
        bf16=training_settings.bf16,
        fp16=training_settings.fp16,
        eval_strategy="steps",
        save_total_limit=2,
        load_best_model_at_end=True,
        report_to=training_settings.report_to,
    )


def run_training(
    model: Any,
    tokenizer: Any,
    train_dataset: Dataset,
    eval_dataset: Dataset,
    training_args: TrainingArguments,
    data_collator: Any,
    final_save_dir: Path | None = None,
) -> None:
    """Run Trainer.train(), then save final model and tokenizer."""
    save_dir = final_save_dir or Path(training_args.output_dir) / "final"
    logger.info(
        "Training: %s epochs, output_dir=%s, save_dir=%s",
        training_args.num_train_epochs,
        training_args.output_dir,
        save_dir,
    )
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_dataset,
        eval_dataset=eval_dataset,
        data_collator=data_collator,
    )
    trainer.train()
    logger.info("Saving model and tokenizer to %s", save_dir)
    trainer.save_model(save_dir)
    tokenizer.save_pretrained(save_dir)
