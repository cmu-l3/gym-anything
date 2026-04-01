"""Internal multi-process batch runner (not part of the public API).

This module provides a simple fire-and-forget parallel runner for running
multiple environment instances. It is not exported from gym_anything.__init__.
"""

from __future__ import annotations

import multiprocessing as mp
from typing import Any, Dict, List, Optional

from .api import make
from .specs import EnvSpec, TaskSpec


def _worker(spec_dict: Dict[str, Any], task_dict: Optional[Dict[str, Any]], seed: int, steps: int, idx: int):
    env = make(spec_dict, task_dict)
    env.reset(seed=seed)
    for _ in range(steps):
        _, _, done, _ = env.step({})
        if done:
            break
    env.close()


class SubprocVectorEnv:
    def __init__(self, n: int, env_spec: EnvSpec, task_spec: Optional[TaskSpec] = None):
        self.n = n
        self.env_spec = env_spec
        self.task_spec = task_spec

    def run(self, steps: int = 10, seed: int = 42) -> None:
        jobs: List[mp.Process] = []
        for i in range(self.n):
            p = mp.Process(
                target=_worker,
                args=(self.env_spec.__dict__, self.task_spec.__dict__ if self.task_spec else None, seed + i, steps, i),
            )
            p.start()
            jobs.append(p)
        for p in jobs:
            p.join()

