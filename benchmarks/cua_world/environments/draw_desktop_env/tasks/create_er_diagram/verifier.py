#!/usr/bin/env python3
"""Verifier for create_er_diagram task.
Checks if a library management ER diagram was created with required entities and relationships.
"""

import json
import tempfile
import os


def verify_create_er_diagram(traj, env_info, task_info):
    """Verify that a library management ER diagram was created."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_shapes = metadata.get('min_shapes', 4)
    min_connections = metadata.get('min_connections', 3)

    # Copy result from container
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
    criteria_met = 0
    total_criteria = 7

    # Criterion 1: File exists (10 points)
    if result.get('file_exists'):
        score += 10
        criteria_met += 1
        feedback_parts.append("File saved")
    else:
        feedback_parts.append("FAIL: No diagram file found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: File has content (10 points)
    file_size = result.get('file_size', 0)
    if file_size > 500:
        score += 10
        criteria_met += 1
        feedback_parts.append(f"File size: {file_size} bytes")
    else:
        feedback_parts.append(f"File too small: {file_size} bytes")

    # Criterion 3: Has Book entity (15 points)
    if result.get('has_book'):
        score += 15
        criteria_met += 1
        feedback_parts.append("Book entity found")
    else:
        feedback_parts.append("Missing Book entity")

    # Criterion 4: Has Author entity (15 points)
    if result.get('has_author'):
        score += 15
        criteria_met += 1
        feedback_parts.append("Author entity found")
    else:
        feedback_parts.append("Missing Author entity")

    # Criterion 5: Has Member entity (15 points)
    if result.get('has_member'):
        score += 15
        criteria_met += 1
        feedback_parts.append("Member entity found")
    else:
        feedback_parts.append("Missing Member entity")

    # Criterion 6: Has Loan entity (15 points)
    if result.get('has_loan'):
        score += 15
        criteria_met += 1
        feedback_parts.append("Loan entity found")
    else:
        feedback_parts.append("Missing Loan entity")

    # Criterion 7: Has connections (20 points)
    num_connections = result.get('num_connections', 0)
    if num_connections >= min_connections:
        score += 20
        criteria_met += 1
        feedback_parts.append(f"Connections: {num_connections}/{min_connections}")
    elif num_connections >= 1:
        score += 10
        feedback_parts.append(f"Partial connections: {num_connections}/{min_connections}")
    else:
        feedback_parts.append(f"No connections drawn ({num_connections}/{min_connections})")

    # Bonus: attributes found
    total_attributes = result.get('total_attributes', 0)
    if total_attributes >= 4:
        feedback_parts.append(f"Attributes: {total_attributes} found")
    elif total_attributes > 0:
        feedback_parts.append(f"Few attributes: {total_attributes}")

    # Count entities found
    entities_found = sum([
        result.get('has_book', False),
        result.get('has_author', False),
        result.get('has_member', False),
        result.get('has_loan', False)
    ])

    # Structural validation: entity names must be inside vertex shapes,
    # not just in edge labels or random text
    entities_in_shapes = result.get('entities_in_shapes', entities_found)
    if entities_found > 0 and entities_in_shapes < entities_found:
        feedback_parts.append(
            f"Warning: {entities_found - entities_in_shapes} entities only in edge labels (not shapes)"
        )

    # Pass requirements:
    # 1. Score >= 60
    # 2. At least 3 entities found IN SHAPES (structural validation)
    # 3. At least 1 connection
    has_enough_entities = entities_in_shapes >= 3
    has_connections = num_connections >= 1

    passed = (score >= 60 and
              has_enough_entities and
              has_connections)

    if passed:
        if entities_found == 4 and num_connections >= min_connections:
            feedback_parts.append("Excellent ER diagram!")
        else:
            feedback_parts.append("ER diagram created successfully")
    else:
        reasons = []
        if not has_enough_entities:
            if entities_in_shapes < entities_found:
                reasons.append(
                    f"only {entities_in_shapes}/4 entities in shapes "
                    f"({entities_found} found but some only in edge labels)"
                )
            else:
                reasons.append(f"only {entities_found}/4 entities")
        if not has_connections:
            reasons.append("no connections")
        if score < 60:
            reasons.append(f"score {score} < 60")
        feedback_parts.append(f"FAILED: {'; '.join(reasons)}")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "file_exists": result.get('file_exists', False),
            "entities_found": entities_found,
            "entities_in_shapes": entities_in_shapes,
            "num_connections": num_connections,
            "total_attributes": total_attributes,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
