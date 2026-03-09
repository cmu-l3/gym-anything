#!/usr/bin/env python3
"""Verifier for extract_constants task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_extract_constants(traj, env_info, task_info):
    """
    Verify that magic numbers were extracted into constants.
    
    Scoring:
    - 20 pts: Project compiles and tests pass
    - 20 pts: PhysicsConstants.java cleaned
    - 20 pts: UnitConverter.java cleaned
    - 20 pts: OrbitalMechanics.java cleaned
    - 10 pts: NetworkConfig.java cleaned
    - 10 pts: VLM Verification (Trajectory shows usage of Eclipse)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Compile & Test (20 pts)
    compile_success = result.get("compile_success", False)
    tests_passed = result.get("tests_passed", False)
    
    if compile_success:
        score += 10
        feedback_parts.append("Project compiles")
    else:
        feedback_parts.append("Project compilation FAILED")
        
    if tests_passed:
        score += 10
        feedback_parts.append("Tests pass")
    else:
        feedback_parts.append("Tests FAILED")

    # 2. Check each file (70 pts total)
    analysis = result.get("code_analysis", {})
    files_info = analysis.get("files", {})
    
    # Weights for each file
    file_weights = {
        "PhysicsConstants.java": 20,
        "UnitConverter.java": 20,
        "OrbitalMechanics.java": 20,
        "NetworkConfig.java": 10
    }
    
    total_magic_remaining = 0
    
    for filename, weight in file_weights.items():
        finfo = files_info.get(filename, {})
        modified = finfo.get("modified", False)
        magic_remaining = finfo.get("magic_numbers_remaining", [])
        constants_found = finfo.get("constants_found", [])
        
        file_score = 0
        if modified:
            if not magic_remaining:
                if len(constants_found) > 0:
                    file_score = weight
                    feedback_parts.append(f"{filename}: Cleaned ({weight}pts)")
                else:
                    # Modified but no constants? Maybe they just hardcoded arithmetic or deleted lines.
                    # We penalize if tests pass but no constants found (unlikely valid refactor)
                    file_score = weight // 2
                    feedback_parts.append(f"{filename}: Modified but no constants found")
            else:
                # Partial credit?
                fraction = 1.0 - (len(magic_remaining) / 3.0) # Approx
                if fraction < 0: fraction = 0
                file_score = int(weight * fraction)
                feedback_parts.append(f"{filename}: {len(magic_remaining)} magic numbers left")
        else:
            feedback_parts.append(f"{filename}: Not modified")
            
        score += file_score
        total_magic_remaining += len(magic_remaining)

    # 3. VLM Verification (10 pts)
    # Check if they actually used the GUI refactoring tool or just typed it
    # We look for the "Extract Constant" dialog or context menu in trajectory
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        checklist = [
            "Eclipse editor showing Java code",
            "Refactor menu or Extract Constant dialog visible",
            "Package Explorer visible",
            "JUnit runner showing green bar"
        ]
        
        vlm_res = vlm_verify_eclipse_task(traj, env_info, "Refactor magic numbers into constants", checklist)
        
        if vlm_res and vlm_res.get("vlm_score", 0) > 50:
            score += 10
            feedback_parts.append("VLM: Eclipse usage verified")
        else:
            # Fallback if VLM fails or they were super fast hotkey users: check if result is perfect
            if total_magic_remaining == 0 and tests_passed:
                score += 10 # Give benefit of doubt for perfect programmatic execution
                feedback_parts.append("VLM: Skipped/Inconclusive, awarded for perfect result")
            else:
                feedback_parts.append("VLM: Little evidence of UI interaction")

    except ImportError:
        # Fallback if utils missing
        if total_magic_remaining == 0 and tests_passed:
            score += 10

    return {
        "passed": score >= 70 and compile_success and tests_passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }