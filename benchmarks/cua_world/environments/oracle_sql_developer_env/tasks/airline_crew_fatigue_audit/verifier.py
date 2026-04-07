#!/usr/bin/env python3
"""Verifier for Airline Crew Fatigue Audit task."""

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
    return gui_used, min(signals / 2, 1.0), "; ".join(details) or "No signals"

def verify_airline_crew_fatigue_audit(traj, env_info, task_info):
    """
    Verify the completion of the Airline Crew Fatigue Audit task.
    
    Scoring structure (100 pts total):
    1. Rest View (15 pts): Exists (10 pts) + LEAD used (5 pts)
    2. Rolling View (15 pts): Exists (10 pts) + RANGE used (5 pts)
    3. Output Table (10 pts): Exists
    4. PL/SQL Procedure (10 pts): Exists
    5. Accuracy (30 pts): 
       - Rest violation count == 1 (15 pts)
       - Limit violation count == 1 (15 pts)
    6. CSV Export (10 pts): Exists and size > 0
    7. GUI Usage (10 pts): At least 2 signals detected
    
    Pass threshold: 70 points AND at least one of the views created + GUI used.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/aviation_audit_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Extract variables
        rest_vw_exists = result.get('rest_vw_exists', False)
        lead_used = result.get('lead_used', False)
        rolling_vw_exists = result.get('rolling_vw_exists', False)
        range_used = result.get('range_used', False)
        table_exists = result.get('table_exists', False)
        proc_exists = result.get('proc_exists', False)
        rest_violation_count = result.get('rest_violation_count', 0)
        limit_violation_count = result.get('limit_violation_count', 0)
        csv_exists = result.get('csv_exists', False)
        csv_size_bytes = result.get('csv_size_bytes', 0)
        
        # Validate Rest View (15 pts)
        if rest_vw_exists:
            score += 10
            feedback_parts.append("Rest View exists (10/10)")
            if lead_used:
                score += 5
                feedback_parts.append("LEAD() function correctly identified in Rest View (5/5)")
            else:
                feedback_parts.append("LEAD() function missing from Rest View (0/5)")
        else:
            feedback_parts.append("Rest View missing (0/15)")

        # Validate Rolling View (15 pts)
        if rolling_vw_exists:
            score += 10
            feedback_parts.append("Rolling View exists (10/10)")
            if range_used:
                score += 5
                feedback_parts.append("RANGE BETWEEN window correctly identified (5/5)")
            else:
                feedback_parts.append("RANGE BETWEEN missing from Rolling View (0/5)")
        else:
            feedback_parts.append("Rolling View missing (0/15)")

        # Validate Target Output Entities (20 pts)
        if table_exists:
            score += 10
            feedback_parts.append("Violation report table exists (10/10)")
        else:
            feedback_parts.append("Violation report table missing (0/10)")
            
        if proc_exists:
            score += 10
            feedback_parts.append("Audit procedure exists (10/10)")
        else:
            feedback_parts.append("Audit procedure missing (0/10)")

        # Validate Accuracy of Data Processing (30 pts)
        # We expect exactly 1 insufficient rest violation (Crew 101, Flight 2)
        if rest_violation_count == 1:
            score += 15
            feedback_parts.append("Correctly identified 1 Insufficient Rest violation (15/15)")
        elif rest_violation_count > 0:
            score += 5
            feedback_parts.append(f"Identified {rest_violation_count} Rest violations, expected 1 (5/15)")
        else:
            feedback_parts.append("No Insufficient Rest violations populated (0/15)")

        # We expect exactly 1 exceeded 28-day limit violation (Crew 102, Flight 12 crosses 100 hours)
        if limit_violation_count == 1:
            score += 15
            feedback_parts.append("Correctly identified 1 Exceeded 28-day Limit violation (15/15)")
        elif limit_violation_count > 0:
            score += 5
            feedback_parts.append(f"Identified {limit_violation_count} Limit violations, expected 1 (5/15)")
        else:
            feedback_parts.append("No Exceeded Limit violations populated (0/15)")

        # Validate CSV Export (10 pts)
        if csv_exists and csv_size_bytes > 20:
            score += 10
            feedback_parts.append("CSV report exported successfully (10/10)")
        else:
            feedback_parts.append("CSV report missing or empty (0/10)")

        # Validate GUI Usage (10 pts)
        gui_used, gui_fraction, gui_details = _check_gui_usage(result.get('gui_evidence', {}))
        gui_points = int(10 * gui_fraction)
        score += gui_points
        if gui_used:
            feedback_parts.append(f"GUI usage confirmed [{gui_details}] ({gui_points}/10)")
        else:
            feedback_parts.append(f"Insufficient GUI usage evidence [{gui_details}] ({gui_points}/10)")

        # Final evaluation
        passed = (score >= 70) and gui_used and (rest_vw_exists or rolling_vw_exists)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {e}"
        }