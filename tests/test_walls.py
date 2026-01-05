import json
from pathlib import Path

from goldevidencebench import walls


def _write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload), encoding="utf-8")


def _make_run(
    root: Path,
    name: str,
    *,
    wrong_update_rate: float,
    update_burst_rate: float,
    state_mode: str = "kv",
    distractor_profile: str = "update_burst",
) -> Path:
    run_dir = root / name
    run_dir.mkdir(parents=True, exist_ok=True)
    _write_json(run_dir / "summary.json", {"retrieval": {"wrong_update_rate": wrong_update_rate}})
    _write_json(
        run_dir / "combined.json",
        [
            {
                "config": {"update_burst_rate": update_burst_rate},
                "state_mode": state_mode,
                "distractor_profile": distractor_profile,
            }
        ],
    )
    return run_dir


def test_find_wall_simple(tmp_path: Path) -> None:
    _make_run(tmp_path, "run1", wrong_update_rate=0.05, update_burst_rate=0.1)
    _make_run(tmp_path, "run2", wrong_update_rate=0.2, update_burst_rate=0.4)
    points = walls.load_points(
        runs_dir=tmp_path,
        metric_path="retrieval.wrong_update_rate",
        param_key="update_burst_rate",
        state_mode="kv",
        distractor_profile="update_burst",
    )
    last_ok, wall = walls.find_wall(points, threshold=0.1, direction="gte")
    assert last_ok is not None
    assert wall is not None
    assert last_ok.param == 0.1
    assert wall.param == 0.4


def test_aggregate_points_max(tmp_path: Path) -> None:
    _make_run(tmp_path, "run1", wrong_update_rate=0.05, update_burst_rate=0.1)
    _make_run(tmp_path, "run2", wrong_update_rate=0.2, update_burst_rate=0.1)
    points = walls.load_points(
        runs_dir=tmp_path,
        metric_path="retrieval.wrong_update_rate",
        param_key="update_burst_rate",
    )
    aggregated = walls.aggregate_points(points, mode="max")
    assert len(aggregated) == 1
    assert aggregated[0].metric == 0.2


def test_update_threshold_config(tmp_path: Path) -> None:
    config_path = tmp_path / "checks.json"
    _write_json(
        config_path,
        {
            "checks": [
                {
                    "id": "wall",
                    "summary_path": "runs/foo/summary.json",
                    "metrics": [{"path": "retrieval.wrong_update_rate"}],
                }
            ]
        },
    )
    walls.update_threshold_config(
        config_path=config_path,
        check_id="wall",
        metric_path="retrieval.wrong_update_rate",
        threshold=0.1,
        direction="gte",
    )
    updated = json.loads(config_path.read_text(encoding="utf-8"))
    metric = updated["checks"][0]["metrics"][0]
    assert metric["max"] == 0.1
