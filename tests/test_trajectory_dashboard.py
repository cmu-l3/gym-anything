import pickle
from pathlib import Path
from urllib.parse import quote

from PIL import Image

from gym_anything.dashboards.trajectory import create_app


def _create_sample_run(root: Path) -> Path:
    run_dir = root / "exp_alpha" / "model_orbit" / "task_canvas" / "run_0"
    run_dir.mkdir(parents=True)

    messages = [
        {"role": "user", "content": "Open the canvas and draw a square."},
        {"role": "assistant", "content": "I will inspect the screen and click the toolbar."},
    ]
    info = {
        "reason": "completed",
        "verifier": {"passed": True, "score": 100, "feedback": "square present"},
    }

    with (run_dir / "messages.pkl").open("wb") as handle:
        pickle.dump(messages, handle)
    with (run_dir / "info.pkl").open("wb") as handle:
        pickle.dump(info, handle)

    Image.new("RGB", (32, 24), (220, 90, 70)).save(run_dir / "observation_0.png")
    return run_dir


def test_trajectory_dashboard_lists_runs_and_details(tmp_path):
    runs_root = tmp_path / "all_runs"
    run_dir = _create_sample_run(runs_root)

    app = create_app(runs_root=runs_root)
    client = app.test_client()

    index_response = client.get("/")
    assert index_response.status_code == 200
    assert b"Trajectory Viewer" in index_response.data

    runs_response = client.get("/api/runs")
    assert runs_response.status_code == 200
    runs_payload = runs_response.get_json()
    assert runs_payload["runs_root"] == str(runs_root.resolve())
    assert len(runs_payload["runs"]) == 1
    assert runs_payload["runs"][0]["task"] == "task_canvas"

    detail_response = client.get(
        f"/api/run?path={quote(str(run_dir.resolve()), safe='')}"
    )
    assert detail_response.status_code == 200
    detail_payload = detail_response.get_json()
    assert detail_payload["summary"]["success"] is True
    assert detail_payload["summary"]["score"] == 100
    assert detail_payload["task_description"] == "Open the canvas and draw a square."
    assert detail_payload["steps"][0]["observation_path"].endswith("observation_0.png")

    image_response = client.get(
        f"/api/image?path={quote(str(run_dir.resolve() / 'observation_0.png'), safe='')}"
    )
    assert image_response.status_code == 200
    assert image_response.mimetype == "image/png"


def test_trajectory_dashboard_rejects_unknown_run_paths(tmp_path):
    runs_root = tmp_path / "all_runs"
    _create_sample_run(runs_root)

    app = create_app(runs_root=runs_root)
    client = app.test_client()

    missing_response = client.get(
        f"/api/run?path={quote(str(tmp_path / 'outside' / 'run_0'), safe='')}"
    )
    assert missing_response.status_code == 404
    assert "indexed runs root" in missing_response.get_json()["error"]

    outside_image = client.get(
        f"/api/image?path={quote(str(tmp_path / 'outside' / 'frame.png'), safe='')}"
    )
    assert outside_image.status_code == 404
