"""Load config from YAML and validate with Pydantic settings."""

from __future__ import annotations

from contextvars import ContextVar
from pathlib import Path
from typing import Any, Literal

import yaml
from pydantic import BaseModel, Field, field_validator, model_validator
from pydantic.fields import FieldInfo
from pydantic_settings import BaseSettings, PydanticBaseSettingsSource, SettingsConfigDict

_config_path_ctx: ContextVar[Path | None] = ContextVar("config_path", default=None)


class ModelSettings(BaseModel):
    """Base model and tokenizer to use for CPT."""

    name_or_path: str = Field(
        default="meta-llama/Llama-3.2-3B",
        min_length=1,
        description="Hugging Face model ID or path to load (e.g. meta-llama/Llama-3.2-1B).",
    )


class PathsSettings(BaseModel):
    """Paths for data, checkpoints, and run naming."""

    data_dir: str = Field(default="data", description="Directory for cached or prepared data.")
    output_dir: str = Field(default="output/cpt", description="Directory for checkpoints and logs.")
    run_name: str = Field(
        default="rhaeto-llm-cpt",
        min_length=1,
        description="Name of the run (e.g. for wandb or logs).",
    )


class DataSettings(BaseModel):
    """Dataset and preprocessing options for quotidiana."""

    dataset_name: str = Field(
        default="ZurichNLP/quotidiana",
        min_length=1,
        description="Hugging Face dataset ID for the Romansh corpus.",
    )
    subsets: list[str] = Field(
        default_factory=lambda: ["1997_2008", "2021_2025"],
        min_length=1,
        description="Quotidiana subsets to load (e.g. 1997_2008, 2021_2025).",
    )
    max_length: int = Field(
        default=1024,
        ge=8,
        le=65536,
        description="Maximum sequence length in tokens (chunk size for CPT).",
    )
    val_ratio: float = Field(
        default=0.02,
        ge=0.0,
        le=1.0,
        description="Fraction of data to use for validation (stratified by dialect).",
    )


class DialectTagsSettings(BaseModel):
    """Dialect tag format for conditioning the model on Romansh variety."""

    use_dialect_tags: bool = Field(
        default=True,
        description="Whether to prepend a dialect tag to each document/chunk.",
    )
    dialect_tag_format: str = Field(
        default="[{variety}]\n\n",
        min_length=1,
        description="Format string for the tag; {variety} is replaced by the dataset variety (e.g. rm-vallader).",
    )

    @field_validator("dialect_tag_format")
    @classmethod
    def dialect_tag_contains_variety(cls, v: str) -> str:
        if "{variety}" not in v:
            raise ValueError("dialect_tag_format must contain the placeholder '{variety}'")
        return v


class QLoraSettings(BaseModel):
    """QLoRA (4-bit + LoRA) hyperparameters."""

    lora_r: int = Field(default=64, ge=1, le=256, description="LoRA rank.")
    lora_alpha: int = Field(default=16, ge=1, description="LoRA alpha (scaling).")
    lora_dropout: float = Field(default=0.05, ge=0.0, le=1.0, description="LoRA dropout.")
    target_modules: str = Field(
        default="q_proj,v_proj,k_proj,o_proj",
        min_length=1,
        description="Comma-separated list of module names to apply LoRA to.",
    )
    bnb_4bit_compute_dtype: Literal["bfloat16", "float16"] = Field(
        default="bfloat16",
        description="Compute dtype for 4-bit quantized model (bfloat16 or float16).",
    )
    bnb_4bit_quant_type: str = Field(
        default="nf4",
        min_length=1,
        description="Quantization type for 4-bit (e.g. nf4).",
    )


