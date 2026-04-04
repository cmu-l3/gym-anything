#!/usr/bin/env python3
"""
Verifier for organize_classics_by_tag@1

Verification Logic:
1. Collection "History of Computing" must exist (10 pts)
2. Tag "classic-era" must exist (implicitly checked by usage)
3. Content Verification:
   - Correctly placed pre-1970 items in collection (30 pts)
   - Correctly excluded post-1970 items from collection (10 pts)
   - Correctly tagged pre-1970 items (40 pts)
   - Correctly excluded post-1970 items from tagging (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_classics(traj, env_info, task_info):
    """
    Verify the organization of classic papers.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for script errors
    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Evaluation script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # Extract metrics
    coll_exists = result.get('collection_exists', False)
    total_classics = result.get('total_classic_items', 10) # Default to 10 if read fails
    total_modern = result.get('total_modern_items', 8)
    
    classic_in_coll = result.get('classic_items_in_coll', 0)
    modern_in_coll = result.get('modern_items_in_coll', 0)
    
    classic_tagged = result.get('classic_items_tagged', 0)
    modern_tagged = result.get('modern_items_tagged', 0)

    # Criterion 1: Collection Exists (10 pts)
    if coll_exists:
        score += 10
        feedback_parts.append("Collection 'History of Computing' created")
    else:
        feedback_parts.append("Collection 'History of Computing' NOT found")

    # Criterion 2: Collection Contents (30 pts for classics)
    # 3 points per correct classic item (max 30)
    coll_points = min(30, classic_in_coll * 3)
    score += coll_points
    if classic_in_coll == total_classics:
        feedback_parts.append(f"All classics in collection ({classic_in_coll}/{total_classics})")
    elif classic_in_coll > 0:
        feedback_parts.append(f"Some classics in collection ({classic_in_coll}/{total_classics})")
    else:
        feedback_parts.append("No classics added to collection")

    # Criterion 3: Collection Purity (10 pts)
    # Deduct points if modern items are in collection
    if modern_in_coll == 0:
        score += 10
        feedback_parts.append("No modern papers in collection (Clean)")
    else:
        feedback_parts.append(f"Incorrectly added {modern_in_coll} modern papers to collection")

    # Criterion 4: Tagging Accuracy (40 pts)
    # 4 points per correct classic item tagged (max 40)
    tag_points = min(40, classic_tagged * 4)
    score += tag_points
    if classic_tagged == total_classics:
        feedback_parts.append(f"All classics tagged ({classic_tagged}/{total_classics})")
    elif classic_tagged > 0:
        feedback_parts.append(f"Some classics tagged ({classic_tagged}/{total_classics})")
    else:
        feedback_parts.append("No classics tagged")

    # Criterion 5: Tagging Purity (10 pts)
    if modern_tagged == 0:
        score += 10
        feedback_parts.append("No modern papers tagged (Clean)")
    else:
        feedback_parts.append(f"Incorrectly tagged {modern_tagged} modern papers")

    # Final Pass/Fail
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "collection_exists": coll_exists,
            "classic_in_coll": classic_in_coll,
            "classic_tagged": classic_tagged,
            "errors": modern_in_coll + modern_tagged
        }
    }