#!/usr/bin/env python3
"""Verifier for Assembly Line Pattern Detection task."""

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
    return gui_used, min(signals / 2.0, 1.0), "; ".join(details) or "No signals"


def verify_assembly_line_pattern_detection(traj, env_info, task_info):
    """
    Verify assembly line pattern detection task completion.

    Scoring (100 pts total):
    1. CASCADE_FAILURES_VW (20 pts): exists+MATCH_RECOGNIZE (15 pts), returns >= 2 rows (5 pts)
    2. QUALITY_DEGRADATION_VW (20 pts): exists+MATCH_RECOGNIZE (15 pts), returns >= 2 rows (5 pts)
    3. SHORT_RUN_CYCLES_VW (20 pts): exists+MATCH_RECOGNIZE (15 pts), returns >= 2 rows (5 pts)
    4. PATTERN_RESULTS table (8 pts): >= 6 rows with >= 2 pattern types
    5. PROC_DAILY_PATTERN_SCAN (8 pts): procedure exists
    6. PATTERN_SUMMARY_MV (8 pts): exists+ROLLUP
    7. CSV Export (6 pts): file exists, size > 50, modified during task
    8. GUI Usage (10 pts): evidence of using SQL Developer

    Pass threshold: 60 pts AND at least two MATCH_RECOGNIZE views exist and return data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/pattern_detection_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        valid_match_views = 0

        # Criterion 1: CASCADE_FAILURES_VW
        if result.get('cascade_vw_exists') and result.get('cascade_has_match'):
            score += 15
            feedback_parts.append("CASCADE view exists with MATCH_RECOGNIZE (+15)")
            if result.get('cascade_rows', 0) >= 2:
                score += 5
                valid_match_views += 1
                feedback_parts.append("CASCADE view returns data (+5)")
            else:
                feedback_parts.append("CASCADE view returns insufficient data")
        else:
            feedback_parts.append("CASCADE view missing or no MATCH_RECOGNIZE")

        # Criterion 2: QUALITY_DEGRADATION_VW
        if result.get('quality_vw_exists') and result.get('quality_has_match'):
            score += 15
            feedback_parts.append("QUALITY view exists with MATCH_RECOGNIZE (+15)")
            if result.get('quality_rows', 0) >= 2:
                score += 5
                valid_match_views += 1
                feedback_parts.append("QUALITY view returns data (+5)")
            else:
                feedback_parts.append("QUALITY view returns insufficient data")
        else:
            feedback_parts.append("QUALITY view missing or no MATCH_RECOGNIZE")

        # Criterion 3: SHORT_RUN_CYCLES_VW
        if result.get('short_run_vw_exists') and result.get('short_run_has_match'):
            score += 15
            feedback_parts.append("SHORT_RUN view exists with MATCH_RECOGNIZE (+15)")
            if result.get('short_run_rows', 0) >= 2:
                score += 5
                valid_match_views += 1
                feedback_parts.append("SHORT_RUN view returns data (+5)")
            else:
                feedback_parts.append("SHORT_RUN view returns insufficient data")
        else:
            feedback_parts.append("SHORT_RUN view missing or no MATCH_RECOGNIZE")

        # Criterion 4: PATTERN_RESULTS table
        rows = result.get('pattern_results_rows', 0)
        types = result.get('pattern_results_types', 0)
        if rows >= 6 and types >= 2:
            score += 8
            feedback_parts.append("PATTERN_RESULTS populated (+8)")
        elif rows > 0:
            score += 4
            feedback_parts.append("PATTERN_RESULTS partially populated (+4)")

        # Criterion 5: PROC_DAILY_PATTERN_SCAN
        if result.get('proc_exists'):
            score += 8
            feedback_parts.append("PROC_DAILY_PATTERN_SCAN exists (+8)")

        # Criterion 6: PATTERN_SUMMARY_MV
        if result.get('mv_exists') and result.get('mv_has_rollup'):
            score += 8
            feedback_parts.append("PATTERN_SUMMARY_MV exists with ROLLUP (+8)")
        elif result.get('mv_exists'):
            score += 4
            feedback_parts.append("PATTERN_SUMMARY_MV exists without ROLLUP (+4)")

        # Criterion 7: CSV Export
        if result.get('csv_exists') and result.get('csv_size_bytes', 0) > 20 and result.get('csv_modified_during_task'):
            score += 6
            feedback_parts.append("CSV exported successfully (+6)")

        # Criterion 8: GUI Usage
        gui_used, _, gui_details = _check_gui_usage(result.get('gui_evidence', {}))
        if gui_used:
            score += 10
            feedback_parts.append(f"GUI usage confirmed [{gui_details}] (+10)")

        # Final Evaluation
        passed = (score >= 60) and (valid_match_views >= 2)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }