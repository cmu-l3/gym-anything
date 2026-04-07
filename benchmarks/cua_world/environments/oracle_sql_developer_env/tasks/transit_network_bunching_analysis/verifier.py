#!/usr/bin/env python3
"""Verifier for Transit Network Bunching Analysis task."""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_transit_bunching(traj, env_info, task_info):
    """
    Verify the transit network bunching analysis task.
    
    Scoring Breakdown (100 pts total):
    1. GTFS Parser Function (25 pts): Successfully compiles and correctly parses >24hr format.
    2. Segment Run Times View (20 pts): Exists (10) + Uses LEAD (10).
    3. Bunching Risk View (25 pts): Exists (10) + Uses LAG (10) + Returns expected rows (5).
    4. Route Performance Materialized View (15 pts): Exists and aggregates.
    5. CSV Export (10 pts): Exists, has data, modified during session.
    6. GUI / VLM Evidence (5 pts): Demonstrates UI usage.

    Pass condition: Score >= 70 and parser function must be correct.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/transit_task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # 1. Function
        func_correct = result.get('func_correct', False)
        if func_correct:
            score += 25
            feedback_parts.append("PARSE_GTFS_TIME correctly parses >24hr intervals (25/25)")
        else:
            val = result.get('func_day_val', 'ERROR')
            feedback_parts.append(f"PARSE_GTFS_TIME failed or parsed incorrectly (returned day: {val}) (0/25)")

        # 2. Segment View
        if result.get('segment_vw_exists'):
            score += 10
            if result.get('has_lead'):
                score += 10
                feedback_parts.append("SEGMENT_RUN_TIMES_VW exists and uses LEAD (20/20)")
            else:
                feedback_parts.append("SEGMENT_RUN_TIMES_VW exists but missing LEAD window function (10/20)")
        else:
            feedback_parts.append("SEGMENT_RUN_TIMES_VW does not exist (0/20)")

        # 3. Bunching Risk View
        if result.get('bunching_vw_exists'):
            score += 10
            if result.get('has_lag'):
                score += 10
                feedback_parts.append("BUNCHING_RISK_VW exists and uses LAG (+20)")
            else:
                feedback_parts.append("BUNCHING_RISK_VW exists but missing LAG window function (+10)")
                
            if result.get('bunching_rows', 0) > 0:
                score += 5
                feedback_parts.append(f"BUNCHING_RISK_VW correctly flags bunching incidents (+5)")
            else:
                feedback_parts.append("BUNCHING_RISK_VW returns 0 rows (missing logic check) (+0)")
        else:
            feedback_parts.append("BUNCHING_RISK_VW does not exist (0/25)")

        # 4. Materialized View
        if result.get('route_mv_exists'):
            score += 15
            feedback_parts.append("ROUTE_PERFORMANCE_MV exists (15/15)")
        else:
            feedback_parts.append("ROUTE_PERFORMANCE_MV does not exist (0/15)")

        # 5. CSV Export
        if result.get('csv_exists') and result.get('csv_modified_during_task'):
            if result.get('csv_size_bytes', 0) > 10:
                score += 10
                feedback_parts.append("CSV exported successfully with data (10/10)")
            else:
                score += 5
                feedback_parts.append("CSV exported but appears empty (5/10)")
        else:
            feedback_parts.append("CSV not exported or not modified during task (0/10)")

        # 6. GUI Evidence Check
        gui = result.get('gui_evidence', {})
        signals = sum(1 for k in ['sql_history_count', 'mru_connection_count', 'sqldev_oracle_sessions'] if gui.get(k, 0) > 0)
        
        if signals >= 2:
            score += 5
            feedback_parts.append("GUI usage confirmed via application artifacts (5/5)")
        else:
            # Fallback to VLM if file artifacts aren't fully flushed
            query_vlm = env_info.get('query_vlm')
            if query_vlm:
                frames = sample_trajectory_frames(traj, n=3)
                final = get_final_screenshot(traj)
                vlm_prompt = "Look at these frames from an agent session. Is the agent actively using Oracle SQL Developer's GUI (writing SQL, running scripts, opening connections)?"
                vlm_resp = query_vlm(images=frames + [final] if final else frames, prompt=vlm_prompt)
                if vlm_resp and vlm_resp.get("success"):
                    ans = str(vlm_resp.get("parsed", vlm_resp.get("response", ""))).lower()
                    if "yes" in ans or "true" in ans:
                        score += 5
                        feedback_parts.append("GUI usage confirmed via VLM trajectory (5/5)")
                    else:
                        feedback_parts.append("No GUI usage confirmed via VLM (0/5)")
            else:
                feedback_parts.append("Insufficient GUI artifact signals and VLM unavailable (0/5)")

        # Final Evaluation
        passed = (score >= 70) and func_correct
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification exception: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {e}"
        }