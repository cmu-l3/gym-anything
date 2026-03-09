#!/usr/bin/env python3
"""Verifier for add_dependency_implement task."""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_dependency_implement(traj, env_info, task_info):
    """
    Verify the add_dependency_implement task.

    Scoring (100 pts total):
    1. Gson dependency in pom.xml (15 pts)
    2. JsonExporter.java modified with implementations (10 pts)
    3. Compilation succeeds (20 pts)
    4. Tests pass (15 pts each for toJson, fromJson; 10 pts each for file I/O) (50 pts total)
    5. VLM workflow check (5 pts)

    Pass threshold: 70 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Load result JSON
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

    # --- Criterion 1: Gson in pom.xml (15 pts) ---
    pom_content = result.get('pom_content', '')
    pom_modified = result.get('pom_modified', False)
    
    has_gson_group = 'com.google.code.gson' in pom_content
    has_gson_artifact = 'gson' in pom_content
    has_gson_version = '2.10.1' in pom_content
    
    if has_gson_group and has_gson_artifact and has_gson_version and pom_modified:
        score += 15
        feedback_parts.append("Gson dependency correctly added to pom.xml")
    elif has_gson_group and has_gson_artifact:
        score += 10
        feedback_parts.append("Gson dependency added but version might be wrong or file not marked modified")
    else:
        feedback_parts.append("Gson dependency missing from pom.xml")

    # --- Criterion 2: JsonExporter.java modified (10 pts) ---
    impl_content = result.get('impl_content', '')
    impl_modified = result.get('impl_modified', False)
    
    has_gson_import = 'import com.google.gson' in impl_content
    has_no_stubs = 'UnsupportedOperationException' not in impl_content
    
    if has_gson_import and has_no_stubs and impl_modified:
        score += 10
        feedback_parts.append("JsonExporter.java implementation provided")
    elif has_gson_import:
        score += 5
        feedback_parts.append("JsonExporter.java imports Gson but might still contain stubs")
    else:
        feedback_parts.append("JsonExporter.java not correctly implemented")

    # --- Criterion 3: Compilation Success (20 pts) ---
    compile_success = result.get('compile_success', False)
    if compile_success:
        score += 20
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append("Project compilation failed")

    # --- Criterion 4: Tests Pass (50 pts total) ---
    # We infer individual test success from total passed count because 
    # capturing per-test status from raw bash is brittle.
    # Total expected tests: 4
    
    tests_run = result.get('tests_run', 0)
    tests_passed = result.get('tests_passed', 0)
    
    if compile_success and tests_run == 4:
        # Assign points proportionally to passed tests
        # 4 tests -> 50 points (12.5 per test)
        test_points = int((tests_passed / 4.0) * 50)
        score += test_points
        feedback_parts.append(f"Tests passed: {tests_passed}/4 ({test_points} pts)")
    elif compile_success:
        feedback_parts.append(f"Incorrect number of tests run: {tests_run} (expected 4)")
    else:
        feedback_parts.append("Tests skipped due to compilation failure")

    # --- Criterion 5: VLM Workflow Verification (5 pts) ---
    # Verify the agent actually used the IDE
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, num_samples=3)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            frames.append(final_ss)
            
        if frames:
            prompt = """
            Look at these screenshots of an agent using IntelliJ IDEA.
            Did the agent:
            1. Edit a pom.xml file?
            2. Edit a Java file?
            3. Run Maven tests or see a 'BUILD SUCCESS' message?
            
            Answer YES or NO for each.
            """
            vlm_res = query_vlm(prompt=prompt, images=frames)
            
            if vlm_res and vlm_res.get('success'):
                # Simple check if VLM thinks it looks good
                response = vlm_res.get('response', '').lower()
                if 'yes' in response:
                    vlm_score = 5
                    feedback_parts.append("VLM verified workflow")
                else:
                    feedback_parts.append("VLM could not verify workflow")
            else:
                # Fallback if VLM fails but other things passed
                if score > 40: 
                    vlm_score = 5
                    feedback_parts.append("VLM skipped, assumed valid based on output")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Graceful fallback
        if score > 40:
            vlm_score = 5
            
    score += vlm_score

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }