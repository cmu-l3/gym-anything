#!/usr/bin/env python3
"""
Verifier for inline_refactoring task.

Criteria:
1. All 6 target methods must be removed from source files (8 pts each = 48 pts)
2. Project must compile (15 pts) - CRITICAL: if false, refactoring points are voided
3. Tests must pass (15 pts)
4. Report file exists (7 pts)
5. VLM verification of GUI interaction (15 pts)

Total: 100 pts
Pass Threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inline_refactoring(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read result JSON
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # Extract flags
    compile_success = result.get('compile_success', False)
    test_success = result.get('test_success', False)
    
    # Method removal checks
    methods = {
        "trimInput": result.get('trim_gone'),
        "checkEmpty": result.get('empty_gone'),
        "addValues": result.get('add_gone'),
        "computeAbsolute": result.get('abs_gone'),
        "invokeValidation": result.get('val_gone'),
        "wrapResult": result.get('wrap_gone')
    }
    
    method_points = 0
    missing_methods = []
    
    # 2. Check Compilation (Gatekeeper)
    if compile_success:
        score += 15
        feedback_parts.append("Project compiles")
        
        # Only award method points if code compiles (preventing deletion-only gaming)
        for name, status in methods.items():
            if status == "true":
                method_points += 8
            else:
                missing_methods.append(name)
        
        if method_points == 48:
            feedback_parts.append("All 6 target methods inlined")
        else:
            feedback_parts.append(f"Methods inlined: {len(methods) - len(missing_methods)}/6")
            feedback_parts.append(f"Failed to remove: {', '.join(missing_methods)}")
            
        score += method_points
    else:
        feedback_parts.append("CRITICAL: Project does not compile. Refactoring must preserve validity.")
        # No points for deleted methods if code is broken
    
    # 3. Check Tests
    if test_success:
        score += 15
        feedback_parts.append("Tests passed")
    elif compile_success:
        feedback_parts.append("Tests failed (logic broken)")
    
    # 4. Check Report
    if result.get('report_exists'):
        score += 7
        feedback_parts.append("Report file created")
    else:
        feedback_parts.append("Report file missing")
        
    # 5. VLM Verification
    try:
        from utils.eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Use Eclipse 'Inline' refactoring to remove methods.",
            checklist_items=[
                "Eclipse IDE is visible",
                "Agent opens a Java source file",
                "Agent uses Refactor menu or Inline shortcut (Alt+Shift+I)",
                "Inline Refactoring dialog is visible",
                "Agent runs JUnit tests at the end"
            ]
        )
        
        if vlm_result:
            if vlm_result.get('vlm_passed'):
                score += 15
            feedback_parts.append(vlm_result.get('vlm_feedback'))
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Graceful degradation if VLM fails
        feedback_parts.append("VLM verification skipped")

    # Hard pass threshold
    passed = score >= 60 and compile_success

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }