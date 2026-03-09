#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_jicofo_logs(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Joined the meeting 'MergerDiscussion' (triggering a log entry).
    2. Extracted a valid log line confirming this from the Jicofo container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Fetch Task Results Metadata
    # ------------------------------------------------------------------
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=True) as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            tmp.seek(0)
            task_result = json.load(tmp)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}

    # ------------------------------------------------------------------
    # 2. Check if Meeting Occurred (30 pts)
    # ------------------------------------------------------------------
    room_active = task_result.get("room_active_in_logs", False)
    if room_active:
        score += 30
        feedback_parts.append("Meeting 'MergerDiscussion' detected in system logs.")
    else:
        feedback_parts.append("Meeting 'MergerDiscussion' NOT detected in logs. Did you join it?")

    # ------------------------------------------------------------------
    # 3. Check Agent's Output File (50 pts + 20 pts accuracy)
    # ------------------------------------------------------------------
    output_exists = task_result.get("output_exists", False)
    file_created = task_result.get("file_created_during_task", False)
    
    agent_lines = []
    ground_truth_lines = []
    
    if output_exists and file_created:
        # Fetch Agent Output
        with tempfile.NamedTemporaryFile(delete=True) as tmp_out:
            try:
                copy_from_env("/home/ga/merger_audit_log.txt", tmp_out.name)
                tmp_out.seek(0)
                agent_content = tmp_out.read().decode('utf-8', errors='ignore')
                agent_lines = [line.strip() for line in agent_content.splitlines() if line.strip()]
            except Exception:
                pass

        # Fetch Ground Truth Logs (captured by export script)
        with tempfile.NamedTemporaryFile(delete=True) as tmp_gt:
            try:
                copy_from_env("/tmp/ground_truth_logs.txt", tmp_gt.name)
                tmp_gt.seek(0)
                gt_content = tmp_gt.read().decode('utf-8', errors='ignore')
                ground_truth_lines = [line.strip() for line in gt_content.splitlines() if line.strip()]
            except Exception:
                pass
        
        # Validation Logic
        if not agent_lines:
            feedback_parts.append("Output file is empty.")
        else:
            # Check content
            found_valid_line = False
            first_line = agent_lines[0]
            
            # Criterion: Must contain meeting name
            if "MergerDiscussion" in first_line:
                score += 30
                found_valid_line = True
                feedback_parts.append("Output contains correct meeting name.")
            else:
                feedback_parts.append("Output file missing meeting name 'MergerDiscussion'.")

            # Criterion: Must look like a log line (Jicofo logs usually have timestamps)
            # e.g., "Jicofo 2023-10-01..." or "[FocusManager]"
            if any(indicator in first_line for indicator in ["Jicofo", "FocusManager", "org.jitsi", "INFO", ":"]):
                score += 20
                feedback_parts.append("Output appears to be a valid log entry.")
            else:
                feedback_parts.append("Output does not look like a raw log line.")

            # Accuracy (Bonus): Is it one of the actual lines we found?
            # We do a loose containment check because whitespace/color codes might differ
            is_ground_truth_match = False
            for gt_line in ground_truth_lines:
                # Remove timestamps or IDs for fuzzy match if needed, but simple containment is usually enough
                # if the agent just copied the line.
                if first_line in gt_line or gt_line in first_line:
                    is_ground_truth_match = True
                    break
            
            if is_ground_truth_match:
                score += 20
                feedback_parts.append("Log line matches verification ground truth.")
            elif found_valid_line:
                # Partial credit if it looks right but exact match failed (maybe diff timestamp/formatting)
                score += 10 
                feedback_parts.append("Log line looks plausible but didn't exact-match ground truth capture.")

    else:
        feedback_parts.append("Output file not created or not modified during task.")

    # ------------------------------------------------------------------
    # 4. Final Scoring
    # ------------------------------------------------------------------
    # Pass threshold: 80 points (Needs Room Creation + Valid Log Extraction)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }