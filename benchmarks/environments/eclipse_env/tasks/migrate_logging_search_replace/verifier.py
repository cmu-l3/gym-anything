#!/usr/bin/env python3
"""
Verifier for migrate_logging_search_replace task.

Verifies:
1. Code Compilation: Project must compile.
2. Logging Migration:
   - System.out.println count should be low (ideally 1, for Main).
   - System.err.println count should be 0.
   - Logger imports and fields should exist in ~10 files.
   - Logger calls should replace print statements.
3. Special Condition: Main.java must keep its final output line.
4. VLM: Check for Search dialog usage in trajectory.
"""

import json
import logging
import tempfile
import os
from typing import Dict, Any

# Import shared VLM utility
try:
    from eclipse_verification_utils import vlm_verify_eclipse_task
except ImportError:
    # Fallback if running locally/testing without the utility
    def vlm_verify_eclipse_task(*args, **kwargs):
        return {"vlm_score": 0, "vlm_feedback": "VLM utils not available", "vlm_passed": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_logging(traj, env_info, task_info):
    """
    Verify the migration of System.out.println to java.util.logging.Logger.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # 1. Load results from export_result.sh
    result_json_path = "/tmp/task_result.json"
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json") as tmp:
            copy_from_env(result_json_path, tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}

    # Extract metrics
    compile_success = result.get("compile_success", False)
    exec_success = result.get("exec_success", False)
    remaining_out = result.get("remaining_system_out", 999)
    remaining_err = result.get("remaining_system_err", 999)
    main_has_line = result.get("main_has_required_line", False)
    logger_imports = result.get("logger_imports", 0)
    logger_fields = result.get("logger_fields", 0)
    logger_calls = result.get("logger_calls", 0)
    report_exists = result.get("report_exists", False)

    score = 0
    feedback = []

    # Scoring Criteria

    # A. Compilation (Critical - 15 pts)
    if compile_success:
        score += 15
        feedback.append("Project compiles successfully (+15).")
    else:
        feedback.append("Project failed to compile (0/15). Check for missing imports or syntax errors.")

    # B. Execution (5 pts)
    if exec_success:
        score += 5
        feedback.append("Project executes successfully (+5).")
    else:
        feedback.append("Project execution failed (0/5).")

    # C. System.out.println Removal (25 pts)
    # Ideally 1 remaining (the one in Main).
    if remaining_out <= 1 and main_has_line:
        score += 25
        feedback.append("All System.out.println calls replaced (except allowed Main line) (+25).")
    elif remaining_out <= 3:
        # Partial credit if they missed just a couple
        score += 15
        feedback.append(f"Most System.out.println calls replaced ({remaining_out} remaining) (+15).")
    elif remaining_out == 0 and not main_has_line:
         # They removed the required line too
         score += 20
         feedback.append("All System.out.println calls replaced, but you removed the required output in Main.java (-5 pts).")
    else:
        feedback.append(f"Too many System.out.println calls remaining ({remaining_out}) (0/25).")

    # D. System.err.println Removal (10 pts)
    if remaining_err == 0:
        score += 10
        feedback.append("All System.err.println calls replaced (+10).")
    else:
        feedback.append(f"Some System.err.println calls remain ({remaining_err}) (0/10).")

    # E. Logger Implementation (25 pts total)
    # Check imports
    if logger_imports >= 10:
        score += 10
        feedback.append("Logger imports present in all files (+10).")
    elif logger_imports >= 5:
        score += 5
        feedback.append(f"Logger imports present in some files ({logger_imports}/10) (+5).")
    
    # Check fields (private static final Logger...)
    if logger_fields >= 10:
        score += 15
        feedback.append("Logger fields defined in all files (+15).")
    elif logger_fields >= 5:
        score += 7
        feedback.append(f"Logger fields defined in some files ({logger_fields}/10) (+7).")

    # F. Logger Calls (10 pts)
    # There were about ~28 print statements initially.
    if logger_calls >= 25:
        score += 10
        feedback.append("High volume of Logger calls detected (+10).")
    elif logger_calls >= 10:
        score += 5
        feedback.append("Some Logger calls detected (+5).")
    else:
        feedback.append("Few or no Logger calls found (0/10).")

    # G. Report File (10 pts)
    if report_exists:
        score += 10
        feedback.append("Migration report file created (+10).")
    else:
        feedback.append("Migration report file missing (0/10).")

    # H. VLM Verification for Process (Bonus/Validation)
    checklist = [
        "Eclipse IDE is open",
        "Search dialog (Ctrl+H) or Find/Replace is visible",
        "Editing Java files to add Logger",
        "Package Explorer shows DataPipeline project"
    ]
    vlm_res = vlm_verify_eclipse_task(traj, env_info, "Migrate logging to Logger using Eclipse Search", checklist)
    
    # VLM isn't strictly adding points here to keep it deterministic based on code,
    # but we use it to validate the process if needed. 
    # For this specific task, code analysis is robust enough, but we append feedback.
    if vlm_res:
        feedback.append(f"Visual Verification: {vlm_res.get('vlm_feedback')}")

    # Final Pass/Fail Logic
    # Must compile AND have removed most printlns
    passed = (score >= 60) and compile_success and (remaining_out <= 3)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }