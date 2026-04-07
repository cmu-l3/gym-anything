#!/usr/bin/env python3
"""Verifier stub for debug_and_complete_spreadsheet_engine.

Primary verification is done via VLM checklist verifier.
This programmatic verifier reads the export_result.sh output
and provides a basic score based on test pass count.
"""
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_debug_and_complete_spreadsheet_engine(traj, env_info, task_info):
    """Verify the spreadsheet engine task completion.

    Reads /tmp/debug_and_complete_spreadsheet_engine_result.json
    and scores based on number of tests passing.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(
            "/tmp/debug_and_complete_spreadsheet_engine_result.json",
            temp_file.name
        )
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result JSON: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Disqualify if test or data files were modified
    if result.get("tests_modified", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Test files were modified — disqualified."
        }
    if result.get("data_modified", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Data files were modified — disqualified."
        }

    tests_passed = result.get("tests_passed", 0)
    total_tests = result.get("total_tests", 35)

    if total_tests == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No tests were found or executed."
        }

    score = round((tests_passed / total_tests) * 100)
    passed = tests_passed >= 30
    feedback = f"{tests_passed}/{total_tests} tests passing ({score}%)"

    if passed:
        feedback += " — PASSED (threshold: 30/35)"
    else:
        feedback += f" — needs {30 - tests_passed} more to pass"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": result
    }
