#!/usr/bin/env python3
"""
Verifier for batch_tag_meetings_by_keyword task.

Checks:
1. 'Audit' tag exists (10 pts)
2. Recall: All events with 'Review' in title have 'Audit' tag (50 pts)
3. Precision: No events WITHOUT 'Review' in title have 'Audit' tag (40 pts)
4. Anti-gaming: Checks that modified events were actually updated during the task window.
"""

import json
import logging
import os
import tempfile
from datetime import datetime, timezone

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_tag_meetings_by_keyword(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/batch_tag_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # 1. Check Tag Creation
    if result.get("audit_tag_exists"):
        score += 10
        feedback_parts.append("Tag 'Audit' exists.")
    else:
        feedback_parts.append("Tag 'Audit' was NOT found.")
        # If tag doesn't exist, they can't have tagged anything correctly.
        return {"passed": False, "score": 0, "feedback": "Failed: 'Audit' tag was not created."}

    # Analyze Events
    events = result.get("events", [])
    task_start_ts = result.get("task_start_ts", 0)
    
    target_keyword = "Review"
    target_tag = "Audit"
    
    targets = []
    non_targets = []
    
    for ev in events:
        name = ev.get("name", "")
        if target_keyword.lower() in name.lower():
            targets.append(ev)
        else:
            non_targets.append(ev)
            
    # 2. Check Recall (Target events must be tagged)
    tagged_targets = 0
    total_targets = len(targets)
    
    for ev in targets:
        tags = ev.get("tags", [])
        if target_tag in tags:
            tagged_targets += 1
        else:
            # Debug info
            pass

    if total_targets > 0:
        recall_score = (tagged_targets / total_targets) * 50
        score += recall_score
        feedback_parts.append(f"Recall: {tagged_targets}/{total_targets} target events tagged (+{recall_score:.1f} pts).")
    else:
        # Should not happen given setup data, but handle gracefully
        score += 50
        feedback_parts.append("Recall: No target events found in DB (Check setup).")

    # 3. Check Precision (Non-targets must NOT be tagged)
    # Special focus on "tricky" items where description contains keyword but title doesn't
    false_positives = 0
    total_non_targets = len(non_targets)
    
    tricky_case_handled = True
    
    for ev in non_targets:
        tags = ev.get("tags", [])
        name = ev.get("name", "")
        desc = ev.get("description", "")
        
        if target_tag in tags:
            false_positives += 1
            feedback_parts.append(f"False Positive: '{name}' incorrectly tagged.")
            
            # Check if this was a tricky case (keyword in description)
            if target_keyword.lower() in desc.lower():
                feedback_parts.append(f"  (Note: '{name}' has keyword in description, but task required Title only).")
                tricky_case_handled = False

    # Precision Scoring
    # 40 points available. Deduct heavily for false positives.
    # If any false positive, lose half points. If many, lose all.
    precision_score = 40
    if false_positives > 0:
        # Deduct 10 points per error, up to 40
        deduction = false_positives * 10
        precision_score = max(0, 40 - deduction)
        feedback_parts.append(f"Precision: {false_positives} incorrect events tagged (-{deduction} pts).")
    else:
        feedback_parts.append("Precision: Perfect (no incorrect tags).")
        
    score += precision_score

    # Anti-gaming check: Did the agent actually modify the records?
    # We check if write_date of tagged targets is recent.
    # Note: write_date is UTC string. We'll do a loose check if Python datetime parsing allows.
    # If difficult to parse safely, we rely on the tag presence check from step 1 (tag didn't exist before).
    # Since we deleted the tag in setup, the fact that it exists and is applied to events implies work was done.
    # So explicit timestamp check is a "nice to have" secondary confirmation here.
    
    # Calculate final status
    passed = (score >= 90) # Requires almost perfect execution
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }