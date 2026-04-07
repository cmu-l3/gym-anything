#!/usr/bin/env python3
"""Verifier for USPTO Patent Citation Network Analysis task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_uspto_patent_citation_network(traj, env_info, task_info):
    """
    Verify USPTO Patent Citation Network Analysis task.

    Scoring (100 pts total):
    1. FORWARD_CITATION_TREE_VW (20 pts)
       - Exists (10 pts)
       - Uses recursive logic (CONNECT BY or WITH) (10 pts)
    2. SELF_CITATION_METRICS_VW (20 pts)
       - Exists (10 pts)
       - Identifies valid self-citation percentage > 0 for IBM (10 pts)
    3. TECH_CYCLE_TIME_VW (20 pts)
       - Exists (10 pts)
       - Uses PERCENTILE_CONT analytic function (10 pts)
    4. TOP_INFLUENTIAL_PATENTS_MV (15 pts)
       - Exists as MV (10 pts)
       - Contains data (5 pts)
    5. CSV Export (15 pts)
       - File exists, size > 0, created during task (15 pts)
    6. GUI Evidence (10 pts)
       - Evidence of using SQL Developer GUI (10 pts)

    Pass threshold: 70 pts (Must successfully implement the Recursive Citation Tree 
    and at least one statistical view).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/uspto_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # 1. FORWARD_CITATION_TREE_VW (20 pts)
        tree_exists = result.get('tree_vw_exists', False)
        tree_recursive = result.get('tree_vw_recursive', False)
        
        if tree_exists:
            score += 10
            feedback_parts.append("FORWARD_CITATION_TREE_VW exists (10/10)")
            if tree_recursive:
                score += 10
                feedback_parts.append("Recursive logic used in tree view (10/10)")
            else:
                feedback_parts.append("Recursive logic (CONNECT BY/WITH) missing in tree view (0/10)")
        else:
            feedback_parts.append("FORWARD_CITATION_TREE_VW not found (0/20)")

        # 2. SELF_CITATION_METRICS_VW (20 pts)
        self_cite_exists = result.get('self_cite_vw_exists', False)
        ibm_pct = result.get('self_cite_ibm_pct', 0)
        
        if self_cite_exists:
            score += 10
            feedback_parts.append("SELF_CITATION_METRICS_VW exists (10/10)")
            if ibm_pct > 0:
                score += 10
                feedback_parts.append(f"Self-citation logic functional (IBM={ibm_pct}%) (10/10)")
            else:
                feedback_parts.append("Self-citation logic failed to detect anomalies (0/10)")
        else:
            feedback_parts.append("SELF_CITATION_METRICS_VW not found (0/20)")

        # 3. TECH_CYCLE_TIME_VW (20 pts)
        cycle_exists = result.get('cycle_time_vw_exists', False)
        cycle_pct_cont = result.get('cycle_time_pct_cont', False)
        
        if cycle_exists:
            score += 10
            feedback_parts.append("TECH_CYCLE_TIME_VW exists (10/10)")
            if cycle_pct_cont:
                score += 10
                feedback_parts.append("PERCENTILE_CONT utilized correctly (10/10)")
            else:
                feedback_parts.append("PERCENTILE_CONT missing from median calculation (0/10)")
        else:
            feedback_parts.append("TECH_CYCLE_TIME_VW not found (0/20)")

        # 4. TOP_INFLUENTIAL_PATENTS_MV (15 pts)
        mv_exists = result.get('influential_mv_exists', False)
        mv_rows = result.get('influential_rows', 0)
        
        if mv_exists:
            score += 10
            feedback_parts.append("TOP_INFLUENTIAL_PATENTS_MV created as Materialized View (10/10)")
            if mv_rows > 0:
                score += 5
                feedback_parts.append(f"MV populated with {mv_rows} rows (5/5)")
            else:
                feedback_parts.append("MV is empty (0/5)")
        else:
            feedback_parts.append("TOP_INFLUENTIAL_PATENTS_MV not found or not an MV (0/15)")

        # 5. CSV Export (15 pts)
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size_bytes', 0)
        csv_during = result.get('csv_created_during', False)
        
        if csv_exists and csv_size > 50 and csv_during:
            score += 15
            feedback_parts.append("CSV export successful and valid (15/15)")
        elif csv_exists:
            score += 5
            feedback_parts.append("CSV export found but validation failed (size/time) (5/15)")
        else:
            feedback_parts.append("CSV export not found (0/15)")

        # 6. GUI Evidence (10 pts)
        gui_evidence = result.get('gui_evidence', {})
        signals = sum([
            1 for k in ['mru_connection_count', 'sqldev_oracle_sessions', 'sql_history_count'] 
            if gui_evidence.get(k, 0) > 0
        ])
        
        if signals >= 2:
            score += 10
            feedback_parts.append("SQL Developer GUI usage verified (10/10)")
        elif signals == 1:
            score += 5
            feedback_parts.append("Partial GUI usage evidence (5/10)")
        else:
            feedback_parts.append("No evidence of GUI usage (0/10)")

        # Evaluate VLM on trajectory if possible (optional verification layer)
        vlm_check = True
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            try:
                from gym_anything.vlm import get_final_screenshot
                final_img = get_final_screenshot(traj)
                if final_img:
                    vlm_res = query_vlm(
                        prompt="Look at this desktop screenshot. Is Oracle SQL Developer open? Answer exactly 'yes' or 'no'.",
                        image=final_img
                    )
                    if vlm_res and vlm_res.get('success'):
                        ans = vlm_res.get('parsed', '').lower().strip()
                        if 'yes' not in ans:
                            feedback_parts.append("VLM warning: SQL Developer not clearly visible in final screenshot.")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")

        # Check critical pass conditions
        passed = score >= 70 and tree_exists and (self_cite_exists or cycle_exists)

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