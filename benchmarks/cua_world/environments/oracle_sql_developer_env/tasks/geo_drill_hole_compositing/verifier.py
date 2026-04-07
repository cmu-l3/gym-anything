#!/usr/bin/env python3
"""Verifier for Geological Drill Hole Compositing task."""

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


def verify_geo_drill_hole_compositing(traj, env_info, task_info):
    """
    Verify geological drill hole compositing task.

    Scoring (100 pts total):
    1. Interval Overlaps Fixed (20 pts):
       - overlaps_remaining == 0 -> 20 pts
    2. Hole Summary View (15 pts):
       - summary_vw_exists -> 5 pts
       - math_correct (h001_au == 0.35) -> 10 pts
    3. Significant Intercepts View (30 pts):
       - intercepts_vw_exists -> 5 pts
       - match_recognize_used -> 10 pts
       - logic_correct (num_intercepts == 1 AND h002_length == 4.5) -> 15 pts
    4. 3D Locations View (15 pts):
       - locations_vw_exists -> 5 pts
       - z_math_correct (h002_z == 397.75) -> 10 pts
    5. Data Export (10 pts):
       - csv_exists AND csv_size > 50 -> 10 pts
    6. GUI Usage (10 pts):
       - 2+ signals -> full points

    Pass conditions: score >= 75 AND overlaps_remaining == 0 AND match_recognize_used
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/geo_task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        overlaps_remaining = result.get('overlaps_remaining', 99)
        summary_vw_exists = result.get('summary_vw_exists', False)
        summary_h001_au = result.get('summary_h001_au', "0")
        intercepts_vw_exists = result.get('intercepts_vw_exists', False)
        match_recognize_used = result.get('match_recognize_used', False)
        num_intercepts = result.get('num_intercepts', 0)
        intercepts_h002_length = result.get('intercepts_h002_length', "0")
        locations_vw_exists = result.get('locations_vw_exists', False)
        locations_h002_z = result.get('locations_h002_z', "0")
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        gui_evidence = result.get('gui_evidence', {})

        # 1. Interval Overlaps Fixed (20 pts)
        if overlaps_remaining == 0:
            score += 20
            feedback_parts.append("Overlaps successfully fixed (20/20)")
        else:
            feedback_parts.append(f"Overlaps remain ({overlaps_remaining}) in CORE_ASSAYS (0/20)")

        # 2. Hole Summary View (15 pts)
        if summary_vw_exists:
            score += 5
            try:
                # Math check: weighted avg au for H001 should be 0.35
                if abs(float(summary_h001_au) - 0.35) < 0.01:
                    score += 10
                    feedback_parts.append("Hole summary view exists & length-weighted math is correct (15/15)")
                else:
                    feedback_parts.append(f"Hole summary exists but math incorrect (expected ~0.35, got {summary_h001_au}) (5/15)")
            except ValueError:
                feedback_parts.append("Hole summary exists but math check failed (5/15)")
        else:
            feedback_parts.append("Hole summary view missing (0/15)")

        # 3. Significant Intercepts View (30 pts)
        if intercepts_vw_exists:
            score += 5
            
            if match_recognize_used:
                score += 10
                feedback_parts.append("MATCH_RECOGNIZE used (+10)")
            else:
                feedback_parts.append("MATCH_RECOGNIZE not used (+0)")
                
            try:
                # Logic check: Should detect exactly 1 intercept (H002), length 4.5
                if num_intercepts == 1 and abs(float(intercepts_h002_length) - 4.5) < 0.01:
                    score += 15
                    feedback_parts.append("Intercept logic correct [>=3m continuous, au>=0.5] (+15)")
                else:
                    feedback_parts.append(f"Intercept logic incorrect [count={num_intercepts}, len={intercepts_h002_length}] (+0)")
            except ValueError:
                feedback_parts.append("Intercept logic check failed (+0)")
        else:
            feedback_parts.append("Significant intercepts view missing (0/30)")

        # 4. 3D Locations View (15 pts)
        if locations_vw_exists:
            score += 5
            try:
                # Z-coord check: 410 - (10 + 4.5/2) = 397.75
                if abs(float(locations_h002_z) - 397.75) < 0.02:
                    score += 10
                    feedback_parts.append("3D locations view exists & Z-depth math correct (15/15)")
                else:
                    feedback_parts.append(f"3D locations exists but Z math incorrect (got {locations_h002_z}) (5/15)")
            except ValueError:
                feedback_parts.append("3D locations exists but Z math check failed (5/15)")
        else:
            feedback_parts.append("3D locations view missing (0/15)")

        # 5. Data Export (10 pts)
        if csv_exists and csv_size > 50:
            score += 10
            feedback_parts.append(f"CSV export found and populated [{csv_size} bytes] (10/10)")
        elif csv_exists:
            score += 5
            feedback_parts.append(f"CSV export found but small/empty [{csv_size} bytes] (5/10)")
        else:
            feedback_parts.append("CSV export missing (0/10)")

        # 6. GUI Usage (10 pts)
        gui_used, gui_score_ratio, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(10 * gui_score_ratio)
        score += gui_pts
        if gui_pts == 10:
            feedback_parts.append("GUI usage verified (10/10)")
        else:
            feedback_parts.append(f"Partial/no GUI usage [{gui_details}] ({gui_pts}/10)")

        # Final Evaluation
        passed = (score >= 75) and (overlaps_remaining == 0) and match_recognize_used
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}