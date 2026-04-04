#!/usr/bin/env python3
"""
Verifier for smart_home_iot_use_case task.
Checks for valid UML Use Case diagram with specific actors, use cases, and relationships.
"""

import json
import tempfile
import os

def verify_smart_home_iot_use_case(traj, env_info, task_info):
    """Verify that the Use Case diagram was created correctly."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence (10 pts)
    if result.get('file_exists') and result.get('file_modified_after_start'):
        score += 10
        feedback_parts.append("File saved")
    else:
        feedback_parts.append("FAIL: File not saved")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    
    # 2. PNG Export (10 pts)
    if result.get('png_exists'):
        score += 10
        feedback_parts.append("PNG exported")
    else:
        feedback_parts.append("PNG missing")

    # 3. Actors (20 pts)
    actors = result.get('actors_count', 0)
    if actors >= 3:
        score += 20
        feedback_parts.append(f"Actors found: {actors}")
    elif actors >= 1:
        score += 10
        feedback_parts.append(f"Actors partial: {actors} (need 3+)")
    else:
        feedback_parts.append("No Actors found (use 'Stick Figure' shape)")

    # 4. Use Cases (20 pts)
    ucs = result.get('use_cases_count', 0)
    if ucs >= 5:
        score += 20
        feedback_parts.append(f"Use Cases found: {ucs}")
    elif ucs >= 2:
        score += 10
        feedback_parts.append(f"Use Cases partial: {ucs} (need 5+)")
    else:
        feedback_parts.append("No Use Cases found (use 'Ellipse' shape)")

    # 5. Relationships (Include/Extend) (30 pts)
    includes = result.get('includes_found', 0)
    extends = result.get('extends_found', 0)
    
    if includes >= 1:
        score += 15
        feedback_parts.append("<<include>> relationship found")
    else:
        feedback_parts.append("Missing <<include>> relationship")
        
    if extends >= 1:
        score += 15
        feedback_parts.append("<<extend>> relationship found")
    else:
        feedback_parts.append("Missing <<extend>> relationship")

    # 6. System Boundary (10 pts)
    if result.get('system_boundary_found'):
        score += 10
        feedback_parts.append("System boundary found")
    else:
        feedback_parts.append("Missing System Boundary")

    # Check text content for correctness
    terms = len(result.get('required_terms_found', []))
    if terms < 4:
        score = max(0, score - 10) # Penalty for generic/empty diagram
        feedback_parts.append(f"Low content relevance ({terms} terms found)")

    passed = score >= 60 and actors >= 1 and ucs >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }