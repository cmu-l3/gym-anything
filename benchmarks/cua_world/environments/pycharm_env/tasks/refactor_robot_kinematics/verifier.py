#!/usr/bin/env python3
"""Verifier for refactor_robot_kinematics task."""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_robot_kinematics(traj, env_info, task_info):
    """
    Verify that the robot controller was refactored correctly.
    
    Scoring Criteria (Total 100):
    - Structure (50 pts):
        - robot/ package exists (10)
        - kinematics module exists & correct (10)
        - trajectory module exists & correct (10)
        - safety module exists & correct (10)
        - arm module exists & correct (10)
    - Code Quality (15 pts):
        - arm.py uses composition (10)
        - __init__.py exports classes (5)
    - Functionality (35 pts):
        - All 12 tests pass (30)
        - Tests import from new package (5)
        
    Pass Threshold: 65 points AND structure must be valid.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    result = {}
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
    
    # 1. Check Structure (50 pts)
    structure = result.get("structure", {})
    content = result.get("content_analysis", {})
    
    if structure.get("robot_dir") and structure.get("init_py"):
        score += 10
        feedback_parts.append("Package directory created (10/10)")
    else:
        feedback_parts.append("Package directory missing or invalid")
        
    if structure.get("kinematics_py") and content.get("kinematics_class"):
        score += 10
        feedback_parts.append("Kinematics module valid (10/10)")
    else:
        feedback_parts.append("Kinematics module missing/invalid")

    if structure.get("trajectory_py") and content.get("trajectory_class"):
        score += 10
        feedback_parts.append("Trajectory module valid (10/10)")
    else:
        feedback_parts.append("Trajectory module missing/invalid")
        
    if structure.get("safety_py") and content.get("safety_class"):
        score += 10
        feedback_parts.append("Safety module valid (10/10)")
    else:
        feedback_parts.append("Safety module missing/invalid")
        
    if structure.get("arm_py") and content.get("arm_class"):
        score += 10
        feedback_parts.append("Arm module valid (10/10)")
    else:
        feedback_parts.append("Arm module missing/invalid")
        
    # 2. Check Code Quality (15 pts)
    if content.get("composition_used"):
        score += 10
        feedback_parts.append("Composition used in RobotArm (10/10)")
    else:
        feedback_parts.append("Composition NOT used (monolith code copied?)")
        
    if content.get("init_exports"):
        score += 5
        feedback_parts.append("__init__.py exports classes (5/5)")
        
    # 3. Check Functionality (35 pts)
    passed_tests = result.get("passed_tests", 0)
    total_tests = result.get("total_tests", 12)
    
    # Pro-rated score for tests
    test_score = 0
    if total_tests > 0:
        test_score = int((passed_tests / total_tests) * 30)
    score += test_score
    feedback_parts.append(f"Tests passed: {passed_tests}/{total_tests} ({test_score}/30)")
    
    if content.get("test_imports_correct"):
        score += 5
        feedback_parts.append("Tests updated to import from package (5/5)")
    else:
        feedback_parts.append("Tests still import from old file or invalid")

    # Final Evaluation
    passed = score >= 65 and structure.get("robot_dir")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }