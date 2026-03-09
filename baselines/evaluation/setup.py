from __future__ import annotations

from typing import Optional

from gym_anything.runtime.post_reset import apply_post_reset_setup


def setup_env(env, setup_code: str = "auto", steps: Optional[int] = None, env_dir: Optional[str] = None):
    return apply_post_reset_setup(env, setup_code=setup_code, steps=steps, env_dir=env_dir)


__all__ = ["setup_env"]
