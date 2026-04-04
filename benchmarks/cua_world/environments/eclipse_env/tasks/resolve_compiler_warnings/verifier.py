#!/usr/bin/env python3
"""
Verifier for resolve_compiler_warnings task.

Verification Logic:
1. Verify Eclipse preferences were updated (Raw Type=Error, Unused Import=Error).
2. Verify project source files were modified (checksums changed).
3. Verify code compiles cleanly with javac -Xlint:all (Zero warnings, zero errors).
4. Verify specific fixes (e.g. no raw types in source).
5. VLM verification of UI state (optional backup).
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_compiler_warnings(traj, env_info, task_info):
    """Verify that compiler warnings were resolved and prefs updated."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Load result JSON
    try:
        tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_result.close()
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # Extract metrics
    project_imported = result.get('project_imported', False)
    files_modified = result.get('files_modified', False)
    prefs_correct = result.get('prefs_correct', False)
    compile_success = result.get('compile_success', False)
    warning_count = result.get('warning_count', -1)
    error_count = result.get('error_count', 0)
    
    # --- Criterion 1: Project Imported (10 pts) ---
    if project_imported:
        score += 10
        feedback.append("Project imported successfully")
    else:
        feedback.append("Project NOT imported into Eclipse workspace")
        return {"passed": False, "score": 0, "feedback": "Project not imported"}

    # --- Criterion 2: Preferences Configured (20 pts) ---
    # Task required changing compiler prefs for Raw Type and Unused Import to Error
    prefs_raw = result.get('prefs_raw_type', 'ignore')
    prefs_unused = result.get('prefs_unused_import', 'ignore')
    
    if prefs_correct:
        score += 20
        feedback.append("Compiler preferences correctly set to Error")
    else:
        # Partial credit
        if prefs_raw == 'error':
            score += 10
            feedback.append("Raw Type pref set to Error")
        else:
            feedback.append(f"Raw Type pref incorrect ({prefs_raw})")
            
        if prefs_unused == 'error':
            score += 10
            feedback.append("Unused Import pref set to Error")
        else:
            feedback.append(f"Unused Import pref incorrect ({prefs_unused})")

    # --- Criterion 3: Files Modified (10 pts) ---
    if files_modified:
        score += 10
        feedback.append("Source files were modified")
    else:
        feedback.append("No source files were modified")

    # --- Criterion 4: Clean Compilation (60 pts) ---
    # Determine points based on remaining warnings
    if compile_success:
        if warning_count == 0 and error_count == 0:
            score += 60
            feedback.append("Code compiles with ZERO warnings/errors")
        elif warning_count == 0:
            # Errors present but no warnings? Unlikely but possible if they broke code
            score += 0
            feedback.append(f"Compilation FAILED with {error_count} errors")
        else:
            # Partial credit for reducing warnings
            # Initial warnings were ~18.
            # 50 pts - (2 pts per remaining warning)
            penalty = warning_count * 3
            comp_score = max(0, 50 - penalty)
            score += comp_score
            feedback.append(f"Code compiles but has {warning_count} remaining warnings ({comp_score}/60 pts)")
    else:
        feedback.append("Code FAILED to compile (syntax errors introduced?)")
        
    # --- VLM Verification (Bonus/Sanity Check) ---
    # We use VLM to verify the "process" - e.g. did they open the Problems view?
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        vlm_res = vlm_verify_eclipse_task(
            traj, env_info, 
            "Import DataUtils project, configure compiler preferences, and fix all warnings.",
            [
                "Eclipse IDE is visible",
                "Problems view is visible",
                "Project 'DataUtils' is in Project/Package Explorer",
                "Preferences dialog was opened",
                "Editor shows Java code being modified"
            ]
        )
        if vlm_res:
            feedback.append(f"VLM: {vlm_res.get('vlm_feedback')}")
    except Exception:
        pass

    # Final decision
    # Must pass clean compilation OR have very high score with minor pref issue
    passed = (score >= 90) or (compile_success and warning_count == 0 and error_count == 0 and prefs_correct)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback)
    }