class TrainingSettings(BaseModel):
    """Training loop and logging options."""

    num_epochs: int = Field(default=3, ge=1, description="Number of training epochs.")
    per_device_train_batch_size: int = Field(
        default=2,
        ge=1,
        description="Batch size per device for training.",
    )
    gradient_accumulation_steps: int = Field(
        default=8,
        ge=1,
        description="Gradient accumulation steps (effective batch = batch_size * accumulation * devices).",
    )
    learning_rate: float = Field(default=2.0e-5, gt=0.0, description="Peak learning rate.")
    warmup_ratio: float = Field(
        default=0.03,
        ge=0.0,
        le=1.0,
        description="Fraction of steps for linear warmup.",
    )
    logging_steps: int = Field(default=10, ge=1, description="Log loss every N steps.")
    save_steps: int = Field(default=500, ge=1, description="Save checkpoint every N steps.")
    eval_steps: int = Field(default=500, ge=1, description="Run evaluation every N steps.")
    bf16: bool = Field(default=True, description="Use bfloat16 for training.")
    fp16: bool = Field(default=False, description="Use float16 for training.")
    report_to: Literal["none", "wandb"] = Field(
        default="none",
        description="Where to report metrics: 'none' or 'wandb'. For wandb, install with [logging] and run wandb login.",
    )
    wandb_project: str | None = Field(
        default=None,
        description="Wandb project name (used when report_to is wandb).",
    )

    @model_validator(mode="after")
    def at_most_one_half_precision(self) -> TrainingSettings:
        if self.bf16 and self.fp16:
            raise ValueError("At most one of bf16 and fp16 can be True")
        return self


class _YamlFileSettingsSource(PydanticBaseSettingsSource):
    """Custom settings source: load YAML from path in _config_path_ctx (set by load_settings)."""

    def __init__(self, settings_cls: type[BaseSettings]) -> None:
        super().__init__(settings_cls)
        self._data: dict[str, Any] | None = None

    def _ensure_loaded(self) -> None:
        if self._data is not None:
            return
        path = _config_path_ctx.get()
        if path is not None:
            self._data = load_config(path, base_dir=None)
        else:
            self._data = {}

    def get_field_value(self, field: FieldInfo, field_name: str) -> tuple[Any, str, bool]:
        self._ensure_loaded()
        value = self._data.get(field_name) if self._data else None
        if value is not None:
            return (value, field_name, False)
        return (None, "", False)

    def __call__(self) -> dict[str, Any]:
        self._ensure_loaded()
        return {k: v for k, v in (self._data or {}).items() if v is not None}


class AppSettings(BaseSettings):
    """Root settings loaded from YAML (and optionally env overrides)."""

    model_config = SettingsConfigDict(env_nested_delimiter="__", extra="ignore")

    model: ModelSettings = Field(default_factory=ModelSettings, description="Base model and tokenizer.")
    paths: PathsSettings = Field(default_factory=PathsSettings, description="Paths and run name.")
    data: DataSettings = Field(default_factory=DataSettings, description="Dataset and preprocessing.")
    dialect_tags: DialectTagsSettings = Field(
        default_factory=DialectTagsSettings,
        description="Dialect tag format for conditioning.",
    )
    qlora: QLoraSettings = Field(default_factory=QLoraSettings, description="QLoRA hyperparameters.")
    training: TrainingSettings = Field(default_factory=TrainingSettings, description="Training and logging.")

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        # First = highest priority: init → env → dotenv → YAML (base) → secrets
        return (
            init_settings,
            env_settings,
            dotenv_settings,
            _YamlFileSettingsSource(settings_cls),
            file_secret_settings,
        )


def _deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    """Recursively merge overlay into base. Dicts are merged; other values are overwritten by overlay."""
    out = dict(base)
    for k, v in overlay.items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def load_config(path: str | Path, base_dir: Path | None = None) -> dict[str, Any]:
    """Load raw config from a YAML file. If path is relative and base_dir is set, resolve against base_dir.
    If the file lives in a directory that also contains common.yaml, common is loaded first and merged (env file overrides)."""
    path = Path(path)
    if not path.is_absolute() and base_dir is not None:
        path = base_dir / path
    path = path.resolve()
    with open(path, encoding="utf-8") as f:
        raw = yaml.safe_load(f) or {}
    common_path = path.parent / "common.yaml"
    if common_path.exists() and common_path != path:
        with open(common_path, encoding="utf-8") as f:
            common = yaml.safe_load(f) or {}
        raw = _deep_merge(common, raw)
    return raw


def load_settings(path: str | Path, base_dir: Path | None = None) -> AppSettings:
    """Load config from YAML (with common merge) and return validated Pydantic settings.
    Uses pydantic-settings: YAML is loaded via a custom source; env vars can override (e.g. PATHS__OUTPUT_DIR)."""
    path = Path(path)
    if not path.is_absolute() and base_dir is not None:
        path = base_dir / path
    path = path.resolve()
    token = _config_path_ctx.set(path)
    try:
        return AppSettings()
    finally:
        _config_path_ctx.reset(token)
