#!/usr/bin/env python3
"""
Verifier for Fifteen Puzzle Solve task.

The agent must navigate to The Fifteen Game in GCompris, advance to Level 3
(4x4 numbered tiles), and solve the sliding tile puzzle so that tiles 1-15
are in order with the blank in the bottom-right corner.

Verification is primarily done via VLM checklist (vlm_checklist_verifier).
This programmatic verifier is a stub for framework compatibility.
"""

import logging

logger = logging.getLogger(__name__)


def verify_fifteen_puzzle_solve(traj, env_info, task_info):
    """Stub verifier - real evaluation via vlm_checklist_verifier."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier (use VLM checklist)"}
