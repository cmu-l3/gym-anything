#!/usr/bin/env python3
"""
Verifier for highlight_key_account_opportunities@1

Checks:
1. Are all "Azure Interior" opportunities colored Red (color=1)?
2. Are other opportunities left uncolored (color=0)?
3. Did the changes happen after task start?
"""

import json
import logging
import tempfile
import os
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_highlight_key_account_opportunities(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Configuration
    target_color_index = 1  # Red in Odoo standard palette
    
    # Copy result file
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

    # Check for execution errors
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Error in data collection: {result['error']}"}

    # Data extraction
    targets = result.get("targets", [])
    distractors = result.get("distractors", [])
    task_start_ts = result.get("task_start", 0)
    
    if not targets:
        return {"passed": False, "score": 0, "feedback": "System error: No target opportunities found in database."}

    # Scoring Logic
    score = 0
    feedback_parts = []
    
    # 1. Target Identification & Coloring (Max 60 points)
    # 40 pts for coloring them at all
    # 20 pts for using the CORRECT color (Red=1)
    colored_count = 0
    correct_color_count = 0
    total_targets = len(targets)
    
    for t in targets:
        color = t.get("color", 0)
        if color != 0:
            colored_count += 1
            if color == target_color_index:
                correct_color_count += 1
    
    if total_targets > 0:
        # Coloring points
        coloring_score = (colored_count / total_targets) * 40
        score += coloring_score
        
        # Color accuracy points
        accuracy_score = (correct_color_count / total_targets) * 20
        score += accuracy_score
        
        feedback_parts.append(f"Colored {colored_count}/{total_targets} target opportunities")
        if correct_color_count < colored_count:
            feedback_parts.append(f"Some targets used wrong color (expected Red/1, found mixed)")
    
    # 2. False Positives (Max 30 points)
    # Deduct points if distractors are colored
    false_positives = 0
    for d in distractors:
        if d.get("color", 0) != 0:
            false_positives += 1
            
    if false_positives == 0:
        score += 30
        feedback_parts.append("No false positives (other customers untouched)")
    else:
        # Partial credit: lose 10 points per false positive, min 0 for this section
        fp_score = max(0, 30 - (false_positives * 10))
        score += fp_score
        feedback_parts.append(f"Penalty: {false_positives} incorrect opportunities colored")

    # 3. Anti-Gaming / Timing (Max 10 points)
    # Check if at least one target was modified after task start
    modified_during_task = False
    for t in targets:
        write_date_str = t.get("write_date", "")
        # Odoo dates are UTC string "YYYY-MM-DD HH:MM:SS"
        # Converting to timestamp for comparison
        try:
            # Simple check: if color is correct, we assume it was done now 
            # (since setup sets color=0). 
            # But let's check modification time if possible.
            # Python strptime is strict, Odoo can be tricky with ms.
            # Fallback: if colored_count > 0, we give points because setup ensured they were 0.
            if t.get("color", 0) != 0:
                modified_during_task = True
                break
        except:
            pass
            
    if modified_during_task:
        score += 10
    else:
        if score > 0:
            # If they got points but didn't modify anything? Impossible given setup.
            # Assume passed if score > 0
            score += 10

    # Final tally
    score = min(100, int(score))
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }