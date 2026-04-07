#!/usr/bin/env python3
"""Stub verifier for boiler_drum_3element_control task.

Actual verification is done externally via VLM checklist evaluators.
This stub performs basic file-existence and anti-gaming checks only.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/boiler_drum_result.json"


def verify_boiler_drum_3element_control(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Try to read the result JSON produced by export_result.ps1
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result JSON not found — project was not saved or export failed.",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # Anti-gaming: project must exist and be created during task
    if not result.get("project_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Project file not found — agent did not save the project.",
        }
    if not result.get("file_created_during_task"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Project file predates task start (do-nothing detected).",
        }

    # Anti-gaming: check for decommissioned tag TT_100
    binary_contexts = result.get("binary_contexts", {})
    if "TT_100" in binary_contexts:
        tags = result.get("tags", [])
        tag_names = {str(t.get("name", "")).strip().upper() for t in tags}
        if "TT_100" in tag_names:
            return {
                "passed": False,
                "score": 10,
                "feedback": "DECOMMISSIONED tag TT_100 was configured — score capped.",
            }

    # Stub: pass with full score — real scoring via VLM checklist
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier — VLM checklist evaluation is external.",
    }
