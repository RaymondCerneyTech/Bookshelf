from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from goldevidencebench.thresholds import load_config


@dataclass(frozen=True)
class WallPoint:
    run_dir: Path
    param: float
    metric: float
    state_mode: str | None
    distractor_profile: str | None


def _read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _get_path(data: dict[str, Any], path: str) -> Any:
    current: Any = data
    for part in path.split("."):
        if not isinstance(current, dict):
            return None
        current = current.get(part)
        if current is None:
            return None
    return current


def _as_float(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).strip())
    except ValueError:
        return None


def _load_payload(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    data = _read_json(path)
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and item.get("config"):
                return item
        return None
    if isinstance(data, dict):
        return data
    return None


def load_points(
    *,
    runs_dir: Path,
    metric_path: str,
    param_key: str,
    state_mode: str | None = None,
    distractor_profile: str | None = None,
) -> list[WallPoint]:
    points: list[WallPoint] = []
    for summary_path in runs_dir.rglob("summary.json"):
        summary = _read_json(summary_path)
        if not isinstance(summary, dict):
            continue
        metric = _as_float(_get_path(summary, metric_path))
        if metric is None:
            continue
        run_dir = summary_path.parent
        payload = _load_payload(run_dir / "combined.json") or _load_payload(run_dir / "results.json")
        if not payload:
            continue
        config = payload.get("config", {})
        param = _as_float(config.get(param_key))
        if param is None:
            continue
        mode = payload.get("state_mode") or config.get("state_mode")
        profile = payload.get("distractor_profile") or config.get("distractor_profile")
        if state_mode and mode != state_mode:
            continue
        if distractor_profile and profile != distractor_profile:
            continue
        points.append(
            WallPoint(
                run_dir=run_dir,
                param=param,
                metric=metric,
                state_mode=mode,
                distractor_profile=profile,
            )
        )
    return points


def aggregate_points(points: Iterable[WallPoint], *, mode: str) -> list[WallPoint]:
    grouped: dict[float, list[WallPoint]] = {}
    for point in points:
        grouped.setdefault(point.param, []).append(point)
    aggregated: list[WallPoint] = []
    for param, items in grouped.items():
        if mode == "min":
            best = min(items, key=lambda p: p.metric)
        else:
            best = max(items, key=lambda p: p.metric)
        aggregated.append(best)
    return aggregated


def find_wall(
    points: Iterable[WallPoint],
    *,
    threshold: float,
    direction: str,
) -> tuple[WallPoint | None, WallPoint | None]:
    ordered = sorted(points, key=lambda p: p.param)
    last_ok: WallPoint | None = None
    for point in ordered:
        if direction == "gte" and point.metric >= threshold:
            return last_ok, point
        if direction == "lte" and point.metric <= threshold:
            return last_ok, point
        last_ok = point
    return last_ok, None


def update_threshold_config(
    *,
    config_path: Path,
    check_id: str,
    metric_path: str,
    threshold: float,
    direction: str,
) -> None:
    config = load_config(config_path)
    checks = config.get("checks", [])
    check = next((c for c in checks if str(c.get("id")) == check_id), None)
    if check is None:
        raise ValueError(f"check id '{check_id}' not found in {config_path}")
    metrics = check.setdefault("metrics", [])
    entry = next((m for m in metrics if str(m.get("path")) == metric_path), None)
    if entry is None:
        entry = {"path": metric_path}
        metrics.append(entry)
    if direction == "gte":
        entry["max"] = float(threshold)
    else:
        entry["min"] = float(threshold)
    config_path.write_text(json.dumps(config, indent=2), encoding="utf-8")
