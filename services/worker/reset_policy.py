from __future__ import annotations

import time
from typing import Dict, Optional

from gym_anything.runtime.post_reset import apply_post_reset_setup


DEFAULT_WORKER_RESET_POLICY = "core"
BASELINE_SETUP_WORKER_RESET_POLICY = "baseline_setup"
SUPPORTED_WORKER_RESET_POLICIES = (
    DEFAULT_WORKER_RESET_POLICY,
    BASELINE_SETUP_WORKER_RESET_POLICY,
)


class InvalidResetPolicyError(ValueError):
    """Raised when a worker reset policy is not recognized."""


def apply_worker_reset_policy(
    env,
    policy: str,
    *,
    fullscreen_steps: int = 50,
    logger=None,
) -> Dict[str, float]:
    if policy == DEFAULT_WORKER_RESET_POLICY:
        return {
            "apply_reset_policy": 0.0,
            "setup_env": 0.0,
            "disable_crash_reporter": 0.0,
        }

    if policy != BASELINE_SETUP_WORKER_RESET_POLICY:
        supported = ", ".join(SUPPORTED_WORKER_RESET_POLICIES)
        raise InvalidResetPolicyError(
            f"Unsupported worker reset policy {policy!r}; supported policies: {supported}"
        )

    policy_start = time.time()
    timings: Dict[str, float] = {}

    setup_start = time.time()
    apply_post_reset_setup(env, setup_code="auto", steps=fullscreen_steps)
    timings["setup_env"] = time.time() - setup_start

    crash_start = time.time()
    try:
        env._runner.exec("sudo sed -i 's/^enabled=.*/enabled=0/' /etc/default/apport")
        env._runner.exec("sudo systemctl stop apport.service 2>/dev/null || sudo service apport stop")
        env._runner.exec("sudo systemctl disable apport.service 2>/dev/null || true")
        env._runner.exec("sudo systemctl disable --now whoopsie.service 2>/dev/null || true")
    except Exception as exc:
        if logger is not None:
            logger.warning("Failed to apply baseline crash-reporter disable sequence: %s", exc)
    timings["disable_crash_reporter"] = time.time() - crash_start
    timings["apply_reset_policy"] = time.time() - policy_start
    return timings


__all__ = [
    "DEFAULT_WORKER_RESET_POLICY",
    "BASELINE_SETUP_WORKER_RESET_POLICY",
    "SUPPORTED_WORKER_RESET_POLICIES",
    "InvalidResetPolicyError",
    "apply_worker_reset_policy",
]
