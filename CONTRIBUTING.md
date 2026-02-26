# Contributing to Romansh-LLM

Contributions are welcome. This document explains how to get set up, what we care about, and how to send changes.

---

## Scope

**In scope:**

- Dialect-aware language model: data preparation, continued pretraining (QLoRA), config, and documentation.
- Instruction tuning and evaluation tooling (planned).

**Out of scope for now:**

- Full NMT (neural machine translation) pipeline—that requires parallel data and is planned as future work. The repo stays focused on the dialect-aware LM.

---

## How to contribute

- **Bug reports:** Open a [GitHub Issue](https://github.com/alex-is-busy-coding/Romansh-LLM/issues). Include your environment (Python version, uv or pip), steps to reproduce, and relevant error output.
- **Ideas / discussions:** Open an issue first so we can align before larger code changes.
- **Code or docs:** Follow the steps below and open a Pull Request.

---

## Development setup

**Prerequisites:** Python 3.10–3.12, [uv](https://docs.astral.sh/uv/) (recommended) or pip, and one GPU for training.

```bash
git clone https://github.com/alex-is-busy-coding/Romansh-LLM.git
cd Romansh-LLM
uv sync
```

**Sanity check:** Run the pipeline locally (see [README Quick start](README.md#quick-start)):

```bash
make download-data
make pretrain ENV=dev
```

For AWS/SageMaker workflows you’ll need `uv sync --extra aws` and Docker; see the README.

---

## Code layout and style

- **Code:** `src/romansh_llm/` (data, train, config, utils). Scripts live in `scripts/`, config in `configs/`.
- **Style:** Keep formatting consistent with the existing codebase. Type hints for new functions are appreciated.
- **Tests:** Not required for now. Adding small unit tests for data or training helpers is welcome.

---

## Pull request process

1. Branch from `main` (e.g. `fix/issue-42`, `feat/dialect-eval`).
2. Keep PRs focused—one logical change per PR.
3. Update the README or docstrings if you change behaviour or add options.
4. A maintainer will review when possible.

---

## Secrets and data

- **Do not commit** `HF_TOKEN`, AWS credentials, or any other secrets. Use a local `.env` (gitignored) or environment variables.
- **Data:** Training uses [ZurichNLP/quotidiana](https://huggingface.co/datasets/ZurichNLP/quotidiana). If you add or change data-related docs or scripts, please cite the dataset (see README).

---

## License

By contributing, you agree that your contributions will be licensed under the same license as the project ([MIT](LICENSE)).

---

*Romansh-LLM has one clear goal: support Romansh dialects in an LLM. Thank you for helping.*
