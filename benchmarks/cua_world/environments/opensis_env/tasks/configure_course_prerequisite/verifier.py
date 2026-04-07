#!/usr/bin/env python3
import json
import os
import logging
import tempfile
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_configure_course_prerequisite(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the user configured 'Biology I' as a prerequisite for 'Anatomy & Physiology'.
    
    Criteria:
    1. A prerequisite record exists for the Anatomy course (was 0, now > 0).
    2. The prerequisite record specifically points to Biology I.
    """
    
    # 1. Setup access to container data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 2. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from environment."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Extract Metrics
    initial_count = int(result.get("initial_count", 0))
    current_count = int(result.get("current_count", 0))
    is_correct_prereq_linked = result.get("is_correct_prereq_linked", False)
    
    # 4. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion A: Action was taken (Count increased)
    # We expect count to go from 0 to 1 (or more, if they added others incorrectly too)
    if current_count > initial_count:
        score += 30
        feedback.append("Prerequisite record successfully created.")
    elif current_count == initial_count:
        feedback.append("No new prerequisite records were added.")
    else:
        feedback.append("Prerequisite count decreased (records deleted?).")
        
    # Criterion B: Correct Course Linked
    if is_correct_prereq_linked:
        score += 70
        feedback.append("Correct course (Biology I) identified and linked.")
    else:
        if current_count > initial_count:
            feedback.append("A prerequisite was added, but it was NOT 'Biology I'.")
        
    # Anti-gaming / Sanity check
    # If they added the correct one, but also deleted it (net zero change), the logic above handles it via current_count
    # Ideally, we want exact state: Is Biology I CURRENTLY a prerequisite?
    
    # Let's refine: If the correct link exists, that's the most important thing, 
    # even if count didn't change (e.g. if we failed to clear it initally).
    # But setup script clears it, so count change is a good proxy for "work done now".
    
    final_score = min(100, score)
    passed = (final_score >= 80) # Requires both criteria effectively (30+70)
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " ".join(feedback)
    }