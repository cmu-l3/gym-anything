#!/usr/bin/env python3
"""Verifier for Surgical Scheduling & OR Utilization task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used (2+ signals required)."""
    if not gui_evidence:
        return False, 0.0, "No GUI evidence"
    signals = 0
    details = []
    if gui_evidence.get('mru_connection_count', 0) > 0:
        signals += 1
        details.append(f"MRU:{gui_evidence['mru_connection_count']}")
    if gui_evidence.get('sqldev_oracle_sessions', 0) > 0:
        signals += 1
        details.append(f"sessions:{gui_evidence['sqldev_oracle_sessions']}")
    if gui_evidence.get('sql_history_count', 0) > 0:
        signals += 1
        details.append(f"history:{gui_evidence['sql_history_count']}")
    
    gui_used = signals >= 2
    return gui_used, min(signals / 3, 1.0), "; ".join(details) or "No signals"

def verify_surgical_scheduling(traj, env_info, task_info):
    """
    Verify the Surgical Scheduling task completion.

    Scoring (100 pts total):
    1. Overlap Identification (25 pts):
       - Table exists & rows > 0 (10 pts)
       - Overlap arithmetic accurate (Room, Surgeon, Both) (15 pts)
    2. Procedure API (30 pts):
       - Procedure exists (5 pts)
       - Prevents overlaps via ORA-20001 (15 pts)
       - Allows clean inserts (10 pts)
    3. Utilization View / Gaps & Islands (30 pts):
       - View exists (10 pts)
       - Correctly merges overlapping intervals without double-counting (20 pts)
    4. CSV Export (5 pts)
    5. GUI Usage (10 pts)

    Pass threshold: 70 pts AND Procedure Prevents Overlap AND View Merges Correctly
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []

        # Extract result fields
        dbl_table_exists = result.get('dbl_table_exists', False)
        dbl_rows = result.get('dbl_rows', 0)
        dbl_room_overlap_correct = result.get('dbl_room_overlap_correct', False)
        dbl_surgeon_overlap_correct = result.get('dbl_surgeon_overlap_correct', False)
        dbl_both_overlap_correct = result.get('dbl_both_overlap_correct', False)
        
        proc_exists = result.get('proc_exists', False)
        proc_prevents_overlap = result.get('proc_prevents_overlap', False)
        proc_allows_clean = result.get('proc_allows_clean', False)
        
        view_exists = result.get('view_exists', False)
        view_merges_correctly = result.get('view_merges_correctly', False)
        
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        
        # 1. Overlap Identification (25 pts)
        if dbl_table_exists and dbl_rows > 0:
            score += 10
            feedback_parts.append(f"DOUBLE_BOOKINGS_LOG exists with {dbl_rows} rows (10/10)")
            
            logic_pts = 0
            if dbl_room_overlap_correct: logic_pts += 5
            if dbl_surgeon_overlap_correct: logic_pts += 5
            if dbl_both_overlap_correct: logic_pts += 5
            
            score += logic_pts
            feedback_parts.append(f"Overlap arithmetic correctness: {logic_pts}/15")
        else:
            feedback_parts.append("DOUBLE_BOOKINGS_LOG missing or empty (0/25)")

        # 2. Procedure API (30 pts)
        if proc_exists:
            score += 5
            feedback_parts.append("PROC_SCHEDULE_SURGERY exists (5/5)")
            if proc_prevents_overlap:
                score += 15
                feedback_parts.append("Procedure prevents overlaps correctly (15/15)")
            else:
                feedback_parts.append("Procedure failed to prevent overlap or raise correct exception (0/15)")
                
            if proc_allows_clean:
                score += 10
                feedback_parts.append("Procedure successfully inserts clean schedule (10/10)")
            else:
                feedback_parts.append("Procedure blocked valid non-overlapping schedule (0/10)")
        else:
            feedback_parts.append("PROC_SCHEDULE_SURGERY missing (0/30)")

        # 3. Utilization View (30 pts)
        if view_exists:
            score += 10
            feedback_parts.append("ROOM_UTILIZATION_VW exists (10/10)")
            if view_merges_correctly:
                score += 20
                feedback_parts.append("Gaps and Islands logic works correctly (20/20)")
            else:
                feedback_parts.append("View double-counted overlapping records instead of merging intervals (0/20)")
        else:
            feedback_parts.append("ROOM_UTILIZATION_VW missing (0/30)")

        # 4. CSV Export (5 pts)
        if csv_exists and csv_size > 50:
            score += 5
            feedback_parts.append("CSV export found and valid (5/5)")
        else:
            feedback_parts.append("CSV export missing or empty (0/5)")

        # 5. GUI Usage (10 pts)
        gui_used, gui_fraction, gui_details = _check_gui_usage(result.get('gui_evidence', {}))
        if gui_used:
            score += 10
            feedback_parts.append(f"GUI usage confirmed [{gui_details}] (10/10)")
        else:
            score += int(10 * gui_fraction)
            feedback_parts.append(f"Limited GUI usage evidence [{gui_details}] ({int(10 * gui_fraction)}/10)")

        # Final Verification
        key_criteria_met = proc_prevents_overlap and view_merges_correctly
        passed = (score >= 70) and key_criteria_met

        if not key_criteria_met:
            feedback_parts.append("FAILED: Key criteria not met (Must successfully prevent overlaps AND correctly merge time intervals)")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error during verification: {str(e)}"
        }