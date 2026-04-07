#!/usr/bin/env python3
"""Verifier for Biodiversity Hotspot Analysis task."""

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

def verify_biodiversity_hotspot_analysis(traj, env_info, task_info):
    """
    Verify biodiversity hotspot analysis task.

    Scoring System (100 total):
    - Haversine function exists & accurate: 12 pts (SF->LA dist within +/- 20 of 559 km)
    - Shannon function exists & valid: 10 pts (H' > 0)
    - Simpson function exists & valid: 8 pts (0 < D < 1)
    - Taxonomic view with CONNECT BY: 15 pts
    - Proximity view exists: 12 pts
    - Seasonal view with window functions: 10 pts
    - GAP view exists: 15 pts
    - Export procedure exists: 5 pts
    - CSV exists & valid size: 8 pts
    - GUI Usage: 5 pts

    Pass threshold: 60 pts AND Haversine function works AND at least 1 analytical view works.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/biodiversity_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Haversine Function (12 pts)
        haversine_exists = result.get('haversine_exists', False)
        hav_km = result.get('haversine_sf_la_km', 0)
        haversine_accurate = False
        if haversine_exists:
            if 530 <= hav_km <= 590:
                score += 12
                haversine_accurate = True
                feedback_parts.append(f"Haversine accurate (SF-LA: {hav_km}km) (12/12)")
            else:
                score += 4
                feedback_parts.append(f"Haversine exists but inaccurate ({hav_km}km) (4/12)")
        else:
            feedback_parts.append("Haversine function missing (0/12)")
        subscores['haversine'] = haversine_accurate

        # 2. Shannon Index (10 pts)
        shannon_exists = result.get('shannon_exists', False)
        shan_val = float(result.get('shannon_site1', -1))
        if shannon_exists and shan_val > 0:
            score += 10
            feedback_parts.append(f"Shannon function valid (H': {shan_val}) (10/10)")
        elif shannon_exists:
            score += 4
            feedback_parts.append(f"Shannon exists but invalid output ({shan_val}) (4/10)")
        else:
            feedback_parts.append("Shannon function missing (0/10)")

        # 3. Simpson Index (8 pts)
        simpson_exists = result.get('simpson_exists', False)
        simp_val = float(result.get('simpson_site1', -1))
        if simpson_exists and 0 < simp_val < 1:
            score += 8
            feedback_parts.append(f"Simpson function valid (D: {simp_val}) (8/8)")
        elif simpson_exists:
            score += 3
            feedback_parts.append(f"Simpson exists but invalid output ({simp_val}) (3/8)")
        else:
            feedback_parts.append("Simpson function missing (0/8)")

        # 4. Taxonomic Tree View (15 pts)
        tax_vw = result.get('taxonomic_vw_exists', False)
        conn_by = result.get('connect_by_used', False)
        if tax_vw and conn_by:
            score += 15
            feedback_parts.append("Taxonomic view w/ CONNECT BY exists (15/15)")
        elif tax_vw:
            score += 7
            feedback_parts.append("Taxonomic view exists but missing CONNECT BY (7/15)")
        else:
            feedback_parts.append("Taxonomic view missing (0/15)")

        # 5. Proximity View (12 pts)
        prox_vw = result.get('proximity_vw_exists', False)
        if prox_vw:
            score += 12
            feedback_parts.append("Proximity view exists (12/12)")
        else:
            feedback_parts.append("Proximity view missing (0/12)")

        # 6. Seasonal View (10 pts)
        seas_vw = result.get('seasonal_vw_exists', False)
        win_func = result.get('window_func_used', False)
        if seas_vw and win_func:
            score += 10
            feedback_parts.append("Seasonal view w/ Window functions exists (10/10)")
        elif seas_vw:
            score += 5
            feedback_parts.append("Seasonal view exists but missing window functions (5/10)")
        else:
            feedback_parts.append("Seasonal view missing (0/10)")

        # 7. GAP View (15 pts)
        gap_vw = result.get('gap_vw_exists', False)
        if gap_vw:
            score += 15
            feedback_parts.append("GAP analysis view exists (15/15)")
        else:
            feedback_parts.append("GAP analysis view missing (0/15)")

        # 8. Export Procedure (5 pts)
        proc_exists = result.get('proc_exists', False)
        if proc_exists:
            score += 5
            feedback_parts.append("Export procedure exists (5/5)")
        else:
            feedback_parts.append("Export procedure missing (0/5)")

        # 9. CSV Export (8 pts)
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        if csv_exists and csv_size > 10:
            score += 8
            feedback_parts.append(f"CSV export valid ({csv_size} bytes) (8/8)")
        elif csv_exists:
            score += 4
            feedback_parts.append("CSV exists but is empty/small (4/8)")
        else:
            feedback_parts.append("CSV export missing (0/8)")

        # 10. GUI Usage (5 pts)
        gui_used, gui_frac, gui_det = _check_gui_usage(result.get('gui_evidence', {}))
        if gui_used:
            score += 5
            feedback_parts.append("GUI usage verified (5/5)")
        else:
            feedback_parts.append(f"Insufficient GUI usage: {gui_det} (0/5)")

        # Pass condition evaluation
        has_analytical_view = tax_vw or prox_vw or seas_vw or gap_vw
        passed = (score >= 60) and haversine_accurate and has_analytical_view

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {str(e)}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed due to error: {str(e)}"
        }