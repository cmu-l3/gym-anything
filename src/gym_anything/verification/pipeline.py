from __future__ import annotations

import json
from pathlib import Path
from typing import Optional

from ..api import from_config
from .reports import TaskPipelineVerificationResult


def verify_task_pipeline(
    env_dir: Path,
    task_id: str,
    seed: int = 42,
    use_cache: bool = False,
    cache_level: str = "pre_start",
    use_savevm: bool = False,
) -> TaskPipelineVerificationResult:
    env_dir = Path(env_dir)
    env = None
    stage = "load"
    episode_dir: Optional[str] = None
    try:
        env = from_config(env_dir, task_id=task_id)
        stage = "reset"
        env.reset(
            seed=seed,
            use_cache=use_cache,
            cache_level=cache_level,
            use_savevm=use_savevm,
        )
        episode_dir = str(env.episode_dir) if env.episode_dir else None

        stage = "finalize"
        _, _, _, info = env.step([], mark_done=True)
        verifier = info.get("verifier")
        if verifier is None and env.episode_dir:
            summary_path = Path(env.episode_dir) / "summary.json"
            if summary_path.exists():
                summary = json.loads(summary_path.read_text(encoding="utf-8"))
                verifier = summary.get("verifier")

        return TaskPipelineVerificationResult(
            env_dir=str(env_dir),
            task_id=task_id,
            ok=verifier is not None,
            stage="verifier",
            episode_dir=episode_dir,
            verifier=verifier,
            error=None if verifier is not None else "Verifier result missing from finalize flow",
        )
    except Exception as exc:
        return TaskPipelineVerificationResult(
            env_dir=str(env_dir),
            task_id=task_id,
            ok=False,
            stage=stage,
            episode_dir=episode_dir,
            verifier=None,
            error=str(exc),
        )
    finally:
        if env is not None:
            try:
                env.close()
            except Exception:
                pass


__all__ = ["verify_task_pipeline"]
