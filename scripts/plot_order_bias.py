import argparse
import csv
from pathlib import Path

import matplotlib.pyplot as plt


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--in-csv",
        type=Path,
        default=Path("runs/summary_all.csv"),
        help="Input summary_all.csv path.",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("docs/figures/order_bias_s5q24_llm.png"),
        help="Output image path.",
    )
    parser.add_argument(
        "--pattern",
        type=str,
        default="order_bias_",
        help="Substring to match in run_name.",
    )
    parser.add_argument(
        "--metric",
        type=str,
        default="selection_rate",
        choices=("selection_rate", "accuracy_when_gold_present", "value_acc"),
        help="Metric to plot.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rows = []
    with args.in_csv.open("r", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            run_name = row.get("run_name", "")
            if args.pattern not in run_name:
                continue
            if not run_name.endswith("s5q24_llm"):
                continue
            rows.append(row)

    if not rows:
        raise SystemExit(
            f"No rows matched pattern={args.pattern!r} ending with s5q24_llm in {args.in_csv}"
        )

    order_map = {}
    for row in rows:
        run_name = row.get("run_name", "")
        order = run_name.split("order_bias_")[1].split("_k4")[0]
        try:
            order_map[order] = float(row[args.metric])
        except (TypeError, ValueError):
            order_map[order] = 0.0

    orders = ["gold_first", "gold_middle", "gold_last", "shuffle"]
    values = [order_map.get(order, 0.0) for order in orders]

    fig, ax = plt.subplots(figsize=(6.8, 3.8))
    bars = ax.bar(orders, values, color="#3b6ea8")
    ax.set_ylim(0, 1.05)
    ax.set_yticks([0.0, 0.25, 0.5, 0.75, 1.0])
    ax.set_ylabel(args.metric)
    ax.set_title("Order bias (LLM-only, k=4, same_key, s5q24)")
    ax.grid(axis="y", linestyle="--", linewidth=0.5, alpha=0.6)
    for bar, value in zip(bars, values):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            value + 0.02,
            f"{value:.2f}",
            ha="center",
            va="bottom",
            fontsize=9,
        )
    fig.tight_layout()

    args.out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.out, dpi=200)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
