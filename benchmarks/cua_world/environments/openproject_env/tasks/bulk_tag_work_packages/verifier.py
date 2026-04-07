#!/usr/bin/env python3
"""
Verifier for bulk_tag_work_packages task.
Verifies that the agent correctly identified work packages with "Search" in the title
and applied the specific tag, while avoiding false positives.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_tag_work_packages(traj, env_info, task_info):
    """
    Verify the bulk tagging task.
    
    Metrics:
    1. Tag Creation (20 pts): The tag 'search-initiative' exists.
    2. Recall (40 pts): % of 'Search' WPs that got tagged.
    3. Precision (40 pts): % of tagged WPs that were actually 'Search' WPs.
       (If precision < 1.0, it means the agent tagged unrelated items).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract sets of IDs
    target_ids = set(result.get('target_ids', []))
    non_target_ids = set(result.get('non_target_ids', []))
    tagged_ids = set(result.get('tagged_ids', []))
    tag_exists = result.get('tag_exists', False)
    
    target_subjects = result.get('target_subjects', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Check Tag Creation (20 pts)
    if tag_exists:
        score += 20
        feedback_parts.append("Tag 'search-initiative' created/exists.")
    else:
        feedback_parts.append("Tag 'search-initiative' does not exist in the system.")
        # If tag doesn't exist, they couldn't have tagged anything.
        return {"passed": False, "score": score, "feedback": "\n".join(feedback_parts)}

    # 2. Check Recall (40 pts)
    # How many of the targets were actually tagged?
    if not target_ids:
        feedback_parts.append("Setup Error: No target work packages found in project.")
        return {"passed": False, "score": 0, "feedback": "Setup Error"}

    correctly_tagged = target_ids.intersection(tagged_ids)
    recall = len(correctly_tagged) / len(target_ids)
    recall_points = int(recall * 40)
    score += recall_points
    
    feedback_parts.append(f"Recall: {len(correctly_tagged)}/{len(target_ids)} target items tagged ({int(recall*100)}%).")
    
    # 3. Check Precision (40 pts)
    # Did we tag anything we shouldn't have?
    wrongly_tagged = non_target_ids.intersection(tagged_ids)
    
    if len(tagged_ids) == 0:
        precision_points = 0
        feedback_parts.append("Precision: No items were tagged.")
    else:
        # Precision = Correctly Tagged / Total Tagged
        precision = len(correctly_tagged) / len(tagged_ids)
        precision_points = int(precision * 40)
        score += precision_points
        feedback_parts.append(f"Precision: {len(correctly_tagged)}/{len(tagged_ids)} tagged items were correct ({int(precision*100)}%).")
        
    if len(wrongly_tagged) > 0:
        feedback_parts.append(f"Warning: {len(wrongly_tagged)} unrelated items were incorrectly tagged.")

    # Final Verification
    # We require 100% recall and 100% precision for a perfect pass on this task,
    # as filters are deterministic.
    passed = (score >= 90) # Allow minor fuzziness if mostly correct, but ideally 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": {
            "targets": len(target_ids),
            "tagged": len(tagged_ids),
            "correct": len(correctly_tagged),
            "incorrect": len(wrongly_tagged)
        }
    }