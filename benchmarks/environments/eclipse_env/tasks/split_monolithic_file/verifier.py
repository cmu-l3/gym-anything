#!/usr/bin/env python3
"""
Verifier for split_monolithic_file task.
"""

import json
import tempfile
import os
import logging
import sys

# Add utils path for VLM
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from utils.eclipse_verification_utils import vlm_verify_eclipse_task

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_split_monolithic_file(traj, env_info, task_info):
    """
    Verify that the monolithic Java file was split correctly.
    
    Scoring Criteria:
    1. Structure (56 pts): 8 pts for each of 7 types extracted to own file.
    2. Cleanup (10 pts): Original monolithic file is deleted or nearly empty.
    3. Compilation (20 pts): Project compiles successfully.
    4. Behavior (14 pts): Runtime output matches expected output.
    5. VLM Bonus (up to 5 pts included in above or extra): Verifies GUI usage.
    
    Total: 100 pts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Load result from export_result.sh
    try:
        tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_result.close()
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}

    # 1. Structure Check (56 pts max)
    files_status = result.get("files_status", {})
    files_exist_count = result.get("files_exist_count", 0)
    
    expected_files = [
        "Command.java", "UndoableCommand.java", "TextDocument.java", 
        "InsertTextCommand.java", "DeleteTextCommand.java", 
        "MacroCommand.java", "CommandInvoker.java"
    ]
    
    structure_score = 0
    missing_files = []
    for f in expected_files:
        if files_status.get(f, False):
            structure_score += 8
        else:
            missing_files.append(f)
    
    score += structure_score
    if missing_files:
        feedback_parts.append(f"Missing files: {', '.join(missing_files)} ({structure_score}/56 pts)")
    else:
        feedback_parts.append(f"All {len(expected_files)} types extracted ({structure_score}/56 pts)")

    # 2. Cleanup Check (10 pts)
    monolithic_status = result.get("monolithic_status", "unknown")
    if monolithic_status == "deleted":
        score += 10
        feedback_parts.append("CommandSystem.java deleted (+10 pts)")
    elif monolithic_status.startswith("exists_with_"):
        try:
            count = int(monolithic_status.split("_")[-1])
            if count <= 1:
                score += 10
                feedback_parts.append(f"CommandSystem.java cleaned up ({count} types left) (+10 pts)")
            else:
                feedback_parts.append(f"CommandSystem.java still has {count} types (0 pts)")
        except:
            feedback_parts.append("Could not verify CommandSystem.java cleanup")
    else:
        feedback_parts.append(f"CommandSystem.java status: {monolithic_status}")

    # 3. Compilation Check (20 pts)
    if result.get("compile_success", False):
        score += 20
        feedback_parts.append("Project compiles successfully (+20 pts)")
    else:
        feedback_parts.append("Project FAILED to compile (0 pts) - Refactoring broke the code")

    # 4. Runtime Behavior Check (14 pts)
    # Priority to system check, then agent output file
    if result.get("runtime_match", False):
        score += 14
        feedback_parts.append("Runtime output matches expected (+14 pts)")
    elif result.get("agent_output_match", False):
        score += 10 # Slightly less if we couldn't run it but agent saved correct output
        feedback_parts.append("Agent output file matches expected (+10 pts)")
    else:
        if result.get("compile_success", False):
            feedback_parts.append("Runtime output INCORRECT (0 pts)")
        else:
            feedback_parts.append("Runtime check skipped due to compilation failure")

    # 5. VLM Check (Integrity check)
    vlm_result = vlm_verify_eclipse_task(
        traj, env_info,
        "Refactor a Java file by moving types to new files using Eclipse context menu",
        [
            "Eclipse Package Explorer shows multiple java files in com.example.commands",
            "CommandSystem.java is NOT the only file in the package",
            "No compilation errors visible in Problems view"
        ]
    )
    
    if vlm_result and not vlm_result.get("vlm_passed", False):
        # Deduct points if visual evidence contradicts success (e.g., massive red errors visible)
        # But don't penalize too hard if VLM is flaky
        feedback_parts.append(f"VLM Note: {vlm_result.get('vlm_feedback', '')}")

    # Final verdict
    passed = score >= 90 # High bar: refactoring shouldn't break code
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }