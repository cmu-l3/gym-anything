#!/usr/bin/env python3
"""Stub verifier for annual_wellness_specialist_followup task.

Actual verification is done externally via VLM checklist evaluators.
The export_result.sh script collects all DB state into
/tmp/annual_wellness_specialist_followup_result.json for programmatic
scoring if needed in the future.
"""


def verify_annual_wellness_specialist_followup(traj, env_info, task_info):
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier — VLM evaluation is external",
    }
