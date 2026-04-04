#!/usr/bin/env python3
"""Verifier for refactor_extract_method task."""

import json
import tempfile
import os
import re
import logging
import sys

# Add workspace utils to path
sys.path.insert(0, '/workspace/utils')
try:
    from eclipse_verification_utils import vlm_verify_eclipse_task
except ImportError:
    vlm_verify_eclipse_task = None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_refactor_extract_method(traj, env_info, task_info):
    """Verify that the method was extracted and duplicated code removed.

    Criteria:
    1. 'appendReportHeader' method exists (30 pts)
    2. 'generateDailyReport' calls the new method (20 pts)
    3. 'generateWeeklyReport' calls the new method (30 pts)
    4. Code compiles and tests pass (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Read result from export_result.sh
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    content = result.get('file_content', '')
    if not content:
        return {"passed": False, "score": 0, "feedback": "Source file is empty or missing"}

    # --- Criterion 1: Check for new method (30 pts) ---
    # We look for private void/String appendReportHeader(StringBuilder ...)
    # The signature might vary depending on how Eclipse extracts it, but it typically passes StringBuilder
    # or returns a String. Given the code, passing StringBuilder is most likely.
    
    method_regex = r'(private|protected|public).*void\s+appendReportHeader\s*\('
    if re.search(method_regex, content):
        score += 30
        feedback_parts.append("New method 'appendReportHeader' created")
    else:
        feedback_parts.append("Method 'appendReportHeader' not found")

    # --- Criterion 2 & 3: Check usage and deduplication (50 pts total) ---
    daily_method = re.search(r'generateDailyReport.*?\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}', content, re.DOTALL)
    weekly_method = re.search(r'generateWeeklyReport.*?\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}', content, re.DOTALL)
    
    # Check Daily Report (Source of extraction)
    if daily_method:
        daily_body = daily_method.group(1)
        if 'appendReportHeader' in daily_body:
            score += 20
            feedback_parts.append("generateDailyReport updated")
            
            # Verify the original string literals are gone from the method body
            if "ACME CORP - INTERNAL REPORT" in daily_body:
                feedback_parts.append("WARNING: Duplicate code NOT removed from daily report")
                score -= 10
        else:
            feedback_parts.append("generateDailyReport does not call the new method")

    # Check Weekly Report (Target of deduplication)
    if weekly_method:
        weekly_body = weekly_method.group(1)
        if 'appendReportHeader' in weekly_body:
            score += 30
            feedback_parts.append("generateWeeklyReport updated (Deduplication successful)")
            
            if "ACME CORP - INTERNAL REPORT" in weekly_body:
                feedback_parts.append("WARNING: Duplicate code NOT removed from weekly report")
                score -= 15
        else:
            feedback_parts.append("generateWeeklyReport does NOT call the new method (Did you check 'Replace duplicate occurrences'?)")

    # --- Criterion 4: Build and Test Status (20 pts) ---
    if result.get('build_success'):
        score += 10
        feedback_parts.append("Build success")
        if result.get('tests_passed'):
            score += 10
            feedback_parts.append("Tests passed")
        else:
            feedback_parts.append("Tests FAILED")
    else:
        feedback_parts.append("Build FAILED")

    # --- VLM Verification (Bonus/Confirmation) ---
    if vlm_verify_eclipse_task:
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Extract method 'appendReportHeader' to remove duplication",
            checklist_items=[
                "Eclipse Extract Method dialog is visible",
                "The 'Replace duplicate occurrences' option is checked (if visible)",
                "The agent runs the JUnit tests"
            ]
        )
        if vlm_result and vlm_result.get('vlm_passed'):
            feedback_parts.append("(VLM confirmed workflow)")
        
    passed = score >= 80  # strict pass because deduplication is the main point
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }