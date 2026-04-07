#!/usr/bin/env python3
"""
Verifier for setup_iec62304_project task (arch-to-test coverage audit).

Stub verifier — primary verification is done via vlm_checklist_verifier.
This verifier checks basic output file existence and structure.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_setup_iec62304_project(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load task result metadata from export_result.sh
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {e}"}
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    score = 0
    feedback_parts = []

    # 1. Output file exists (10 pts)
    if task_result.get("output_exists", False):
        score += 10
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Created during task window (5 pts)
    if task_result.get("created_during_task", False):
        score += 5
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("Warning: file not created during task window")

    # 3. Valid JSON structure (10 pts)
    output_content = task_result.get("output_content", "")
    try:
        report = json.loads(output_content)
        if isinstance(report, dict) and "components" in report:
            score += 10
            feedback_parts.append("Valid JSON with 'components' key")
        else:
            feedback_parts.append("JSON missing 'components' key")
    except (json.JSONDecodeError, TypeError):
        feedback_parts.append("Invalid JSON in output file")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 4. Has summary section (5 pts)
    if "summary" in report:
        score += 5
        feedback_parts.append("Has summary section")
    else:
        feedback_parts.append("Missing summary section")

    # 5. App was running (5 pts)
    if task_result.get("app_running", False):
        score += 5
        feedback_parts.append("ReqView running at task end")

    passed = score >= 25
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
