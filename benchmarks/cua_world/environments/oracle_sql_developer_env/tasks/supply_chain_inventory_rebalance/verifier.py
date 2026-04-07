#!/usr/bin/env python3
"""Verifier for Supply Chain Inventory Rebalance task."""

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


def verify_supply_chain_inventory_rebalance(traj, env_info, task_info):
    """
    Verify supply chain inventory rebalance task completion.

    Scoring (100 pts total):
    1. Demand Analysis (15 pts):
       - demand_analysis_exists -> 5 pts
       - demand_analysis_rows > 0 -> 5 pts
       - window_functions_used -> 5 pts
    2. Reorder Parameter Fixes (30 pts):
       - zero_reorder_fixed (remaining=0) -> 10 pts (partial if remaining < 12)
       - excessive_safety_fixed (remaining=0) -> 10 pts (partial if remaining < 8)
       - zero_leadtime_fixed (remaining=0) -> 10 pts (partial if remaining < 5)
    3. Inventory Forecast View (20 pts):
       - inventory_forecast_exists -> 10 pts
       - model_clause_used -> 10 pts
    4. Rebalance Recommendations (10 pts):
       - rebalance_vw_exists -> 5 pts
       - json_used -> 5 pts
    5. Scheduled Monitoring (15 pts):
       - stockout_proc_exists -> 5 pts
       - alerts_table_exists -> 5 pts
       - scheduler_job_exists -> 5 pts
    6. GUI Usage (10 pts):
       - 2+ signals -> full points

    Pass threshold: 70 pts AND at least 2 of 3 error types fixed AND inventory_forecast_exists.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/supply_chain_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Extract result fields
        demand_analysis_exists = result.get('demand_analysis_exists', False)
        demand_analysis_rows = result.get('demand_analysis_rows', 0)
        window_functions_used = result.get('window_functions_used', False)
        zero_reorder_fixed = result.get('zero_reorder_fixed', False)
        remaining_zero_reorder = result.get('remaining_zero_reorder', 12)
        excessive_safety_fixed = result.get('excessive_safety_fixed', False)
        remaining_excessive_safety = result.get('remaining_excessive_safety', 8)
        zero_leadtime_fixed = result.get('zero_leadtime_fixed', False)
        remaining_zero_leadtime = result.get('remaining_zero_leadtime', 5)
        inventory_forecast_exists = result.get('inventory_forecast_exists', False)
        model_clause_used = result.get('model_clause_used', False)
        rebalance_vw_exists = result.get('rebalance_vw_exists', False)
        json_used = result.get('json_used', False)
        scheduler_job_exists = result.get('scheduler_job_exists', False)
        stockout_proc_exists = result.get('stockout_proc_exists', False)
        alerts_table_exists = result.get('alerts_table_exists', False)
        alert_count = result.get('alert_count', 0)
        eoq_used = result.get('eoq_used', False)
        gui_evidence = result.get('gui_evidence', {})

        # ---- Criterion 1: Demand Analysis (15 pts) ----
        demand_pts = 0
        if demand_analysis_exists:
            demand_pts += 5
            feedback_parts.append("Demand analysis view/table exists (5/5)")
        else:
            feedback_parts.append("Demand analysis view/table not found (0/5)")

        if demand_analysis_rows > 0:
            demand_pts += 5
            feedback_parts.append(f"Demand analysis has {demand_analysis_rows} rows (5/5)")
        else:
            feedback_parts.append("Demand analysis has no data rows (0/5)")

        if window_functions_used:
            demand_pts += 5
            feedback_parts.append("Window functions used in demand analysis (5/5)")
        else:
            feedback_parts.append("Window functions not detected in demand analysis (0/5)")

        score += demand_pts
        subscores['demand_analysis'] = demand_analysis_exists and demand_analysis_rows > 0

        # ---- Criterion 2: Reorder Parameter Fixes (30 pts) ----

        # 2a. Zero reorder point fixed (10 pts)
        if zero_reorder_fixed and remaining_zero_reorder == 0:
            score += 10
            feedback_parts.append("Zero reorder points fully fixed (10/10)")
            subscores['zero_reorder'] = True
        elif remaining_zero_reorder < 12:
            partial = int(10 * (12 - remaining_zero_reorder) / 12)
            score += partial
            feedback_parts.append(f"Zero reorder points partially fixed: {remaining_zero_reorder} remaining ({partial}/10)")
            subscores['zero_reorder'] = remaining_zero_reorder == 0
        else:
            feedback_parts.append(f"Zero reorder points not fixed: {remaining_zero_reorder} remaining (0/10)")
            subscores['zero_reorder'] = False

        # 2b. Excessive safety stock fixed (10 pts)
        if excessive_safety_fixed and remaining_excessive_safety == 0:
            score += 10
            feedback_parts.append("Excessive safety stock fully fixed (10/10)")
            subscores['excessive_safety'] = True
        elif remaining_excessive_safety < 8:
            partial = int(10 * (8 - remaining_excessive_safety) / 8)
            score += partial
            feedback_parts.append(f"Excessive safety stock partially fixed: {remaining_excessive_safety} remaining ({partial}/10)")
            subscores['excessive_safety'] = remaining_excessive_safety == 0
        else:
            feedback_parts.append(f"Excessive safety stock not fixed: {remaining_excessive_safety} remaining (0/10)")
            subscores['excessive_safety'] = False

        # 2c. Zero lead time fixed (10 pts)
        if zero_leadtime_fixed and remaining_zero_leadtime == 0:
            score += 10
            feedback_parts.append("Zero lead times fully fixed (10/10)")
            subscores['zero_leadtime'] = True
        elif remaining_zero_leadtime < 5:
            partial = int(10 * (5 - remaining_zero_leadtime) / 5)
            score += partial
            feedback_parts.append(f"Zero lead times partially fixed: {remaining_zero_leadtime} remaining ({partial}/10)")
            subscores['zero_leadtime'] = remaining_zero_leadtime == 0
        else:
            feedback_parts.append(f"Zero lead times not fixed: {remaining_zero_leadtime} remaining (0/10)")
            subscores['zero_leadtime'] = False

        # ---- Criterion 3: Inventory Forecast View (20 pts) ----
        forecast_pts = 0
        if inventory_forecast_exists:
            forecast_pts += 10
            feedback_parts.append("Inventory forecast view exists (10/10)")
        else:
            feedback_parts.append("Inventory forecast view not found (0/10)")

        if model_clause_used:
            forecast_pts += 10
            feedback_parts.append("MODEL clause used in forecast (10/10)")
        else:
            feedback_parts.append("MODEL clause not detected in forecast (0/10)")

        score += forecast_pts
        subscores['inventory_forecast'] = inventory_forecast_exists

        # ---- Criterion 4: Rebalance Recommendations (10 pts) ----
        rebalance_pts = 0
        if rebalance_vw_exists:
            rebalance_pts += 5
            feedback_parts.append("Rebalance recommendations view exists (5/5)")
        else:
            feedback_parts.append("Rebalance recommendations view not found (0/5)")

        if json_used:
            rebalance_pts += 5
            feedback_parts.append("JSON functions used in rebalance output (5/5)")
        else:
            feedback_parts.append("JSON functions not detected in rebalance output (0/5)")

        score += rebalance_pts
        subscores['rebalance_view'] = rebalance_vw_exists

        # ---- Criterion 5: Scheduled Monitoring (15 pts) ----
        monitor_pts = 0
        if stockout_proc_exists:
            monitor_pts += 5
            feedback_parts.append("Stockout detection procedure exists (5/5)")
        else:
            feedback_parts.append("Stockout detection procedure not found (0/5)")

        if alerts_table_exists and alert_count > 0:
            monitor_pts += 5
            feedback_parts.append(f"Alerts table exists with {alert_count} alert(s) (5/5)")
        else:
            feedback_parts.append(f"Alerts table not found or empty (0/5)")

        if scheduler_job_exists:
            monitor_pts += 5
            feedback_parts.append("Scheduler job exists for monitoring (5/5)")
        else:
            feedback_parts.append("Scheduler job not found (0/5)")

        score += monitor_pts
        subscores['scheduled_monitoring'] = stockout_proc_exists and alerts_table_exists

        # ---- Criterion 6: GUI Usage (10 pts) ----
        gui_used, gui_frac, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(gui_frac * 10)
        score += gui_pts
        subscores['gui'] = gui_used
        if gui_used:
            feedback_parts.append(f"GUI confirmed ({gui_details}) ({gui_pts}/10)")
        elif gui_pts > 0:
            feedback_parts.append(f"Partial GUI evidence ({gui_details}) ({gui_pts}/10)")
        else:
            feedback_parts.append("No GUI usage evidence (0/10)")

        # ---- VLM bonus (optional) ----
        if query_vlm:
            try:
                temp_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_ss.name)
                    vlm_prompt = (
                        "Examine this Oracle SQL Developer screenshot. "
                        "Is there evidence of: inventory management queries, reorder point calculations, "
                        "supply chain analysis, MODEL clause forecasting, or scheduled job creation? "
                        "Reply VERIFIED if supply chain inventory work is visible, else NOT_VERIFIED."
                    )
                    vlm_result = query_vlm(image=temp_ss.name, prompt=vlm_prompt)
                    if vlm_result and 'VERIFIED' in str(vlm_result).upper() and 'NOT_VERIFIED' not in str(vlm_result).upper():
                        if score < 95:
                            score = min(score + 5, 100)
                            feedback_parts.append("VLM: supply chain inventory work visible (+5 bonus)")
                finally:
                    os.unlink(temp_ss.name)
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")

        # ---- Pass conditions ----
        # At least 2 of 3 error types must be fixed
        errors_fixed = sum([
            subscores.get('zero_reorder', False),
            subscores.get('excessive_safety', False),
            subscores.get('zero_leadtime', False),
        ])

        passed = (
            score >= 70 and
            errors_fixed >= 2 and
            inventory_forecast_exists
        )

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
