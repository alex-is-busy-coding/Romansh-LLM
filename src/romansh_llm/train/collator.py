"""Data collators for training."""

from __future__ import annotations

import torch


class CausalLMCollator:
    """Collate pre-tokenized sequences (input_ids, attention_mask, labels) into batches."""

    def __call__(self, examples: list[dict]) -> dict[str, torch.Tensor]:
        batch = {}
        for key in ("input_ids", "attention_mask", "labels"):
            batch[key] = torch.tensor([ex[key] for ex in examples], dtype=torch.long)
        return batch
