#!/usr/bin/env python3
"""Verifier for Grocery Market Basket Analysis task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_gui_usage(gui_evidence):
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


def verify_grocery_market_basket_analysis(traj, env_info, task_info):
    """
    Verify Grocery Market Basket Analysis task.
    
    Scoring (100 pts total):
    1. Views Created (20 pts)
       - PRODUCT_METRICS_VW (10 pts)
       - PAIR_METRICS_VW (10 pts)
    2. MV Created & Filtered (20 pts)
       - MARKET_BASKET_RULES_MV exists (10 pts)
       - Filters applied correctly (10 pts)
    3. Math Accuracy (40 pts)
       - Verified against deterministic seed data (Hot Dogs / PBJ)
       - Support accuracy implied by Lift/Conf passing
       - Conf A->B, Conf B->A, Lift accurate to 2 decimal places
    4. CSV Export (20 pts)
       - File exists and created during task (10 pts)
       - Line count approx 201 (10 pts)
       
    Pass threshold: 75 pts with Math Accuracy completely correct.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/grocery_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Read export payload
        product_vw_exists = result.get('product_vw_exists', False)
        pair_vw_exists = result.get('pair_vw_exists', False)
        mv_exists = result.get('mv_exists', False)
        filter_fails = result.get('filter_fails', 999)
        hd_stats = result.get('hd_stats', "").strip()
        pbj_stats = result.get('pbj_stats', "").strip()
        csv_exists = result.get('csv_exists', False)
        csv_lines = result.get('csv_lines', 0)
        file_created_during_task = result.get('file_created_during_task', False)
        gui_evidence = result.get('gui_evidence', {})

        # GUI usage check
        gui_used, _, gui_details = _check_gui_usage(gui_evidence)
        if not gui_used:
            feedback_parts.append(f"Warning: Insufficient GUI usage detected ({gui_details})")

        # 1. Views Created (20 pts)
        if product_vw_exists:
            score += 10
            feedback_parts.append("PRODUCT_METRICS_VW exists")
        else:
            feedback_parts.append("PRODUCT_METRICS_VW missing")
            
        if pair_vw_exists:
            score += 10
            feedback_parts.append("PAIR_METRICS_VW exists")
        else:
            feedback_parts.append("PAIR_METRICS_VW missing")

        # 2. MV Created & Filtered (20 pts)
        if mv_exists:
            score += 10
            feedback_parts.append("MARKET_BASKET_RULES_MV exists")
            
            if filter_fails == 0:
                score += 10
                feedback_parts.append("MV filters (count>=20, lift>2.0) applied correctly")
            else:
                feedback_parts.append(f"MV has {filter_fails} rows violating filters")
        else:
            feedback_parts.append("MARKET_BASKET_RULES_MV missing")

        # 3. Math Accuracy (40 pts)
        math_correct = False
        
        # Parse HD stats: pair_order_count, conf_a_b, conf_b_a, lift
        # Expected HD: 400, 0.8000, 0.6667, 13.3333
        if hd_stats:
            try:
                parts = [float(x) for x in hd_stats.split(',')]
                if len(parts) == 4:
                    pair_count, conf_ab, conf_ba, lift = parts
                    # Check within small tolerance
                    if pair_count == 400 and abs(conf_ab - 0.8) < 0.05 and abs(conf_ba - 0.6667) < 0.05 and abs(lift - 13.3333) < 0.5:
                        score += 20
                        math_correct = True
                        feedback_parts.append("Hot Dogs pair math perfectly verified")
                    else:
                        feedback_parts.append(f"Hot Dogs pair math incorrect: got {hd_stats}")
            except Exception as e:
                feedback_parts.append(f"Error parsing HD stats: {e}")
        else:
            feedback_parts.append("Hot Dogs pair missing from rules MV")

        # Parse PBJ stats: 100, 0.6667, 0.6667, 44.4444
        if pbj_stats:
            try:
                parts = [float(x) for x in pbj_stats.split(',')]
                if len(parts) == 4:
                    pair_count, conf_ab, conf_ba, lift = parts
                    if pair_count == 100 and abs(conf_ab - 0.6667) < 0.05 and abs(conf_ba - 0.6667) < 0.05 and abs(lift - 44.4444) < 0.5:
                        score += 20
                        feedback_parts.append("PB&J pair math perfectly verified")
                    else:
                        feedback_parts.append(f"PB&J pair math incorrect: got {pbj_stats}")
            except Exception:
                pass

        # 4. CSV Export (20 pts)
        if csv_exists and file_created_during_task:
            score += 10
            feedback_parts.append("CSV exported during task")
            
            # Expecting 200 rows + 1 header = 201 lines.
            # Allow slight variance (e.g. blank trailing lines)
            if 195 <= csv_lines <= 210:
                score += 10
                feedback_parts.append(f"CSV line count accurate ({csv_lines} lines)")
            else:
                score += 5
                feedback_parts.append(f"CSV line count incorrect ({csv_lines} lines, expected ~201)")
        elif csv_exists:
            feedback_parts.append("CSV exists but was not created/modified during task (possible gaming)")
        else:
            feedback_parts.append("CSV export missing")

        # Determine pass status
        passed = (score >= 75) and math_correct

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {str(e)}"}