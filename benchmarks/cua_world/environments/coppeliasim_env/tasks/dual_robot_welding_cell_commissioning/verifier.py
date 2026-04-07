#!/usr/bin/env python3
"""Stub verifier for dual_robot_welding_cell_commissioning task.

Actual verification is done externally via VLM checklist evaluators.
This file is kept for framework compatibility.
"""

from typing import Dict, Any


def verify_dual_robot_welding_cell_commissioning(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Stub verifier -- real verification is done via external VLM evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier -- VLM evaluation is external",
    }
