#!/usr/bin/env python3
"""
Stub verifier for cml_polypharmacy_drug_selection_consultation task.

This task is verified externally via vlm_checklist_verifier.
The stub performs minimal file-existence checks only.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cml_polypharmacy_consultation(traj, env_info, task_info):
    """
    Stub verifier — returns passed=True if the report file was created
    during the task. Full scoring is handled by external VLM checklist
    verifier.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON written by export_result.sh
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve task result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    file_exists = result.get("file_exists", False)
    file_created_during_task = result.get("file_created_during_task", False)
    content = result.get("file_content", "")

    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file /sdcard/Download/cml_drug_safety_report.txt not found."
        }

    if not file_created_during_task:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file exists but was not created during the task (anti-gaming)."
        }

    # Minimal content length check — a real report should be at least ~100 chars
    if len(content) < 50:
        return {
            "passed": False,
            "score": 10,
            "feedback": "Report file created but content is too short to be a valid consultation report."
        }

    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier: report file created during task. Full evaluation via VLM checklist."
    }
