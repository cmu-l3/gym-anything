#!/usr/bin/env python3
"""
Verifier for Batch Transfer Fulfillment task in Odoo.
Checks if the agent successfully enabled the batch transfer feature,
grouped the correct delivery orders into a batch, ignored distractors,
and validated the batch.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_transfer_fulfillment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_customers = metadata.get('target_customers', [])
    distractor_customers = metadata.get('distractor_customers', [])
    pass_threshold = metadata.get('pass_threshold', 70)

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Error during data extraction: {result['error']}"}

    # Criterion 1: Settings Configuration (10 pts)
    if result.get("batch_feature_enabled", False):
        score += 10
        feedback_parts.append("✅ Batch Transfers feature enabled (+10)")
    else:
        feedback_parts.append("❌ Batch Transfers feature NOT enabled")

    # Criterion 2: Batch Creation (20 pts)
    batches = result.get("batches", [])
    if len(batches) > 0:
        score += 20
        feedback_parts.append(f"✅ Batch Transfer created (Found {len(batches)}) (+20)")
    else:
        feedback_parts.append("❌ No Batch Transfer created")

    # Analyze pickings
    pickings = result.get("pickings", {})
    
    # Criterion 3: Correct Grouping (30 pts)
    # Target customers must all share the SAME batch_id, and it must not be None
    target_batch_ids = set()
    targets_assigned = 0
    targets_validated = 0
    
    for tc in target_customers:
        p_data = pickings.get(tc, {})
        b_id = p_data.get("batch_id")
        state = p_data.get("state")
        
        if b_id:
            target_batch_ids.add(b_id)
            targets_assigned += 1
            
        if state == "done":
            targets_validated += 1

    if targets_assigned == len(target_customers) and len(target_batch_ids) == 1:
        score += 30
        feedback_parts.append("✅ All 4 target delivery orders assigned to a single Batch Transfer (+30)")
    elif targets_assigned > 0:
        partial = int((targets_assigned / len(target_customers)) * 15)
        score += partial
        feedback_parts.append(f"⚠️ Partial: {targets_assigned}/4 targets assigned to batch (+{partial})")
    else:
        feedback_parts.append("❌ Target delivery orders were not batched")

    # Criterion 4: Distractors Ignored (20 pts)
    # Distractors should NOT have a batch_id
    distractors_ignored = 0
    for dc in distractor_customers:
        p_data = pickings.get(dc, {})
        if not p_data.get("batch_id") and p_data.get("state") in ["assigned", "confirmed"]:
            distractors_ignored += 1

    if distractors_ignored == len(distractor_customers):
        score += 20
        feedback_parts.append("✅ International distractor orders successfully ignored (+20)")
    else:
        # Anti-gaming penalty if they just selected all
        feedback_parts.append(f"❌ Distractor orders were improperly batched or validated")

    # Criterion 5: Batch Validation (20 pts)
    # Targets should be in 'done' state
    if targets_validated == len(target_customers):
        score += 20
        feedback_parts.append("✅ Batch (and underlying target orders) fully validated (+20)")
    elif targets_validated > 0:
        partial = int((targets_validated / len(target_customers)) * 10)
        score += partial
        feedback_parts.append(f"⚠️ Partial: {targets_validated}/4 target orders validated (+{partial})")
    else:
        feedback_parts.append("❌ Target orders were not validated/shipped")

    passed = score >= pass_threshold
    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }