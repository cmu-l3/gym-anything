#!/usr/bin/env python3
"""Verifier for reorganize_package_structure task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reorganize_package_structure(traj, env_info, task_info):
    """
    Verify the Java project refactoring task.
    
    Scoring Criteria:
    1. Files moved to correct directories (5 points per file * 10 files = 50 pts)
    2. Package declarations updated in files (checked implicitly by build, but also explicitly)
    3. Project compilation success (30 pts)
    4. Old directory cleanup (10 pts)
    5. VLM verification of process (10 pts)
    
    Total: 100 pts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata for expected structure
    metadata = task_info.get('metadata', {})
    
    # 1. Read Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: File Locations (50 pts) ---
    file_checks = result.get('file_checks', [])
    files_correct = 0
    total_files = len(file_checks)
    
    moved_correctly = []
    failed_moves = []
    
    for fc in file_checks:
        fname = fc.get('filename')
        # Check if physically in right folder
        loc_ok = fc.get('correct_location', False)
        # Check if package declaration matches folder structure roughly
        # (Export script extracts explicit package name)
        pkg = fc.get('package', '')
        
        # Infer expected package from expected path in export script logic
        # But here we can simply validate that package matches the path structure
        # e.g. path .../com/myapp/model/User.java -> package com.myapp.model
        
        if loc_ok:
            # Verify package declaration matches the location
            # Simple heuristic: if loc is com/myapp/model, package should contain com.myapp.model
            if pkg and pkg in fc.get('path', '').replace('/', '.'):
                files_correct += 1
                moved_correctly.append(fname)
            else:
                failed_moves.append(f"{fname} (moved but package decl wrong: '{pkg}')")
        else:
            failed_moves.append(f"{fname} (wrong location)")

    # 5 points per file
    file_score = files_correct * 5
    score += file_score
    feedback.append(f"File Structure: {files_correct}/{total_files} files correct ({file_score}/50 pts)")
    if failed_moves:
        feedback.append(f"Issues: {', '.join(failed_moves[:3])}...")

    # --- Criterion 2: Compilation (30 pts) ---
    if result.get('build_success', False):
        score += 30
        feedback.append("Compilation: Success (30/30 pts)")
    else:
        feedback.append("Compilation: Failed (0/30 pts)")
        # If compilation failed, check if it was due to moves without refactoring
        if files_correct > 0:
            feedback.append("Hint: Did you update imports? (Refactor > Move required)")

    # --- Criterion 3: Cleanup (10 pts) ---
    if result.get('old_directory_clean', False):
        score += 10
        feedback.append("Cleanup: Old 'myapp' package removed (10/10 pts)")
    else:
        feedback.append("Cleanup: Old 'myapp' package still exists/not empty (0/10 pts)")

    # --- Criterion 4: VLM Verification (10 pts) ---
    # We want to see the Package Explorer with the new hierarchy
    vlm_score = 0
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Refactor Java project: Move classes from 'myapp' to 'com.myapp.model', 'com.myapp.service', etc.",
            checklist_items=[
                "Eclipse Package Explorer is visible",
                "Project structure shows 'com.myapp' hierarchy (model, service, etc)",
                "No compilation errors (red X icons) visible on final files",
                "Refactor/Move dialog was visible at some point"
            ]
        )
        
        if vlm_result:
            if vlm_result.get('vlm_passed'):
                vlm_score = 10
                feedback.append("VLM: Visual verification passed (10/10 pts)")
            else:
                feedback.append(f"VLM: Visual check failed - {vlm_result.get('vlm_feedback')}")
            
    except Exception as e:
        logger.warning(f"VLM check error: {e}")
        feedback.append("VLM: Skipped due to error")

    score += vlm_score

    # Determine Pass/Fail
    # Must compile AND have moved at least 80% of files
    passed = (result.get('build_success') and files_correct >= 8)

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }