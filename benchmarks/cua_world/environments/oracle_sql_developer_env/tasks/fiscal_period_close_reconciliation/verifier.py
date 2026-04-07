#!/usr/bin/env python3
"""Verifier for Fiscal Period Close Reconciliation task."""

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


def verify_fiscal_period_close_reconciliation(traj, env_info, task_info):
    """
    Verify fiscal period close reconciliation task completion.

    Scoring (100 pts total):
    1. Error Corrections (50 pts):
       a. Unbalanced JE fixed (15 pts)
       b. Duplicate JE removed (10 pts)
       c. Intercompany elimination (15 pts)
       d. Capex reclassified (10 pts)
    2. Materialized View (20 pts):
       - trial_balance_mv_exists (or alt) -> 8 pts
       - trial_balance_balances -> 7 pts
       - rollup_used -> 5 pts
    3. Consolidated Report View (10 pts):
       - consolidated_vw_exists -> 10 pts
    4. CSV Export (10 pts):
       - csv_exists AND csv_size > 100 -> 5 pts
       - csv_has_categories -> 5 pts
    5. GUI Usage (10 pts):
       - 2+ signals -> full points

    Pass threshold: 70 pts AND at least 3 of 4 errors fixed.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/fiscal_close_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Extract result fields
        unbalanced_je_fixed = result.get('unbalanced_je_fixed', False)
        remaining_unbalanced_count = result.get('remaining_unbalanced_count', 4)
        duplicate_je_removed = result.get('duplicate_je_removed', False)
        remaining_duplicate_count = result.get('remaining_duplicate_count', 99)
        intercompany_eliminated = result.get('intercompany_eliminated', False)
        pending_ic_eliminations = result.get('pending_ic_eliminations', 99)
        capex_reclassified = result.get('capex_reclassified', False)
        ppe_has_entry = result.get('ppe_has_entry', 0)
        trial_balance_mv_exists = result.get('trial_balance_mv_exists', False)
        trial_balance_mv_alt_exists = result.get('trial_balance_mv_alt_exists', 0)
        trial_balance_balances = result.get('trial_balance_balances', False)
        rollup_used = result.get('rollup_used', False)
        consolidated_vw_exists = result.get('consolidated_vw_exists', False)
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        csv_has_categories = result.get('csv_has_categories', False)
        gui_evidence = result.get('gui_evidence', {})

        # ---- Criterion 1: Error Corrections (50 pts total) ----

        # 1a. Unbalanced JE fixed (15 pts)
        if unbalanced_je_fixed and remaining_unbalanced_count == 0:
            score += 15
            feedback_parts.append("Unbalanced journal entries fully fixed (15/15)")
            subscores['unbalanced_je'] = True
        elif unbalanced_je_fixed:
            score += 8
            feedback_parts.append(f"JE-2024-0047 fixed but {remaining_unbalanced_count} other unbalanced entries remain (8/15)")
            subscores['unbalanced_je'] = False
        else:
            feedback_parts.append(f"Unbalanced journal entries not fixed: {remaining_unbalanced_count} remaining (0/15)")
            subscores['unbalanced_je'] = False

        # 1b. Duplicate JE removed (10 pts)
        if duplicate_je_removed:
            score += 10
            feedback_parts.append("Duplicate journal entries removed (10/10)")
            subscores['duplicate_je'] = True
        elif remaining_duplicate_count < result.get('remaining_duplicate_count', remaining_duplicate_count) or remaining_duplicate_count == 0:
            # Partial: fewer duplicates than initial
            score += 5
            feedback_parts.append(f"Duplicate JE partially removed: {remaining_duplicate_count} remaining (5/10)")
            subscores['duplicate_je'] = False
        else:
            feedback_parts.append(f"Duplicate journal entries not removed: {remaining_duplicate_count} remaining (0/10)")
            subscores['duplicate_je'] = False

        # 1c. Intercompany elimination (15 pts)
        if intercompany_eliminated and pending_ic_eliminations == 0:
            score += 15
            feedback_parts.append("Intercompany eliminations fully completed (15/15)")
            subscores['intercompany'] = True
        elif pending_ic_eliminations < 99 and pending_ic_eliminations < result.get('pending_ic_eliminations', 99):
            score += 8
            feedback_parts.append(f"Intercompany eliminations partially done: {pending_ic_eliminations} pending (8/15)")
            subscores['intercompany'] = False
        elif intercompany_eliminated:
            score += 8
            feedback_parts.append(f"Intercompany elimination flagged but {pending_ic_eliminations} still pending (8/15)")
            subscores['intercompany'] = False
        else:
            feedback_parts.append(f"Intercompany eliminations not completed: {pending_ic_eliminations} pending (0/15)")
            subscores['intercompany'] = False

        # 1d. Capex reclassified (10 pts)
        if capex_reclassified:
            score += 10
            feedback_parts.append("Capital expenditure reclassified to PPE (10/10)")
            subscores['capex'] = True
        elif ppe_has_entry > 0:
            score += 5
            feedback_parts.append(f"PPE has {ppe_has_entry} entry/entries but capex not fully reclassified (5/10)")
            subscores['capex'] = False
        else:
            feedback_parts.append("Capital expenditure not reclassified (0/10)")
            subscores['capex'] = False

        # ---- Criterion 2: Materialized View (20 pts) ----
        mv_pts = 0
        mv_exists = trial_balance_mv_exists or (trial_balance_mv_alt_exists > 0)
        if mv_exists:
            mv_pts += 8
            feedback_parts.append("Trial balance materialized view exists (8/8)")
        else:
            feedback_parts.append("Trial balance materialized view not found (0/8)")

        if trial_balance_balances:
            mv_pts += 7
            feedback_parts.append("Trial balance balances correctly (7/7)")
        else:
            feedback_parts.append("Trial balance does not balance (0/7)")

        if rollup_used:
            mv_pts += 5
            feedback_parts.append("ROLLUP used in trial balance (5/5)")
        else:
            feedback_parts.append("ROLLUP not used in trial balance (0/5)")

        score += mv_pts
        subscores['materialized_view'] = mv_exists

        # ---- Criterion 3: Consolidated Report View (10 pts) ----
        if consolidated_vw_exists:
            score += 10
            feedback_parts.append("Consolidated report view exists (10/10)")
            subscores['consolidated_view'] = True
        else:
            feedback_parts.append("Consolidated report view not found (0/10)")
            subscores['consolidated_view'] = False

        # ---- Criterion 4: CSV Export (10 pts) ----
        csv_pts = 0
        if csv_exists and csv_size > 100:
            csv_pts += 5
            feedback_parts.append(f"CSV export exists ({csv_size} bytes) (5/5)")
        elif csv_exists:
            feedback_parts.append(f"CSV export exists but too small ({csv_size} bytes) (0/5)")
        else:
            feedback_parts.append("CSV export not found (0/5)")

        if csv_has_categories:
            csv_pts += 5
            feedback_parts.append("CSV contains financial categories (5/5)")
        else:
            feedback_parts.append("CSV missing financial categories (0/5)")

        score += csv_pts
        subscores['csv_export'] = csv_exists and csv_size > 100

        # ---- Criterion 5: GUI Usage (10 pts) ----
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
                        "Is there evidence of: journal entry corrections, intercompany eliminations, "
                        "materialized view creation, trial balance queries, or fiscal close SQL work? "
                        "Reply VERIFIED if fiscal period close reconciliation work is visible, else NOT_VERIFIED."
                    )
                    vlm_result = query_vlm(image=temp_ss.name, prompt=vlm_prompt)
                    if vlm_result and 'VERIFIED' in str(vlm_result).upper() and 'NOT_VERIFIED' not in str(vlm_result).upper():
                        if score < 95:
                            score = min(score + 5, 100)
                            feedback_parts.append("VLM: fiscal close work visible (+5 bonus)")
                finally:
                    os.unlink(temp_ss.name)
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")

        # ---- Pass conditions ----
        # At least 3 of 4 error corrections must be fixed
        errors_fixed = sum([
            subscores.get('unbalanced_je', False),
            subscores.get('duplicate_je', False),
            subscores.get('intercompany', False),
            subscores.get('capex', False),
        ])

        passed = (
            score >= 70 and
            errors_fixed >= 3
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
