#!/usr/bin/env python3
"""
Verifier for reclassify_item_types task.

Verification Criteria:
1. "Attention Is All You Need" -> conferencePaper (25 pts)
2. "Deep Residual Learning..." -> conferencePaper (25 pts)
3. "ImageNet Classification..." -> conferencePaper (25 pts)
4. "The Mathematical Theory of Communication" -> book (15 pts)
5. No collateral damage (other items remain journalArticle) (10 pts)

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reclassify_item_types(traj, env_info, task_info):
    """Verify that item types were correctly updated."""
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate
    score = 0
    feedback_parts = []
    
    if not result.get("db_accessible", False):
        return {"passed": False, "score": 0, "feedback": "Could not access Zotero database to verify results."}

    targets = result.get("targets", {})
    
    # Check specific papers
    # Mapping titles to short names for feedback
    paper_map = {
        "Attention Is All You Need": "Attention",
        "Deep Residual Learning for Image Recognition": "ResNet",
        "ImageNet Classification": "ImageNet",
        "The Mathematical Theory of Communication": "Shannon Book"
    }

    # Points mapping from task.json metadata (or hardcoded here for safety)
    points_map = {
        "Attention Is All You Need": 25,
        "Deep Residual Learning for Image Recognition": 25,
        "ImageNet Classification": 25,
        "The Mathematical Theory of Communication": 15
    }

    for title_frag, info in targets.items():
        short_name = next((v for k, v in paper_map.items() if k in title_frag), "Paper")
        pts = next((v for k, v in points_map.items() if k in title_frag), 0)
        
        if not info.get("found"):
            feedback_parts.append(f"{short_name}: Not found in DB")
            continue

        if info.get("correct"):
            score += pts
            feedback_parts.append(f"{short_name}: Correct ({info['current_type']})")
        else:
            feedback_parts.append(f"{short_name}: Incorrect (is {info['current_type']}, expected {info['expected_type']})")

    # Check collateral damage
    damage = result.get("collateral_damage", 0)
    if damage == 0:
        score += 10
        feedback_parts.append("No collateral damage")
    else:
        feedback_parts.append(f"Collateral damage: {damage} other items modified")
        # No points for this section

    # 3. Finalize
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }