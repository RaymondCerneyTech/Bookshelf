from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt


def load_results(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return data if isinstance(data, list) else [data]


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("Usage: python scripts/plot_results.py RESULTS.json OUT_DIR")
        return 1
    res_path = Path(argv[0])
    out_dir = Path(argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = load_results(res_path)

    def scatter(metric: str, name: str) -> None:
        xs = []
        ys = []
        labels = []
        for r in rows:
            eff = r.get("efficiency", {})
            tokens_per_q = eff.get("tokens_per_q", 0)
            val = r.get("metrics", {}).get(metric)
            if val is None:
                continue
            xs.append(tokens_per_q)
            ys.append(val)
            labels.append(f"{r.get('baseline','') or r.get('adapter','')} {r.get('state_mode','')}")
        if not xs:
            return
        plt.figure()
        plt.scatter(xs, ys)
        for i, lbl in enumerate(labels):
            plt.annotate(lbl, (xs[i], ys[i]))
        plt.xlabel("tokens/query")
        plt.ylabel(metric)
        plt.title(name)
        plt.grid(True, linestyle="--", alpha=0.3)
        plt.tight_layout()
        plt.savefig(out_dir / f"{metric}.png", dpi=150)
        plt.close()

    scatter("exact_acc", "Accuracy vs tokens/query")
    scatter("instruction_gap", "Instruction gap vs tokens/query")
    scatter("twin_flip_rate", "Twin flip vs tokens/query")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
