#!/usr/bin/env python3
"""
Verifier for diagrams.net create_flowchart task.
Checks if a login flowchart was created with the required elements.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.DEBUG)


def verify_create_flowchart(traj, env_info, task_info):
    """
    Verify that a login flowchart was created successfully.

    Checks:
    1. Diagram file exists and was saved
    2. Diagram contains sufficient shapes (min 7)
    3. Diagram contains connections between shapes (min 6)
    4. Diagram has required shape types (terminal, process, decision)
    5. Diagram contains expected text labels
    """

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    min_shapes = metadata.get('min_shapes', 7)
    min_connections = metadata.get('min_connections', 6)

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    score = 0
    feedback_parts = []
    criteria_met = 0
    total_criteria = 8

    # Criterion 1: File exists (15 points)
    if result.get('file_exists'):
        score += 15
        criteria_met += 1
        feedback_parts.append(f"File exists: {result.get('file_path', 'unknown')}")
    else:
        feedback_parts.append("FAIL: No diagram file found")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: File size indicates content (10 points)
    file_size = result.get('file_size', 0)
    if file_size > 1000:  # At least 1KB of content
        score += 10
        criteria_met += 1
        feedback_parts.append(f"File size OK: {file_size} bytes")
    else:
        feedback_parts.append(f"File too small: {file_size} bytes")

    # Criterion 3: Sufficient shapes (15 points)
    num_shapes = result.get('num_shapes', 0)
    if num_shapes >= min_shapes:
        score += 15
        criteria_met += 1
        feedback_parts.append(f"Shapes: {num_shapes}/{min_shapes}")
    elif num_shapes >= min_shapes // 2:
        score += 7
        feedback_parts.append(f"Partial shapes: {num_shapes}/{min_shapes}")
    else:
        feedback_parts.append(f"Insufficient shapes: {num_shapes}/{min_shapes}")

    # Criterion 4: Connections between shapes (15 points)
    num_connections = result.get('num_connections', 0)
    if num_connections >= min_connections:
        score += 15
        criteria_met += 1
        feedback_parts.append(f"Connections: {num_connections}/{min_connections}")
    elif num_connections >= min_connections // 2:
        score += 7
        feedback_parts.append(f"Partial connections: {num_connections}/{min_connections}")
    else:
        feedback_parts.append(f"Insufficient connections: {num_connections}/{min_connections}")

    # Criterion 5: Has terminal shapes (10 points)
    if result.get('has_terminal'):
        score += 10
        criteria_met += 1
        feedback_parts.append("Has terminal shapes")
    else:
        feedback_parts.append("Missing terminal shapes")

    # Criterion 6: Has process shapes (10 points)
    if result.get('has_process'):
        score += 10
        criteria_met += 1
        feedback_parts.append("Has process shapes")
    else:
        feedback_parts.append("Missing process shapes")

    # Criterion 7: Has decision shapes (10 points)
    if result.get('has_decision'):
        score += 10
        criteria_met += 1
        feedback_parts.append("Has decision shapes")
    else:
        feedback_parts.append("Missing decision shapes")

    # Criterion 8: Has expected text labels (15 points)
    text_criteria = 0
    text_labels = [
        ('has_start_text', 'Start'),
        ('has_username_text', 'Username'),
        ('has_password_text', 'Password'),
        ('has_valid_text', 'Valid'),
        ('has_login_text', 'Login/Success'),
        ('has_error_text', 'Error'),
        ('has_end_text', 'End')
    ]

    found_labels = []
    missing_labels = []
    for key, label in text_labels:
        if result.get(key):
            text_criteria += 1
            found_labels.append(label)
        else:
            missing_labels.append(label)

    # Give partial credit for text labels
    if text_criteria >= 5:
        score += 15
        criteria_met += 1
        feedback_parts.append(f"Text labels: {text_criteria}/{len(text_labels)}")
    elif text_criteria >= 3:
        score += 8
        feedback_parts.append(f"Partial labels: {text_criteria}/{len(text_labels)} - found: {', '.join(found_labels)}")
    else:
        feedback_parts.append(f"Few labels: {text_criteria}/{len(text_labels)} - missing: {', '.join(missing_labels[:3])}")

    # Determine pass/fail
    # CRITICAL: Must have minimum connections and shapes to pass
    # A flowchart without connections is not a valid flowchart
    has_minimum_connections = num_connections >= 3  # At least 3 arrows
    has_minimum_shapes = num_shapes >= min_shapes
    has_required_shape_types = (result.get('has_terminal') and
                                result.get('has_process') and
                                result.get('has_decision'))

    # Pass requires:
    # 1. Score >= 70 (stricter threshold)
    # 2. At least 6 criteria met
    # 3. At least 3 connections (arrows)
    # 4. All required shape types present
    passed = (score >= 70 and
              criteria_met >= 6 and
              has_minimum_connections and
              has_required_shape_types)

    if passed:
        if score >= 90:
            feedback_parts.append("Excellent flowchart!")
        elif score >= 80:
            feedback_parts.append("Good flowchart!")
        else:
            feedback_parts.append("Acceptable flowchart")
    else:
        # Provide specific failure reasons
        failure_reasons = []
        if not has_minimum_connections:
            failure_reasons.append(f"need at least 3 connections (have {num_connections})")
        if not has_required_shape_types:
            missing_types = []
            if not result.get('has_terminal'):
                missing_types.append("terminal")
            if not result.get('has_process'):
                missing_types.append("process")
            if not result.get('has_decision'):
                missing_types.append("decision")
            failure_reasons.append(f"missing shape types: {', '.join(missing_types)}")
        if score < 70:
            failure_reasons.append(f"score {score} < 70")
        if criteria_met < 6:
            failure_reasons.append(f"only {criteria_met}/6 criteria met")

        feedback_parts.append(f"FAILED: {'; '.join(failure_reasons)}")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "file_exists": result.get('file_exists', False),
            "num_shapes": num_shapes,
            "num_connections": num_connections,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
