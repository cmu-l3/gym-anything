#!/usr/bin/env python3
"""Verifier for e2e_study_activation task.

This is a stub verifier. Actual verification is done externally via VLM
checklist evaluation (vlm_checklist.json). The export_result.sh script
collects all ground-truth data from the database for reference.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_e2e_study_activation(traj, env_info, task_info):
    """Stub verifier - real verification is done via external VLM evaluation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file for basic sanity check
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/e2e_study_activation_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export script did not run",
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}",
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Stub: return success to defer to VLM checklist verification
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier - VLM checklist evaluation is external",
    }
