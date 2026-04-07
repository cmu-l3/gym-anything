#!/usr/bin/env python3
"""Verifier for calculate_physics_problems task."""

import json
import os
import tempfile
import re

def verify_calculate_physics_problems(traj, env_info, task_info):
    """Verify that the physics answers text file was created with the correct answers."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract the result JSON from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/physics_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    file_exists = result.get('file_exists', False)
    file_modified = result.get('file_modified', False)
    file_size = result.get('file_size', 0)
    content = result.get('content', '')

    # Criterion 1: Check file existence and creation timestamp
    if file_exists:
        score += 10
        feedback.append("physics_answers.txt exists")
        if file_modified:
            score += 5
            feedback.append("File created/modified during task")
        else:
            feedback.append("File modification time check failed")
            
        if file_size > 50:
            score += 5
            feedback.append(f"File has meaningful size ({file_size} bytes)")
        else:
            feedback.append(f"File too small ({file_size} bytes)")
    else:
        feedback.append("FAIL: physics_answers.txt not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    ground_truth = {
        1: 60.03,
        2: 28.80,
        3: 2521.50,
        4: 123.48,
        5: 21.82
    }
    
    tolerances = {
        1: 0.05,
        2: 0.05,
        3: 0.50,
        4: 0.05,
        5: 0.05
    }

    correct_count = 0

    # Criterion 2: Check each physics problem answer inside the content
    for prob_num, expected_val in ground_truth.items():
        # Match "Problem N: [answer]" ignoring possible spacing variations
        pattern = rf'Problem\s*{prob_num}\s*:\s*([\d.]+)'
        match = re.search(pattern, content, re.IGNORECASE)
        
        if match:
            val_str = match.group(1)
            try:
                val = float(val_str)
                tol = tolerances[prob_num]
                if abs(val - expected_val) <= tol:
                    score += 16
                    correct_count += 1
                    feedback.append(f"Problem {prob_num} correct ({val})")
                else:
                    feedback.append(f"Problem {prob_num} incorrect: expected {expected_val}, got {val}")
            except ValueError:
                feedback.append(f"Problem {prob_num} value not parsed: {val_str}")
        else:
            feedback.append(f"Problem {prob_num} not found or malformed in file")

    # Pass condition: must have >= 65 total score, file must exist, and at least 3 answers must be correct
    passed = (score >= 65 and file_exists and correct_count >= 3)

    if passed:
        feedback.append("Task successfully completed!")
    else:
        feedback.append(f"FAILED: Score {score} < 65 or correct count {correct_count} < 3")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "file_exists": file_exists,
            "correct_count": correct_count
        }
    }