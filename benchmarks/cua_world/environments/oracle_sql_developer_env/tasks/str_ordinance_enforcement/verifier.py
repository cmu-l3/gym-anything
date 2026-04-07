#!/usr/bin/env python3
"""Verifier for Short-Term Rental Ordinance Enforcement task."""

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

def verify_str_ordinance_enforcement(traj, env_info, task_info):
    """
    Verify short-term rental ordinance enforcement task completion.

    Scoring (100 pts total):
    1. Regex Extraction Implementation (20 pts):
       - vw_cleaned_exists -> 5 pts
       - extracted_count >= 8 -> 15 pts
    2. License Status Validation (15 pts):
       - unlicensed_detected > 0 -> 7.5 pts
       - expired_detected > 0 -> 7.5 pts
    3. Duplicate License Detection (15 pts):
       - duplicate_detected > 0 -> 15 pts
    4. Commercial/Occupancy Math Logic (20 pts):
       - commercial_detected > 0 -> 10 pts
       - over_limit_detected > 0 -> 10 pts
    5. Materialized View Creation (15 pts):
       - mv_violations_exists -> 15 pts
    6. CSV Export & GUI (15 pts):
       - csv_exists & csv_size > 50 -> 10 pts
       - GUI used -> 5 pts

    Pass threshold: 70 pts AND vw_cleaned_exists AND mv_violations_exists.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/str_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Read result fields
        vw_cleaned_exists = result.get('vw_cleaned_exists', False)
        extracted_count = result.get('extracted_count', 0)
        mv_violations_exists = result.get('mv_violations_exists', False)
        unlicensed_detected = result.get('unlicensed_detected', 0)
        expired_detected = result.get('expired_detected', 0)
        duplicate_detected = result.get('duplicate_detected', 0)
        commercial_detected = result.get('commercial_detected', 0)
        over_limit_detected = result.get('over_limit_detected', 0)
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        gui_evidence = result.get('gui_evidence', {})

        # 1. Regex Extraction (20 pts)
        if vw_cleaned_exists:
            score += 5
            feedback_parts.append("VW_CLEANED_LISTINGS exists (+5)")
            if extracted_count >= 8:
                score += 15
                feedback_parts.append(f"Regex successfully extracted {extracted_count} licenses (+15)")
            elif extracted_count > 0:
                score += 7
                feedback_parts.append(f"Regex partially extracted licenses ({extracted_count}) (+7)")
            else:
                feedback_parts.append("No valid licenses extracted via regex (0/15)")
        else:
            feedback_parts.append("VW_CLEANED_LISTINGS missing (0/20)")

        # 2. License Status (15 pts)
        if unlicensed_detected > 0:
            score += 7.5
            feedback_parts.append("UNLICENSED correctly flagged (+7.5)")
        else:
            feedback_parts.append("UNLICENSED not flagged (0/7.5)")
            
        if expired_detected > 0:
            score += 7.5
            feedback_parts.append("EXPIRED/REVOKED correctly flagged (+7.5)")
        else:
            feedback_parts.append("EXPIRED/REVOKED not flagged (0/7.5)")

        # 3. Duplicate License (15 pts)
        if duplicate_detected > 0:
            score += 15
            feedback_parts.append("DUPLICATE_LICENSE correctly flagged via window function (+15)")
        else:
            feedback_parts.append("DUPLICATE_LICENSE not flagged (0/15)")

        # 4. Commercial/Occupancy Logic (20 pts)
        if commercial_detected > 0:
            score += 10
            feedback_parts.append("COMMERCIAL_OPERATOR correctly flagged (+10)")
        else:
            feedback_parts.append("COMMERCIAL_OPERATOR not flagged (0/10)")
            
        if over_limit_detected > 0:
            score += 10
            feedback_parts.append("OVER_LIMIT correctly flagged (+10)")
        else:
            feedback_parts.append("OVER_LIMIT not flagged (0/10)")

        # 5. MV Creation (15 pts)
        if mv_violations_exists:
            score += 15
            feedback_parts.append("MV_STR_VIOLATIONS created successfully (+15)")
        else:
            feedback_parts.append("MV_STR_VIOLATIONS missing (0/15)")

        # 6. CSV & GUI (15 pts)
        if csv_exists and csv_size > 50:
            score += 10
            feedback_parts.append("CSV exported successfully (+10)")
        elif csv_exists:
            score += 5
            feedback_parts.append("CSV exists but is empty/too small (+5)")
        else:
            feedback_parts.append("CSV missing (0/10)")
            
        gui_used, gui_score_mult, gui_details = _check_gui_usage(gui_evidence)
        if gui_used:
            score += 5
            feedback_parts.append(f"GUI usage confirmed [{gui_details}] (+5)")
        else:
            feedback_parts.append(f"No GUI usage detected [{gui_details}] (0/5)")

        # Final Evaluation
        passed = score >= 70 and vw_cleaned_exists and mv_violations_exists
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}