from __future__ import annotations

import argparse
from pathlib import Path

from goldevidencebench.thresholds import evaluate_checks, format_issues, load_config


def main() -> int:
    parser = argparse.ArgumentParser(description="Check use-case thresholds from summary.json files.")
    parser.add_argument(
        "--config",
        type=Path,
        default=Path("configs/usecase_checks.json"),
        help="Path to threshold config JSON.",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path("."),
        help="Root for summary_path entries (default: repo root).",
    )
    args = parser.parse_args()

    config = load_config(args.config)
    issues, error_count = evaluate_checks(config, root=args.root)
    print(format_issues(issues))
    return 1 if error_count else 0


if __name__ == "__main__":
    raise SystemExit(main())
