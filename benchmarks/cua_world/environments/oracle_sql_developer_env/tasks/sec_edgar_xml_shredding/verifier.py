#!/usr/bin/env python3
"""Verifier for SEC EDGAR XML Shredding task."""

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

def verify_sec_edgar_xml_shredding(traj, env_info, task_info):
    """
    Verify SEC EDGAR XML Shredding task completion.
    
    Scoring (100 pts total):
    1. XML Shredding (30 pts)
       - Table exists (10 pts)
       - Extracted rows > 0 (10 pts, full if 6)
       - Namespaces handled (0 null issuers) (10 pts)
    2. Relational Join / View (15 pts)
       - View exists (15 pts)
    3. Anomaly Detection and Correction (35 pts)
       - Anomaly Yes Count > 0 (10 pts, full 20 pts if all 3 found)
       - Corrected values math applied (7 pts, full 15 pts if all 3 correct)
    4. Export Artifact (10 pts)
       - CSV exported and size > 50 bytes (10 pts)
    5. GUI Usage (10 pts)
       - 2+ SQL Developer signals (10 pts)
       
    Pass Threshold: 70 pts AND extracted_table_exists AND corrected_view_exists AND anomaly_yes_count > 0
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/sec_edgar_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # 1. XML Shredding (30 points)
        extracted_table_exists = result.get("extracted_table_exists", False)
        extracted_count = int(result.get("extracted_count", 0))
        null_issuer_count = int(result.get("null_issuer_count", 99))
        
        if extracted_table_exists:
            score += 10
            feedback_parts.append("EXTRACTED_HOLDINGS table exists (10/10)")
            if extracted_count >= 6:
                score += 10
                feedback_parts.append("All XML nodes extracted successfully (10/10)")
            elif extracted_count > 0:
                score += 5
                feedback_parts.append(f"Partial XML extraction ({extracted_count} rows) (5/10)")
            else:
                feedback_parts.append("EXTRACTED_HOLDINGS is empty (0/10)")
                
            if null_issuer_count == 0 and extracted_count > 0:
                score += 10
                feedback_parts.append("XML namespaces handled correctly (no null issuer_names) (10/10)")
            else:
                feedback_parts.append(f"XML namespaces failed ({null_issuer_count} null issuer_names) (0/10)")
        else:
            feedback_parts.append("EXTRACTED_HOLDINGS table not found (0/30)")
            
        # 2. Relational Join / View (15 points)
        corrected_view_exists = result.get("corrected_view_exists", False)
        
        if corrected_view_exists:
            score += 15
            feedback_parts.append("VW_HOLDINGS_CORRECTED view created (15/15)")
        else:
            feedback_parts.append("VW_HOLDINGS_CORRECTED view not found (0/15)")

        # 3. Anomaly Detection and Correction (35 points)
        anomaly_yes_count = int(result.get("anomaly_yes_count", 0))
        corrected_math_count = int(result.get("corrected_math_count", 0))
        
        if anomaly_yes_count == 3:
            score += 20
            feedback_parts.append("Correctly identified all 3 thousands errors (20/20)")
        elif anomaly_yes_count > 0:
            score += 10
            feedback_parts.append(f"Partially identified thousands errors ({anomaly_yes_count} found) (10/20)")
        else:
            feedback_parts.append("No thousands errors detected (0/20)")
            
        if corrected_math_count == 3 and anomaly_yes_count == 3:
            score += 15
            feedback_parts.append("Corrected values computed properly (/1000) (15/15)")
        elif corrected_math_count > 0:
            score += 7
            feedback_parts.append("Corrected values logic partially applied (7/15)")
        else:
            feedback_parts.append("Corrected values logic missing or incorrect (0/15)")

        # 4. Export Artifact (10 points)
        csv_exists = result.get("csv_exists", False)
        csv_size = int(result.get("csv_size", 0))
        
        if csv_exists and csv_size > 50:
            score += 10
            feedback_parts.append("AAPL top holders CSV exported (10/10)")
        elif csv_exists:
            score += 5
            feedback_parts.append("AAPL top holders CSV exists but may be empty (5/10)")
        else:
            feedback_parts.append("AAPL top holders CSV not found (0/10)")

        # 5. GUI Usage (10 points)
        gui_evidence = result.get("gui_evidence", {})
        gui_used, gui_score_frac, gui_details = _check_gui_usage(gui_evidence)
        if gui_used:
            score += 10
            feedback_parts.append(f"GUI usage confirmed [{gui_details}] (10/10)")
        else:
            feedback_parts.append(f"Insufficient GUI usage evidence [{gui_details}] (0/10)")

        passed = score >= 70 and extracted_table_exists and corrected_view_exists and anomaly_yes_count > 0

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}