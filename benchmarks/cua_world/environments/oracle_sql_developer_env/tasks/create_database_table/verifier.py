#!/usr/bin/env python3
"""Verifier for Create Database Table task in Oracle SQL Developer."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used (not just command-line tools).

    Returns (gui_used: bool, gui_score: float 0-1, details: str)
    """
    if not gui_evidence:
        return False, 0.0, "No GUI evidence collected"

    signals = 0
    total_signals = 4
    details = []

    mru = gui_evidence.get('mru_connection_count', 0)
    if mru > 0:
        signals += 1
        details.append(f"MRU cache has {mru} connections")

    if gui_evidence.get('window_title_changed', False):
        signals += 1
        details.append(f"Window title: {gui_evidence.get('window_title', '')}")

    sessions = gui_evidence.get('sqldev_oracle_sessions', 0)
    if sessions > 0:
        signals += 1
        details.append(f"{sessions} active SQL Developer DB sessions")

    history = gui_evidence.get('sql_history_count', 0)
    if history > 0:
        signals += 1
        details.append(f"{history} SQL history entries")

    gui_used = signals >= 2
    gui_score = min(signals / total_signals, 1.0)
    detail_str = "; ".join(details) if details else "No GUI interaction detected"
    return gui_used, gui_score, detail_str


def verify_create_database_table(traj, env_info, task_info):
    """
    Verify that TRAINING_COURSES table was created with correct structure and data.

    Criteria (100 pts total):
    1. Table exists with correct columns (20 pts)
    2. Table has at least 3 rows of data (15 pts)
    3. Table has primary key and FK referencing DEPARTMENTS (20 pts)
    4. GUI usage verified (25 pts)
    5. VLM verification (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')
    metadata = task_info.get('metadata', {})
    expected_columns = [c.upper() for c in metadata.get('expected_columns', [])]
    min_rows = metadata.get('min_rows', 3)

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/table_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        table_exists = result.get('table_exists', False)
        row_count = result.get('table_row_count', 0)
        column_count = result.get('column_count', 0)
        columns_found = result.get('columns_found', '')
        has_pk = result.get('has_primary_key', False)
        has_fk = result.get('has_foreign_key', False)
        fk_refs_dept = result.get('fk_references_departments', False)
        newly_created = result.get('table_newly_created', False)
        gui_evidence = result.get('gui_evidence', {})

        logger.info(f"Result: exists={table_exists}, rows={row_count}, cols={column_count}, "
                    f"pk={has_pk}, fk={has_fk}, fk_dept={fk_refs_dept}, gui={gui_evidence}")

        # CRITICAL: Table must exist
        if not table_exists:
            return {
                "passed": False, "score": 0,
                "feedback": "FAILED: TRAINING_COURSES table does not exist in HR schema",
                "subscores": {"table_exists": False, "correct_columns": False,
                              "has_data": False, "has_constraints": False,
                              "gui_verified": False, "vlm_verified": False}
            }

        # Criterion 1: Table exists with correct columns (20 pts)
        actual_cols = [c.strip().upper() for c in columns_found.split(',') if c.strip()]
        if expected_columns:
            matched_cols = sum(1 for c in expected_columns if c in actual_cols)
            if matched_cols >= len(expected_columns):
                score += 20
                feedback_parts.append(f"All {len(expected_columns)} expected columns present")
                subscores['correct_columns'] = True
            elif matched_cols >= 4:
                score += 14
                feedback_parts.append(f"Most columns present: {matched_cols}/{len(expected_columns)}")
                subscores['correct_columns'] = True
            elif matched_cols >= 2:
                score += 8
                feedback_parts.append(f"Some columns present: {matched_cols}/{len(expected_columns)}")
                subscores['correct_columns'] = False
            else:
                feedback_parts.append(f"Missing columns: only {matched_cols}/{len(expected_columns)} found")
                subscores['correct_columns'] = False
        elif column_count >= 4:
            score += 10
            feedback_parts.append(f"Table has {column_count} columns")
            subscores['correct_columns'] = False

        # Criterion 2: Has data rows (15 pts)
        if row_count >= min_rows:
            score += 15
            feedback_parts.append(f"Table has {row_count} rows (required >= {min_rows})")
            subscores['has_data'] = True
        elif row_count > 0:
            score += 5
            feedback_parts.append(f"Table has {row_count} rows (need >= {min_rows})")
            subscores['has_data'] = False
        else:
            feedback_parts.append("Table is empty - no data inserted")
            subscores['has_data'] = False

        # Criterion 3: Constraints - PK required, FK must reference DEPARTMENTS (20 pts)
        if has_pk and fk_refs_dept:
            score += 20
            feedback_parts.append("Primary key and FK referencing DEPARTMENTS present")
            subscores['has_constraints'] = True
        elif has_pk and has_fk:
            score += 14
            feedback_parts.append("PK + FK present (but FK target not verified as DEPARTMENTS)")
            subscores['has_constraints'] = True
        elif has_pk:
            score += 10
            feedback_parts.append("Primary key present (no foreign key)")
            subscores['has_constraints'] = False
        elif has_fk:
            score += 5
            feedback_parts.append("Foreign key present (no primary key)")
            subscores['has_constraints'] = False
        else:
            feedback_parts.append("No constraints defined")
            subscores['has_constraints'] = False

        # Criterion 4: GUI usage verified (25 pts) - CRITICAL
        gui_used, gui_score_frac, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(gui_score_frac * 25)
        score += gui_pts
        subscores['gui_verified'] = gui_used
        if gui_used:
            feedback_parts.append(f"GUI usage confirmed ({gui_details})")
        elif gui_pts > 0:
            feedback_parts.append(f"Partial GUI evidence ({gui_details})")
        else:
            feedback_parts.append("No GUI usage evidence - task may have been done via command line")

        # Criterion 5: VLM verification (20 pts)
        vlm_verified = False
        if query_vlm:
            try:
                temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
                    vlm_prompt = """Analyze this screenshot of Oracle SQL Developer.
                    Questions:
                    1. Is there a SQL Worksheet showing CREATE TABLE or INSERT statements?
                    2. Can you see a TRAINING_COURSES table in the schema browser?
                    3. Are there query results showing training course data?
                    4. Does the interface show successful SQL execution?
                    Respond with "VERIFIED" if table creation evidence is visible,
                    or "NOT VERIFIED" if not."""
                    vlm_result = query_vlm(image=temp_screenshot.name, prompt=vlm_prompt)
                    if vlm_result:
                        vlm_text = str(vlm_result).upper()
                        if 'VERIFIED' in vlm_text and 'NOT VERIFIED' not in vlm_text:
                            vlm_verified = True
                finally:
                    os.unlink(temp_screenshot.name)
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")

        subscores['vlm_verified'] = vlm_verified
        if vlm_verified:
            score += 20
            feedback_parts.append("VLM: Table creation verified visually")
        elif table_exists and row_count >= min_rows and gui_used:
            score += 5
            feedback_parts.append("VLM: Not verified (but database + GUI validates)")
        else:
            feedback_parts.append("VLM: Not verified")

        passed = (
            table_exists and
            row_count >= min_rows and
            has_pk and
            gui_used and
            score >= 70
        )

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {e}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}
