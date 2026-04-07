#!/usr/bin/env python3
"""Verifier for AML Transaction Pattern Analysis task."""

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

def verify_aml_transaction_pattern_analysis(traj, env_info, task_info):
    """
    Verify AML Transaction Pattern Analysis task completion.
    
    Scoring (100 pts total):
    1. Structuring Detection (30 pts):
       - STRUCTURING_ALERTS populated (10 pts)
       - MATCH_RECOGNIZE used (10 pts)
       - Known smurf accounts flagged (10 pts)
    2. Fund Flow Tracing (15 pts):
       - FUND_FLOW_VW exists (5 pts)
       - CONNECT BY or RECURSIVE CTE used (10 pts)
    3. Layering Detection (15 pts):
       - LAYERING_ALERTS populated (8 pts)
       - Known layering accounts flagged (7 pts)
    4. Risk Scoring (10 pts):
       - CUSTOMER_RISK_SCORE_VW exists (10 pts)
    5. SAR Generation (18 pts):
       - PROC_GENERATE_SAR_RECOMMENDATIONS exists (5 pts)
       - SAR_RECOMMENDATIONS populated + LISTAGG narrative (8 pts)
       - Threshold (score >= 60) enforced correctly (5 pts)
    6. CSV Export (7 pts):
       - File exists and size > 50 bytes (7 pts)
    7. GUI Usage (5 pts):
       - GUI evidence found (5 pts)

    Pass threshold: 60 pts AND structuring alerts populated AND match_recognize used.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/aml_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # 1. Structuring
        struct_exists = result.get('structuring_alerts_exists', False)
        struct_rows = result.get('structuring_rows', 0)
        match_recognize_used = result.get('match_recognize_used', False)
        smurfs_found = result.get('smurf_accounts_found', 0)
        
        if struct_exists and struct_rows > 0:
            score += 10
            feedback_parts.append("Structuring alerts populated (10/10)")
        else:
            feedback_parts.append("Structuring alerts missing/empty (0/10)")
            
        if match_recognize_used:
            score += 10
            feedback_parts.append("MATCH_RECOGNIZE used (10/10)")
        else:
            feedback_parts.append("MATCH_RECOGNIZE NOT used (0/10)")
            
        if smurfs_found > 0:
            score += 10
            feedback_parts.append(f"Known smurfs flagged: {smurfs_found} (10/10)")
        else:
            feedback_parts.append("No known smurf accounts flagged (0/10)")

        # 2. Fund Flow
        fund_flow_exists = result.get('fund_flow_vw_exists', False)
        connect_by_used = result.get('connect_by_used', False)
        
        if fund_flow_exists:
            score += 5
            feedback_parts.append("Fund flow view exists (5/5)")
        else:
            feedback_parts.append("Fund flow view missing (0/5)")
            
        if connect_by_used:
            score += 10
            feedback_parts.append("CONNECT BY/RECURSIVE used (10/10)")
        else:
            feedback_parts.append("Hierarchical query NOT used (0/10)")

        # 3. Layering
        layering_exists = result.get('layering_alerts_exists', False)
        layering_rows = result.get('layering_rows', 0)
        layers_found = result.get('layering_accounts_found', 0)
        
        if layering_exists and layering_rows > 0:
            score += 8
            feedback_parts.append("Layering alerts populated (8/8)")
        else:
            feedback_parts.append("Layering alerts missing/empty (0/8)")
            
        if layers_found > 0:
            score += 7
            feedback_parts.append("Known layering accounts flagged (7/7)")
        else:
            feedback_parts.append("Known layering accounts NOT flagged (0/7)")

        # 4. Risk Scoring
        risk_vw_exists = result.get('risk_score_vw_exists', False)
        if risk_vw_exists:
            score += 10
            feedback_parts.append("Risk score view exists (10/10)")
        else:
            feedback_parts.append("Risk score view missing (0/10)")

        # 5. SAR Generation
        proc_exists = result.get('proc_generate_sar_exists', False)
        sar_exists = result.get('sar_recommendations_exists', False)
        sar_rows = result.get('sar_rows', 0)
        sar_threshold = result.get('sar_threshold_enforced', False)
        sar_narrative = result.get('sar_narrative_populated', False)
        
        if proc_exists:
            score += 5
            feedback_parts.append("SAR procedure exists (5/5)")
            
        if sar_exists and sar_rows > 0 and sar_narrative:
            score += 8
            feedback_parts.append("SAR recommendations populated with narrative (8/8)")
        elif sar_exists and sar_rows > 0:
            score += 4
            feedback_parts.append("SAR recommendations populated but narrative missing/short (4/8)")
            
        if sar_threshold and sar_rows > 0:
            score += 5
            feedback_parts.append("SAR score threshold enforced (5/5)")

        # 6. CSV Export
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size_bytes', 0)
        
        if csv_exists and csv_size > 50:
            score += 7
            feedback_parts.append("CSV export successful (7/7)")
        elif csv_exists:
            score += 3
            feedback_parts.append("CSV exported but seems empty (3/7)")
            
        # 7. GUI Usage
        gui_evidence = result.get('gui_evidence', {})
        gui_used, gui_ratio, gui_details = _check_gui_usage(gui_evidence)
        if gui_used:
            score += 5
            feedback_parts.append(f"GUI usage verified [{gui_details}] (5/5)")
        else:
            feedback_parts.append(f"Insufficient GUI usage evidence [{gui_details}] (0/5)")

        # Final pass evaluation
        key_criteria = struct_exists and match_recognize_used
        passed = score >= 60 and key_criteria

        if not passed and score >= 60:
            feedback_parts.append("FAILED: Key criteria not met (MATCH_RECOGNIZE or structuring alerts missing).")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {str(e)}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {str(e)}"
        }