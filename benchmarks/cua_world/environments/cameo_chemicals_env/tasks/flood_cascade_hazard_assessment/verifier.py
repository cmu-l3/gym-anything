#!/usr/bin/env python3
"""Stub verifier for flood_cascade_hazard_assessment task.

Actual verification is done externally via VLM checklist evaluators.
The export_result.sh post-task hook extracts keyword signals into
/tmp/flood_cascade_hazard_assessment_result.json for reference.
"""


def verify_flood_cascade_hazard_assessment(traj, env_info, task_info):
    """Stub verifier - real verification is done via external VLM evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier - VLM evaluation is external",
    }
