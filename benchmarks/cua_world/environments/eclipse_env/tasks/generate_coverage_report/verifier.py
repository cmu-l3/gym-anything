#!/usr/bin/env python3
"""Verifier for generate_coverage_report task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_coverage_report(traj, env_info, task_info):
    """
    Verify that the agent generated an HTML code coverage report.
    
    Criteria:
    1. Report index.html exists (40 pts)
    2. File was created during the task (Anti-gaming) (10 pts)
    3. Content appears to be valid HTML (20 pts)
    4. Content refers to the correct project/class (20 pts)
    5. VLM check verifies UI interaction (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    max_score = 100

    # Retrieve result JSON
    result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result data"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Criterion 1: Report Exists (40 pts)
    if result.get('report_exists', False):
        score += 40
        feedback_parts.append("Report file exists")
    else:
        feedback_parts.append("Report file NOT found at expected path")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Timestamp Check (10 pts)
    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("Report created during task")
    else:
        feedback_parts.append("Report file is old or pre-existing")

    # Criterion 3: HTML Format (20 pts)
    if result.get('is_html', False):
        score += 20
        feedback_parts.append("Format is HTML")
    else:
        feedback_parts.append("Format appears invalid (not HTML)")

    # Criterion 4: Content Verification (20 pts)
    if result.get('contains_project_name', False):
        score += 20
        feedback_parts.append("Report contains correct project data")
    else:
        feedback_parts.append("Report does not mention 'FinTechCalc' or 'LoanCalculator'")

    # Criterion 5: VLM Verification (10 pts)
    # Check if we saw the Coverage view or export dialog
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Run JUnit tests with coverage and export HTML report",
            checklist_items=[
                "Eclipse IDE is open",
                "The 'Coverage' view is visible (usually green/red bars in editor or separate view)",
                "The 'Export' wizard or dialog is visible",
                "HTML format selected in export dialog"
            ]
        )
        if vlm_result and vlm_result.get('vlm_passed', False):
            score += 10
            feedback_parts.append("Visual confirmation of coverage/export workflow")
        else:
            feedback_parts.append("VLM did not confirm workflow steps")
    except ImportError:
        logger.warning("VLM module not available, awarding points generously if file is correct")
        # If file is perfect, give benefit of doubt for VLM portion
        if score >= 90:
            score += 10

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }