#!/usr/bin/env python3
"""
Stub verifier for rd_department_onboarding task.

Primary verification is done via vlm_checklist.json (VLM-based evaluation).
This stub is provided for the programmatic verification interface.
"""

import json
import os
import tempfile


def verify_rd_department_onboarding(traj, env_info, task_info):
    """Stub verifier — returns 0 score. Use VLM checklist for actual evaluation."""
    return {
        "passed": False,
        "score": 0,
        "feedback": "Stub verifier. Use VLM checklist evaluation for scoring.",
    }
