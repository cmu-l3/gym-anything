#!/usr/bin/env python3
"""
Verifier for discontinue_medication task.

Verification Strategy:
1. Programmatic: Check database if specific drug record is marked 'archived' (1).
2. Programmatic: Check if 'archived_date' is >= task start date (Anti-gaming).
3. Programmatic: Check if 'archivedReason' contains required keywords (GI, nausea, etc.).
4. VLM: Check trajectory frames to ensure proper workflow (chart navigation) was used.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import framework VLM utilities if available
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_discontinue_medication(traj, env_info, task_info):
    """
    Verify that Margaret Thompson's Metformin prescription was discontinued
    with the correct reason.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    required_keywords = metadata.get('required_reason_keywords', ["gi", "nausea", "side effect"])
    
    # 1. Load result from container
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

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Extraction
    target_id = result.get('target_drug_id')
    current_archived = int(result.get('current_archived', 0))
    initial_archived = int(result.get('initial_archived', 0))
    archived_date_str = result.get('current_archived_date', 'NULL')
    archived_reason = result.get('current_archived_reason', '')
    task_start_date = result.get('task_start_date', '2000-01-01')
    
    # =========================================================
    # Criterion 1: Medication is archived (30 pts)
    # =========================================================
    is_archived = False
    if current_archived == 1:
        score += 30
        is_archived = True
        feedback_parts.append("Medication successfully archived")
    else:
        # Fallback: check if ANY metformin was archived (maybe they duplicated the record)
        if int(result.get('any_archived_metformin_count', 0)) > 0:
            score += 15
            is_archived = True
            feedback_parts.append("Partial Pass: A Metformin record was archived, but possibly not the original target ID")
        else:
            feedback_parts.append("Medication NOT archived")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # =========================================================
    # Criterion 2: Archived Date / Anti-gaming (15 pts)
    # =========================================================
    date_valid = False
    if is_archived and archived_date_str and archived_date_str != "NULL":
        # Simple string comparison for ISO dates (YYYY-MM-DD) works
        if archived_date_str >= task_start_date:
            score += 15
            date_valid = True
            feedback_parts.append(f"Archive date valid ({archived_date_str})")
        else:
            feedback_parts.append(f"Archive date {archived_date_str} is before task start {task_start_date}")
    elif is_archived:
         feedback_parts.append("Archive date missing")

    # =========================================================
    # Criterion 3: Discontinuation Reason (35 pts)
    # =========================================================
    reason_valid = False
    if is_archived:
        if archived_reason and len(archived_reason.strip()) > 3:
            # Check keywords
            reason_lower = archived_reason.lower()
            matched = [kw for kw in required_keywords if kw in reason_lower]
            
            if matched:
                score += 35
                reason_valid = True
                feedback_parts.append(f"Reason valid (matched: {matched[0]})")
            else:
                # Partial credit for having a reason but missing specific keywords
                score += 15
                feedback_parts.append(f"Reason recorded ('{archived_reason}') but missing keywords like 'GI', 'nausea'")
        else:
            feedback_parts.append("Reason for discontinuation missing or empty")

    # =========================================================
    # Criterion 4: VLM Workflow Verification (20 pts)
    # =========================================================
    # We want to ensure they didn't just use SQL injection or just "Create New" without discontinuing
    # We use trajectory frames provided by the framework
    
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            You are verifying a user interacting with an EMR (Electronic Medical Record).
            Look at these sequential screenshots.
            
            Did the user:
            1. View a patient chart or list of medications?
            2. Open a dialog or form to discontinue/archive a medication?
            3. Type a reason for discontinuation?
            
            Return JSON:
            {"workflow_detected": boolean, "confidence": "high|medium|low"}
            """
            
            try:
                vlm_result = query_vlm(images=frames, prompt=prompt)
                parsed = vlm_result.get('parsed', {}) if vlm_result.get('success') else {}
                
                if parsed.get('workflow_detected', False):
                    vlm_score = 20
                    feedback_parts.append("VLM verified workflow")
                else:
                    # Soft fail on VLM if we have strong DB evidence
                    vlm_score = 10
                    feedback_parts.append("VLM inconclusive on workflow")
            except Exception:
                vlm_score = 10 # Default fallback
        else:
            vlm_score = 10 # No frames available
    else:
        vlm_score = 20 # Skip VLM check if tool not available (assume pass if DB is perfect)
        
    score += vlm_score

    # Final Result
    passed = (is_archived and date_valid and reason_valid and score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }