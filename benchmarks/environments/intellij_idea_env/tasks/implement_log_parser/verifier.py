#!/usr/bin/env python3
"""Verifier for implement_log_parser task."""

import json
import tempfile
import os
import re
import logging
from utils.intellij_verification_utils import vlm_verify_intellij_task

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_log_parser(traj, env_info, task_info):
    """Verify log parser implementation.

    Scoring (100 pts total):
    1. Project compiles (10 pts)
    2. Parser implementation non-stub (10 pts)
    3. Analyzer implementation non-stub (10 pts)
    4. Unit Tests Pass (5 pts each, max 50 pts)
    5. Report file exists and valid (10 pts)
    6. VLM Verification (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Compilation (10 pts)
    if task_result.get('compile_success'):
        score += 10
        feedback.append("Project compiles successfully.")
    else:
        feedback.append("Project compilation failed.")

    # 2. Source Code Checks (20 pts)
    parser_src = task_result.get('parser_source', '')
    analyzer_src = task_result.get('analyzer_source', '')

    # Check for meaningful regex in Parser
    if 'Pattern.compile' in parser_src and 'TODO' not in parser_src and len(parser_src) > 500:
        score += 10
        feedback.append("LogParser implementation looks valid.")
    else:
        feedback.append("LogParser appears incomplete or stubbed.")

    # Check for stream/loop logic in Analyzer
    if ('stream()' in analyzer_src or 'for (' in analyzer_src) and 'TODO' not in analyzer_src:
        score += 10
        feedback.append("LogAnalyzer implementation looks valid.")
    else:
        feedback.append("LogAnalyzer appears incomplete or stubbed.")

    # 3. Test Results (50 pts)
    tests_passed = task_result.get('tests_passed', 0)
    tests_score = min(50, tests_passed * 5) # 10 tests total
    score += tests_score
    feedback.append(f"Unit Tests: {tests_passed}/10 passed ({tests_score} pts).")

    # 4. Report Validation (10 pts)
    report_exists = task_result.get('report_exists', False)
    report_content = task_result.get('report_content', '')
    
    if report_exists and len(report_content) > 50:
        # Basic validation of content
        if "Total Requests:" in report_content and "Status Codes:" in report_content:
             score += 10
             feedback.append("Analysis report generated and looks correct.")
        else:
             score += 5
             feedback.append("Analysis report exists but format seems wrong.")
    else:
        feedback.append("Analysis report not found or empty.")

    # 5. VLM Verification (10 pts)
    vlm_result = vlm_verify_intellij_task(
        traj, env_info, task_result.get('description', 'Parse logs'),
        ["IntelliJ IDEA window visible", "Java code being edited", "Tests running or console output visible"]
    )
    
    if vlm_result:
        vlm_score_component = 10 if vlm_result['vlm_passed'] else 0
        score += vlm_score_component
        feedback.append(f"VLM: {vlm_result['vlm_feedback']}")
    else:
        # Fallback if VLM unavailable
        if score >= 60: score += 10 

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }