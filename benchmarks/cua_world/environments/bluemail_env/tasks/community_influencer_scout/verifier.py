#!/usr/bin/env python3
"""
Verifier for community_influencer_scout task.

Scoring Breakdown:
1. Folder Creation (10 pts): 'Scout-ILUG' exists.
2. Content Filtering (20 pts): Folder contains emails (checks count).
3. Flagging Accuracy (30 pts): F1 Score of flagging original threads vs replies.
   - Precision: Correctly Flagged / Total Flagged
   - Recall: Correctly Flagged / Total Original Threads
4. CSV Output (20 pts): CSV exists and contains data corresponding to the count of flagged items.
5. Draft Email (20 pts): Draft exists to correct recipient.

Total: 100
Pass Threshold: 70
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_community_influencer_scout(traj, env_info, task_info):
    """Verify the influencer scout task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # 1. Folder Creation (10 pts)
    if result.get("scout_folder_exists"):
        score += 10
        feedback_parts.append("Folder 'Scout-ILUG' created.")
    else:
        feedback_parts.append("Folder 'Scout-ILUG' NOT found.")

    # 2. Content Filtering (20 pts)
    # We expect some emails to be moved.
    email_count = result.get("emails_in_folder", 0)
    if email_count >= 5:
        score += 20
        feedback_parts.append(f"Folder populated ({email_count} emails).")
    elif email_count > 0:
        score += 10
        feedback_parts.append(f"Folder partially populated ({email_count} emails).")
    else:
        feedback_parts.append("Folder is empty.")

    # 3. Flagging Accuracy (30 pts)
    stats = result.get("flagging_stats", {})
    tp = stats.get("correctly_flagged", 0)
    fp = stats.get("incorrectly_flagged", 0) # Flagged but was a reply
    fn = stats.get("missed_flags", 0)       # Original thread but not flagged
    
    # F1 Score Calculation
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0
    
    # Scale F1 to 30 points
    flag_score = int(f1 * 30)
    score += flag_score
    
    if flag_score > 0:
        feedback_parts.append(f"Flagging Accuracy: {int(f1*100)}% (TP={tp}, FP={fp}, FN={fn}).")
    else:
        feedback_parts.append("Flagging failed (No correct flags or low accuracy).")

    # 4. CSV Output (20 pts)
    # Check if exists and if count roughly matches flagged count
    if result.get("csv_exists"):
        entries = result.get("csv_entries", [])
        entry_count = len(entries)
        
        # We give points if CSV exists and has content
        if entry_count > 0:
            score += 10
            feedback_parts.append(f"CSV file created with {entry_count} entries.")
            
            # Bonus 10 pts if count matches the number of flagged items (within tolerance)
            # Agents might include header row, so +1 is okay
            total_flagged = stats.get("total_flagged", 0)
            if abs(entry_count - total_flagged) <= 2 and total_flagged > 0:
                score += 10
                feedback_parts.append("CSV entry count matches flagged emails.")
            else:
                feedback_parts.append(f"CSV count ({entry_count}) mismatch with flagged count ({total_flagged}).")
        else:
             feedback_parts.append("CSV file exists but is empty.")
    else:
        feedback_parts.append("CSV file NOT found.")

    # 5. Draft Email (20 pts)
    if result.get("draft_exists"):
        score += 20
        feedback_parts.append("Outreach draft email found.")
    else:
        feedback_parts.append("No outreach draft found.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }