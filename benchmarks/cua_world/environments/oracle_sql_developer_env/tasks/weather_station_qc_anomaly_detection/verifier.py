#!/usr/bin/env python3
"""Verifier for Weather Station QC Anomaly Detection task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prompt for supplementary VLM check on trajectory
TRAJECTORY_VLM_PROMPT = """You are verifying an agent's completion of a database analysis task in Oracle SQL Developer.
Look at the sequence of screenshots showing the agent's screen during the task.

Does the trajectory show the agent actively using Oracle SQL Developer?
Look for:
- Writing or running SQL queries in the SQL Worksheet
- Browsing table data or schemas in the left connections panel
- Creating tables, functions, or views
- Viewing query results grids

Return a JSON with:
{
    "sqldev_used_actively": true/false,
    "wrote_queries": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what the agent is seen doing"
}
"""

def verify_weather_station_qc(traj, env_info, task_info):
    """
    Verify weather station QC task completion.

    Scoring (100 pts total):
    1. QC_RESULTS table exists: 5 pts
    2. Stuck sensor detection (>= 10 flags): 15 pts
    3. Impossible value detection (>= 10 flags): 15 pts
    4. IDW interpolation function (exists + Haversine logic): 15 pts
    5. Climate anomaly view (exists + STDDEV): 15 pts
    6. Quality-controlled MV exists: 15 pts
    7. CSV export (> 500 bytes): 10 pts
    8. GUI Evidence (Programmatic + VLM): 10 pts

    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/weather_qc_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. QC_RESULTS Table
        if result.get('qc_results_exists'):
            score += 5
            feedback_parts.append("QC_RESULTS exists (5/5)")
            subscores['qc_table'] = True
        else:
            feedback_parts.append("QC_RESULTS missing (0/5)")
            subscores['qc_table'] = False

        # 2. Stuck sensor detection
        stuck_flags = result.get('stuck_sensor_flags', 0)
        if stuck_flags >= 10:
            score += 15
            feedback_parts.append(f"Stuck sensors flagged: {stuck_flags} (15/15)")
            subscores['stuck_sensor'] = True
        elif stuck_flags > 0:
            score += 5
            feedback_parts.append(f"Stuck sensors partially flagged: {stuck_flags} (5/15)")
            subscores['stuck_sensor'] = False
        else:
            feedback_parts.append("Stuck sensors not flagged (0/15)")
            subscores['stuck_sensor'] = False

        # 3. Impossible value detection
        impossible_flags = result.get('impossible_value_flags', 0)
        if impossible_flags >= 10:
            score += 15
            feedback_parts.append(f"Impossible values flagged: {impossible_flags} (15/15)")
            subscores['impossible_value'] = True
        elif impossible_flags > 0:
            score += 5
            feedback_parts.append(f"Impossible values partially flagged: {impossible_flags} (5/15)")
            subscores['impossible_value'] = False
        else:
            feedback_parts.append("Impossible values not flagged (0/15)")
            subscores['impossible_value'] = False

        # 4. IDW Function
        if result.get('idw_func_exists'):
            if result.get('haversine_used'):
                score += 15
                feedback_parts.append("IDW function created with Haversine math (15/15)")
            else:
                score += 8
                feedback_parts.append("IDW function created without clear Haversine math (8/15)")
            subscores['idw_func'] = True
        else:
            feedback_parts.append("IDW function missing (0/15)")
            subscores['idw_func'] = False

        # 5. Anomaly View
        if result.get('anomaly_vw_exists'):
            if result.get('stddev_used'):
                score += 15
                feedback_parts.append("Anomaly view created with STDDEV logic (15/15)")
            else:
                score += 8
                feedback_parts.append("Anomaly view created without STDDEV (8/15)")
            subscores['anomaly_view'] = True
        else:
            feedback_parts.append("Anomaly view missing (0/15)")
            subscores['anomaly_view'] = False

        # 6. Quality-Controlled MV
        if result.get('qc_mv_exists'):
            score += 15
            feedback_parts.append("QC Materialized View exists (15/15)")
            subscores['qc_mv'] = True
        else:
            feedback_parts.append("QC Materialized View missing (0/15)")
            subscores['qc_mv'] = False

        # 7. CSV Export
        csv_size = result.get('csv_size_bytes', 0)
        if result.get('csv_exists') and csv_size > 500:
            score += 10
            feedback_parts.append(f"CSV export found, size {csv_size} bytes (10/10)")
            subscores['csv_export'] = True
        elif result.get('csv_exists'):
            score += 4
            feedback_parts.append(f"CSV export found but small ({csv_size} bytes) (4/10)")
            subscores['csv_export'] = False
        else:
            feedback_parts.append("CSV export missing (0/10)")
            subscores['csv_export'] = False

        # 8. GUI Usage & VLM verification
        gui_evidence = result.get('gui_evidence', {})
        prog_gui_signals = 0
        if gui_evidence.get('mru_connection_count', 0) > 0: prog_gui_signals += 1
        if gui_evidence.get('sqldev_oracle_sessions', 0) > 0: prog_gui_signals += 1
        if gui_evidence.get('sql_history_count', 0) > 0: prog_gui_signals += 1
        
        gui_score = 0
        vlm_used = False
        
        # Base GUI score from programmatic checks
        if prog_gui_signals >= 2:
            gui_score = 10
            feedback_parts.append(f"Strong GUI evidence found programmatically (10/10)")
        elif prog_gui_signals == 1:
            gui_score = 5
            feedback_parts.append(f"Weak GUI evidence found programmatically (5/10)")
            
        # Fallback/Supplemental VLM Check on trajectory if programmatic isn't perfect
        if gui_score < 10 and env_info.get('query_vlm'):
            try:
                from gym_anything.vlm import sample_trajectory_frames
                frames = sample_trajectory_frames(traj, n=4)
                if frames:
                    vlm_result = env_info['query_vlm'](images=frames, prompt=TRAJECTORY_VLM_PROMPT)
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        if parsed.get('sqldev_used_actively') and parsed.get('wrote_queries'):
                            vlm_used = True
                            gui_score = 10
                            feedback_parts.append("VLM trajectory check confirmed SQL Developer usage (+GUI pts)")
            except Exception as e:
                logger.warning(f"VLM trajectory check failed: {e}")
                
        if gui_score == 0 and not vlm_used:
            feedback_parts.append("No GUI usage evidence (0/10)")
            
        score += gui_score
        subscores['gui_usage'] = gui_score > 0

        # Pass condition: 60+ points and at least ONE detection component working
        passed = score >= 60 and (subscores.get('stuck_sensor') or subscores.get('impossible_value'))
        
        if passed:
            feedback_parts.insert(0, "SUCCESS: Required QC checks and tables completed.")
        else:
            if score >= 60:
                feedback_parts.insert(0, "FAILED: Score sufficient but core detection logic (stuck sensors or impossible values) not implemented.")
            else:
                feedback_parts.insert(0, "FAILED: Insufficient score.")

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