#!/usr/bin/env python3
"""Verifier for Transit Fleet Interval Packing task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transit_fleet_interval_packing(traj, env_info, task_info):
    """
    Verify interval packing task completion.

    Scoring (100 pts total):
    1. Contiguous Blocks Created (35 pts):
       - DOWNTIME_BLOCKS_VW exists AND row count successfully reduced compared to raw logs.
    2. Zero Overlaps Remaining (25 pts):
       - Self-join query returns 0 overlapping records in the view.
    3. Availability Calculation (15 pts):
       - FLEET_AVAILABILITY_VW exists.
    4. Alert Infrastructure (15 pts):
       - MAINTENANCE_ALERTS table exists (5)
       - PROC_FLAG_STUCK_LOCOMOTIVES procedure exists (5)
       - Table is populated with > 0 records (5)
    5. Report Export (5 pts):
       - CSV file exists, > 0 bytes, created during task.
    6. GUI Usage (5 pts):
       - SQL Developer history / connections show activity.

    Pass threshold: 75 pts AND zero overlaps remaining AND downtime blocks view exists.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/transit_fleet_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []

        # Read fields
        downtime_blocks_exists = result.get('downtime_blocks_exists', False)
        raw_log_count = result.get('raw_log_count', 0)
        packed_block_count = result.get('packed_block_count', 0)
        overlap_count = result.get('overlap_count', -1)
        availability_vw_exists = result.get('availability_vw_exists', False)
        alert_tbl_exists = result.get('alert_tbl_exists', False)
        alert_proc_exists = result.get('alert_proc_exists', False)
        alert_count = result.get('alert_count', 0)
        csv_exists = result.get('csv_exists', False)
        csv_modified = result.get('csv_modified', False)
        csv_size = result.get('csv_size', 0)
        gui_ev = result.get('gui_evidence', {})

        # 1. Contiguous Blocks Created (35 pts)
        if downtime_blocks_exists:
            if packed_block_count > 0 and packed_block_count < raw_log_count:
                score += 35
                feedback_parts.append(f"Downtime blocks packed successfully (raw: {raw_log_count}, packed: {packed_block_count}) (35/35)")
            else:
                score += 15
                feedback_parts.append(f"DOWNTIME_BLOCKS_VW created but no reduction in row count indicating poor interval packing (raw: {raw_log_count}, packed: {packed_block_count}) (15/35)")
        else:
            feedback_parts.append("DOWNTIME_BLOCKS_VW not found (0/35)")

        # 2. Zero Overlaps Remaining (25 pts)
        if downtime_blocks_exists and overlap_count == 0:
            score += 25
            feedback_parts.append("Zero overlaps detected in packed blocks (25/25)")
        elif downtime_blocks_exists and overlap_count > 0:
            feedback_parts.append(f"Overlaps still present in packed blocks: {overlap_count} overlapping pairs detected (0/25)")
        else:
            feedback_parts.append("Overlaps could not be checked (0/25)")

        # 3. Availability Calculation (15 pts)
        if availability_vw_exists:
            score += 15
            feedback_parts.append("FLEET_AVAILABILITY_VW exists (15/15)")
        else:
            feedback_parts.append("FLEET_AVAILABILITY_VW not found (0/15)")

        # 4. Alert Infrastructure (15 pts)
        alert_pts = 0
        if alert_tbl_exists:
            alert_pts += 5
        if alert_proc_exists:
            alert_pts += 5
        if alert_count > 0:
            alert_pts += 5
        
        score += alert_pts
        if alert_pts == 15:
            feedback_parts.append("Alert infrastructure fully implemented and populated (15/15)")
        else:
            feedback_parts.append(f"Alert infrastructure partially implemented ({alert_pts}/15)")

        # 5. Report Export (5 pts)
        if csv_exists and csv_modified and csv_size > 50:
            score += 5
            feedback_parts.append("CSV exported successfully (5/5)")
        else:
            feedback_parts.append("CSV export missing or invalid (0/5)")

        # 6. GUI Usage (5 pts)
        gui_signals = sum([
            1 if gui_ev.get('mru_connection_count', 0) > 0 else 0,
            1 if gui_ev.get('sqldev_oracle_sessions', 0) > 0 else 0,
            1 if gui_ev.get('sql_history_count', 0) > 0 else 0
        ])
        if gui_signals >= 2:
            score += 5
            feedback_parts.append("GUI usage verified (5/5)")
        else:
            feedback_parts.append("Insufficient GUI usage evidence (0/5)")

        # Pass logic
        passed = (score >= 75 and overlap_count == 0 and downtime_blocks_exists)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}