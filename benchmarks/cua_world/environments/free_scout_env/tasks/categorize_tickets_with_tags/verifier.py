#!/usr/bin/env python3
"""
Verifier for categorize_tickets_with_tags task.

Verification Criteria:
1. 'Acme VIP' tag exists (10 pts)
2. 'Urgent' tag exists (10 pts)
3. Acme conversation 1 is tagged 'Acme VIP' (25 pts)
4. Acme conversation 2 is tagged 'Acme VIP' (25 pts)
5. Critical conversation is tagged 'Urgent' (20 pts)
6. No false positives (no other conversations tagged with these tags) (10 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_categorize_tickets(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    
    tags = result.get('tags', {})
    gt = result.get('ground_truth', {})
    actual = result.get('actual_state', {})

    # 1. Verify Tags Exist
    acme_tag_id = tags.get('acme_vip_id')
    urgent_tag_id = tags.get('urgent_id')

    if acme_tag_id and acme_tag_id != "":
        score += 10
        feedback_parts.append("'Acme VIP' tag created")
    else:
        feedback_parts.append("'Acme VIP' tag NOT found")

    if urgent_tag_id and urgent_tag_id != "":
        score += 10
        feedback_parts.append("'Urgent' tag created")
    else:
        feedback_parts.append("'Urgent' tag NOT found")

    # 2. Verify Acme Conversation Assignments
    gt_acme_ids = set(gt.get('acme_ids', []))
    tagged_acme_ids = set(actual.get('tagged_acme_ids', []))

    # Calculate points per correct Acme tag (50 pts total for this section)
    # We have 2 targets. Each is worth 25 pts.
    correct_acme_tags = 0
    for target_id in gt_acme_ids:
        if target_id in tagged_acme_ids:
            score += 25
            correct_acme_tags += 1
    
    if correct_acme_tags == len(gt_acme_ids):
        feedback_parts.append(f"All Acme tickets tagged ({correct_acme_tags}/{len(gt_acme_ids)})")
    else:
        feedback_parts.append(f"Acme tickets missing tags ({correct_acme_tags}/{len(gt_acme_ids)})")

    # 3. Verify Urgent Conversation Assignment
    gt_urgent_id = gt.get('urgent_id')
    tagged_urgent_ids = set(actual.get('tagged_urgent_ids', []))

    if gt_urgent_id in tagged_urgent_ids:
        score += 20
        feedback_parts.append("Urgent ticket tagged correctly")
    else:
        feedback_parts.append("Urgent ticket NOT tagged")

    # 4. Verify False Positives (10 pts)
    # Check if any non-target IDs were tagged with Acme VIP
    false_positive_acme = tagged_acme_ids - gt_acme_ids
    # Check if any non-target IDs were tagged with Urgent (assuming gt_urgent_id is a single int)
    gt_urgent_set = {gt_urgent_id} if gt_urgent_id else set()
    false_positive_urgent = tagged_urgent_ids - gt_urgent_set

    false_positives_count = len(false_positive_acme) + len(false_positive_urgent)

    if false_positives_count == 0:
        score += 10
        feedback_parts.append("No incorrect tags applied")
    else:
        feedback_parts.append(f"Found {false_positives_count} incorrectly tagged tickets")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }