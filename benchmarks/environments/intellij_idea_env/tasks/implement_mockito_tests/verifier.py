#!/usr/bin/env python3
"""Verifier for implement_mockito_tests task."""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_mockito_tests(traj, env_info, task_info):
    """
    Verify that the user implemented correct Mockito tests.
    
    Scoring Breakdown (100 pts total):
    - 10 pts: Maven Dependencies (JUnit 5 + Mockito)
    - 10 pts: Test file created during task
    - 10 pts: Test code contains Mockito usage (@Mock, verify, when)
    - 20 pts: Baseline tests pass (compiles and runs)
    - 15 pts: Mutant A caught (verifies repository.save called)
    - 15 pts: Mutant B caught (verifies return value/logic)
    - 10 pts: Mutant C caught (verifies correct status saved)
    - 10 pts: VLM Verification (IntelliJ usage visible)
    
    Pass Threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read JSON Result
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
    feedback = []

    # Criterion 1: Maven Dependencies (10 pts)
    if result.get("has_junit_dependency") and result.get("has_mockito_dependency"):
        score += 10
        feedback.append("Dependencies correct.")
    else:
        feedback.append("Missing JUnit or Mockito dependency.")

    # Criterion 2: Test File Existence & Timestamp (10 pts)
    if result.get("test_file_exists") and result.get("test_created_during_task"):
        score += 10
        feedback.append("Test file created.")
    elif result.get("test_file_exists"):
        score += 5
        feedback.append("Test file exists but timestamp check failed.")
    else:
        feedback.append("Test file not found.")

    # Criterion 3: Mockito Usage in Code (10 pts)
    test_content = result.get("test_content", "")
    has_mock_annotation = "@Mock" in test_content or "@InjectMocks" in test_content
    has_verify = "verify(" in test_content
    has_when = "when(" in test_content or "given(" in test_content
    
    if has_mock_annotation or (has_verify and has_when):
        score += 10
        feedback.append("Mockito usage detected.")
    else:
        feedback.append("No obvious Mockito usage in test code.")

    # Criterion 4: Baseline Tests Pass (20 pts)
    if result.get("baseline_tests_pass"):
        score += 20
        feedback.append("Tests compile and pass baseline.")
    else:
        feedback.append("Tests failed to compile or run against original code.")
        # If baseline fails, mutations imply nothing, so we stop scoring logic here mostly
    
    # Criterion 5, 6, 7: Mutation Testing (40 pts total)
    # Only applicable if baseline passed
    if result.get("baseline_tests_pass"):
        if result.get("mutant_a_caught"):
            score += 15
            feedback.append("Tests verified repository.save() call (Mutant A caught).")
        else:
            feedback.append("Tests failed to verify repository.save() was called.")

        if result.get("mutant_b_caught"):
            score += 15
            feedback.append("Tests verified logic branching (Mutant B caught).")
        else:
            feedback.append("Tests failed to verify logic branching/return values.")

        if result.get("mutant_c_caught"):
            score += 10
            feedback.append("Tests verified correct status values (Mutant C caught).")
        else:
            feedback.append("Tests failed to verify correct status values.")

    # Criterion 8: VLM Verification (10 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, num_samples=3)
        final = get_final_screenshot(traj)
        if final: frames.append(final)
        
        prompt = """
        You are verifying an agent working in IntelliJ IDEA.
        Look at these screenshots.
        1. Is the IntelliJ IDEA interface visible?
        2. Is there code visible related to 'PaymentService' or 'PaymentServiceTest'?
        3. Do you see JUnit test results (green/red bar)?
        
        Answer YES or NO for each.
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, images=frames)
            if vlm_resp and vlm_resp.get('success'):
                text = vlm_resp.get('response', '').lower()
                if "yes" in text and "intellij" in text:
                    vlm_score = 10
                    feedback.append("VLM verified IntelliJ usage.")
                else:
                    feedback.append("VLM could not verify IntelliJ usage.")
        except Exception:
            feedback.append("VLM check failed.")
    
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }