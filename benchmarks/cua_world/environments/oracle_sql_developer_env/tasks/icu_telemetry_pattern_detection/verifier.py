#!/usr/bin/env python3
"""Verifier for ICU Telemetry Pattern Detection task."""

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

def verify_icu_telemetry_pattern_detection(traj, env_info, task_info):
    """
    Verify ICU Telemetry Pattern Detection task completion.

    Scoring (100 pts total):
    1. JSON Shredding (20 pts): parsed_vitals_exists AND json_table_used
    2. Time-Series Imputation (20 pts): clean_vitals_exists AND ignore_nulls_used
    3. Hypoglycemia Pattern (20 pts): hypoglycemia_exists AND match_recognize_used AND hypo_match_count > 0
    4. Tachycardia Pattern (20 pts): tachycardia_exists AND match_recognize_used AND tachy_match_count > 0
    5. CSV Export (10 pts): csv_exists AND csv_size > 0
    6. GUI Utilization (10 pts): 2+ gui signals

    Pass threshold: 80 pts (Must successfully implement BOTH patterns)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/icu_telemetry_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []

        # Read results
        parsed_vitals_exists = result.get('parsed_vitals_exists', False)
        clean_vitals_exists = result.get('clean_vitals_exists', False)
        hypoglycemia_exists = result.get('hypoglycemia_exists', False)
        tachycardia_exists = result.get('tachycardia_exists', False)
        json_table_used = result.get('json_table_used', False)
        ignore_nulls_used = result.get('ignore_nulls_used', False)
        match_recognize_used = result.get('match_recognize_used', False)
        hypo_match_count = result.get('hypo_match_count', 0)
        tachy_match_count = result.get('tachy_match_count', 0)
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        gui_evidence = result.get('gui_evidence', {})

        # Criterion 1: JSON Shredding
        if parsed_vitals_exists and json_table_used:
            score += 20
            feedback_parts.append("JSON_TABLE correctly implemented (20/20)")
        elif parsed_vitals_exists:
            score += 10
            feedback_parts.append("Parsed view exists but JSON_TABLE function missing from source (10/20)")
        else:
            feedback_parts.append("JSON parsing view missing (0/20)")

        # Criterion 2: Time-Series Imputation
        if clean_vitals_exists and ignore_nulls_used:
            score += 20
            feedback_parts.append("IGNORE NULLS imputation correctly implemented (20/20)")
        elif clean_vitals_exists:
            score += 10
            feedback_parts.append("Clean materialized view exists but IGNORE NULLS missing (10/20)")
        else:
            feedback_parts.append("Imputation materialized view missing (0/20)")

        # Criterion 3: Hypoglycemia Pattern
        hypo_score = 0
        if hypoglycemia_exists and match_recognize_used:
            if hypo_match_count > 0:
                hypo_score = 20
                feedback_parts.append(f"Hypoglycemia MATCH_RECOGNIZE successful, matches={hypo_match_count} (20/20)")
            else:
                hypo_score = 10
                feedback_parts.append("Hypoglycemia MATCH_RECOGNIZE view exists but logic caught 0 matches (10/20)")
        else:
            feedback_parts.append("Hypoglycemia MATCH_RECOGNIZE logic missing (0/20)")
        score += hypo_score

        # Criterion 4: Tachycardia Pattern
        tachy_score = 0
        if tachycardia_exists and match_recognize_used:
            if tachy_match_count > 0:
                tachy_score = 20
                feedback_parts.append(f"Tachycardia MATCH_RECOGNIZE successful, matches={tachy_match_count} (20/20)")
            else:
                tachy_score = 10
                feedback_parts.append("Tachycardia MATCH_RECOGNIZE view exists but logic caught 0 matches (10/20)")
        else:
            feedback_parts.append("Tachycardia MATCH_RECOGNIZE logic missing (0/20)")
        score += tachy_score

        # Criterion 5: CSV Export
        if csv_exists and csv_size > 0:
            score += 10
            feedback_parts.append("CSV export successful (10/10)")
        else:
            feedback_parts.append("CSV export missing or empty (0/10)")

        # Criterion 6: GUI Usage
        gui_used, _, gui_details = _check_gui_usage(gui_evidence)
        if gui_used:
            score += 10
            feedback_parts.append(f"GUI usage confirmed [{gui_details}] (10/10)")
        else:
            feedback_parts.append("No GUI usage detected (0/10)")

        # Pass logic
        passed = (score >= 80) and (hypo_score == 20) and (tachy_score == 20)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Error in verifier: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with exception: {str(e)}"}