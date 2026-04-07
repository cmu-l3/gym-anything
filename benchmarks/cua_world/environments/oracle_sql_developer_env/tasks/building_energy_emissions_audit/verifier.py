#!/usr/bin/env python3
"""Verifier for Municipal Building Energy Emissions Audit task."""

import json
import logging
import os
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used."""
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

def _safe_float(val):
    try:
        if val is None or val == "":
            return None
        return float(val)
    except ValueError:
        return None

def verify_building_energy_emissions_audit(traj, env_info, task_info):
    """
    Verify Building Energy Emissions Audit task completion.

    Scoring (100 pts total):
    1. View & PIVOT Usage (20 pts)
       - pivot_vw_exists -> 10 pts
       - pivot_used -> 10 pts
    2. Dynamic Math Verification (40 pts)
       - evaluates successfully without SQL error -> 10 pts
       - GHG calculation exact (1006.83 +/- 0.5) -> 10 pts
       - Limit calculation exact (846.00 +/- 0.5) -> 10 pts
       - Penalty logic exact (43102.44 +/- 1.0) & compliant string 'N' -> 10 pts
    3. Automating Notices (20 pts)
       - proc_exists -> 10 pts
       - notices_generated > 0 -> 10 pts
    4. CSV Export (10 pts)
       - csv_exists & size > 50 -> 10 pts
    5. GUI Usage (10 pts)
       - 2+ signals -> 10 pts

    Pass threshold: 70 pts AND Dynamic Math evaluation must be successful.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/building_emissions_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Extract properties
        pivot_vw_exists = result.get('pivot_vw_exists', False)
        pivot_used = result.get('pivot_used', False)
        emissions_vw_exists = result.get('emissions_vw_exists', False)
        proc_exists = result.get('proc_exists', False)
        notices_generated = result.get('notices_generated', 0)
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size_bytes', 0)
        
        mock_eval_success = result.get('mock_eval_success', False)
        mock_error = result.get('mock_eval_error', '')
        mock_results = result.get('mock_results', {})
        
        gui_evidence = result.get('gui_evidence', {})
        gui_used, _, gui_details = _check_gui_usage(gui_evidence)

        # -----------------------------------------------------------------
        # 1. View & PIVOT Usage (20 pts)
        # -----------------------------------------------------------------
        if pivot_vw_exists:
            score += 10
            feedback_parts.append("PIVOT view exists (10/10)")
            if pivot_used:
                score += 10
                feedback_parts.append("PIVOT syntax used (10/10)")
            else:
                feedback_parts.append("PIVOT syntax not detected in view (0/10)")
        else:
            feedback_parts.append("PIVOT view not found (0/20)")

        # -----------------------------------------------------------------
        # 2. Dynamic Math Verification (40 pts)
        # -----------------------------------------------------------------
        math_correct = False
        if mock_eval_success:
            score += 10
            feedback_parts.append("Math evaluation ran successfully against agent view (10/10)")
            
            # Expected values based on injected mock data
            expected_ghg = 1006.83
            expected_limit = 846.00
            expected_penalty = 43102.44
            
            agent_ghg = _safe_float(mock_results.get('ghg'))
            agent_limit = _safe_float(mock_results.get('limit'))
            agent_compliant = mock_results.get('compliant', '').strip().upper()
            agent_penalty = _safe_float(mock_results.get('penalty'))
            
            # Sub-check A: GHG calculation
            if agent_ghg is not None and math.isclose(agent_ghg, expected_ghg, abs_tol=0.5):
                score += 10
                feedback_parts.append(f"GHG calculated accurately: {agent_ghg} (10/10)")
            else:
                feedback_parts.append(f"GHG calculation failed: expected {expected_ghg}, got {agent_ghg} (0/10)")
                
            # Sub-check B: Limit calculation
            if agent_limit is not None and math.isclose(agent_limit, expected_limit, abs_tol=0.5):
                score += 10
                feedback_parts.append(f"Limit calculated accurately: {agent_limit} (10/10)")
            else:
                feedback_parts.append(f"Limit calculation failed: expected {expected_limit}, got {agent_limit} (0/10)")
                
            # Sub-check C: Compliance & Penalty
            if agent_compliant == 'N' and agent_penalty is not None and math.isclose(agent_penalty, expected_penalty, abs_tol=1.0):
                score += 10
                math_correct = True
                feedback_parts.append(f"Penalty & Compliance accurate: {agent_compliant}, {agent_penalty} (10/10)")
            else:
                feedback_parts.append(f"Penalty/Compliance failed: expected N/{expected_penalty}, got {agent_compliant}/{agent_penalty} (0/10)")
        else:
            feedback_parts.append(f"Math evaluation failed to run: {mock_error} (0/40)")

        # -----------------------------------------------------------------
        # 3. Automating Notices (20 pts)
        # -----------------------------------------------------------------
        if proc_exists:
            score += 10
            feedback_parts.append("Procedure PROC_GENERATE_NOTICES exists (10/10)")
            if notices_generated > 0:
                score += 10
                feedback_parts.append(f"Notices table populated with {notices_generated} records (10/10)")
            else:
                feedback_parts.append("Notices table is empty (0/10)")
        else:
            feedback_parts.append("Procedure PROC_GENERATE_NOTICES not found (0/20)")

        # -----------------------------------------------------------------
        # 4. CSV Export (10 pts)
        # -----------------------------------------------------------------
        if csv_exists and csv_size > 50:
            score += 10
            feedback_parts.append("CSV exported successfully (10/10)")
        else:
            feedback_parts.append("CSV not exported or empty (0/10)")

        # -----------------------------------------------------------------
        # 5. GUI Usage (10 pts)
        # -----------------------------------------------------------------
        if gui_used:
            score += 10
            feedback_parts.append(f"GUI usage confirmed [{gui_details}] (10/10)")
        else:
            feedback_parts.append("Insufficient GUI usage evidence (0/10)")

        passed = score >= 70 and mock_eval_success and math_correct

        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {str(e)}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {str(e)}"
        }