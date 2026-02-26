"""Build tokenizer and QLoRA model for CPT."""

from __future__ import annotations

import torch
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    BitsAndBytesConfig,
    PreTrainedModel,
    PreTrainedTokenizerBase,
)
from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training

from romansh_llm.config import QLoraSettings
from romansh_llm.utils.logging import get_logger

logger = get_logger(__name__)


def build_tokenizer(model_name: str) -> PreTrainedTokenizerBase:
    """Load tokenizer and set pad token and padding side for causal LM."""
    logger.info("Loading tokenizer: %s", model_name)
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    if tokenizer.pad_token_id is None:
        tokenizer.pad_token_id = tokenizer.eos_token_id
    tokenizer.padding_side = "right"
    return tokenizer


def build_qlora_model(
    model_name: str,
    qlora_settings: QLoraSettings,
) -> PreTrainedModel:
    """Load base model in 4-bit, apply LoRA, return PEFT model."""
    logger.info(
        "Loading QLoRA model: %s (r=%s, alpha=%s, target_modules=%s)",
        model_name,
        qlora_settings.lora_r,
        qlora_settings.lora_alpha,
        qlora_settings.target_modules,
    )
    compute_dtype = (
        torch.bfloat16
        if qlora_settings.bnb_4bit_compute_dtype == "bfloat16"
        else torch.float16
    )
    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type=qlora_settings.bnb_4bit_quant_type,
        bnb_4bit_compute_dtype=compute_dtype,
        bnb_4bit_use_double_quant=True,
    )
    model = AutoModelForCausalLM.from_pretrained(
        model_name,
        quantization_config=bnb_config,
        device_map="auto",
        trust_remote_code=True,
    )
    model = prepare_model_for_kbit_training(model)

    target_modules = [
        s.strip() for s in qlora_settings.target_modules.split(",")
    ]
    lora_config = LoraConfig(
        r=qlora_settings.lora_r,
        lora_alpha=qlora_settings.lora_alpha,
        lora_dropout=qlora_settings.lora_dropout,
        target_modules=target_modules,
        bias="none",
        task_type="CAUSAL_LM",
    )
    return get_peft_model(model, lora_config)
