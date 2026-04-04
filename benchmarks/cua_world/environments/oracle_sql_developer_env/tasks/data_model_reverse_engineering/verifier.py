#!/usr/bin/env python3
"""Verifier for Data Model Reverse Engineering task."""

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


def verify_data_model_reverse_engineering(traj, env_info, task_info):
    """
    Verify legacy schema data model reverse engineering task.

    Scoring (100 pts total):
    1. Table comments added for LEGACY_OPS tables (25 pts)
       - 8 tables commented: 25 pts
       - 5-7 tables: 18 pts
       - 3-4 tables: 10 pts
       - 1-2 tables: 5 pts
    2. Column comments added (20 pts)
       - >= 15 columns: 20 pts
       - 10-14 columns: 14 pts
       - 5-9 columns: 8 pts
       - 1-4 columns: 3 pts
    3. Primary key constraints added (20 pts)
       - >= 5 PKs: 20 pts
       - 3-4 PKs: 14 pts
       - 1-2 PKs: 7 pts
    4. Foreign key constraints added (10 pts)
       - >= 4 FKs: 10 pts
       - 2-3 FKs: 7 pts
       - 1 FK: 3 pts
    5. Schema analysis report exported (25 pts)
       - Exists, meaningful (>500 bytes), mentions tables and relationships: 25 pts
       - Exists and meaningful but incomplete: 15 pts
       - Exists but thin (<500 bytes): 8 pts

    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/data_model_reverse_engineering_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        new_table_comments = result.get('new_table_comments', 0)
        new_col_comments = result.get('new_col_comments', 0)
        table_comment_count = result.get('table_comment_count', 0)
        col_comment_count = result.get('col_comment_count', 0)
        min_comment_len = result.get('min_comment_length', 0)

        new_pk_count = result.get('new_pk_count', 0)
        pk_count = result.get('pk_count', 0)
        t_cli_pk = result.get('t_cli_pk', False)
        t_ord_pk = result.get('t_ord_pk', False)
        t_prd_pk = result.get('t_prd_pk', False)
        t_cat_pk = result.get('t_cat_pk', False)
        t_emp_pk = result.get('t_emp_pk', False)
        t_dept_pk = result.get('t_dept_pk', False)

        new_fk_count = result.get('new_fk_count', 0)
        fk_count = result.get('fk_count', 0)
        t_ord_cli_fk = result.get('t_ord_cli_fk', False)
        t_ord_emp_fk = result.get('t_ord_emp_fk', False)
        t_ord_itm_ord_fk = result.get('t_ord_itm_ord_fk', False)
        t_ord_itm_prd_fk = result.get('t_ord_itm_prd_fk', False)
        t_prd_cat_fk = result.get('t_prd_cat_fk', False)
        t_emp_dept_fk = result.get('t_emp_dept_fk', False)

        report_exists = result.get('report_exists', False)
        report_size = result.get('report_size', 0)
        report_meaningful = result.get('report_meaningful', False)
        report_mentions_tables = result.get('report_mentions_tables', False)
        report_mentions_relationships = result.get('report_mentions_relationships', False)

        gui_evidence = result.get('gui_evidence', {})

        # Criterion 1: Table comments (25 pts)
        # Use new_table_comments but also count total in case initial wasn't 0
        effective_table_comments = max(new_table_comments, table_comment_count)
        if effective_table_comments >= 8:
            score += 25
            feedback_parts.append(f"All 8 tables commented (25/25)")
            subscores['table_comments'] = True
        elif effective_table_comments >= 5:
            score += 18
            feedback_parts.append(f"{effective_table_comments}/8 tables commented (18/25)")
            subscores['table_comments'] = True
        elif effective_table_comments >= 3:
            score += 10
            feedback_parts.append(f"{effective_table_comments}/8 tables commented (10/25)")
            subscores['table_comments'] = False
        elif effective_table_comments >= 1:
            score += 5
            feedback_parts.append(f"{effective_table_comments}/8 tables commented (5/25)")
            subscores['table_comments'] = False
        else:
            feedback_parts.append("No table comments added to LEGACY_OPS (0/25)")
            subscores['table_comments'] = False

        # Criterion 2: Column comments (20 pts)
        effective_col_comments = max(new_col_comments, col_comment_count)
        if effective_col_comments >= 15:
            score += 20
            feedback_parts.append(f"{effective_col_comments} column comments added (20/20)")
            subscores['col_comments'] = True
        elif effective_col_comments >= 10:
            score += 14
            feedback_parts.append(f"{effective_col_comments} column comments added (14/20)")
            subscores['col_comments'] = True
        elif effective_col_comments >= 5:
            score += 8
            feedback_parts.append(f"{effective_col_comments} column comments added (8/20)")
            subscores['col_comments'] = False
        elif effective_col_comments >= 1:
            score += 3
            feedback_parts.append(f"{effective_col_comments} column comments added (3/20)")
            subscores['col_comments'] = False
        else:
            feedback_parts.append("No column comments added to LEGACY_OPS (0/20)")
            subscores['col_comments'] = False

        # Criterion 3: Primary key constraints (20 pts)
        effective_pks = max(new_pk_count, pk_count)
        pk_tables = [t for t, has_pk in [
            ("T_CLI", t_cli_pk), ("T_ORD", t_ord_pk), ("T_PRD", t_prd_pk),
            ("T_CAT", t_cat_pk), ("T_EMP", t_emp_pk), ("T_DEPT", t_dept_pk)
        ] if has_pk]

        if effective_pks >= 5 or len(pk_tables) >= 5:
            score += 20
            feedback_parts.append(f"PKs added to: {', '.join(pk_tables)} ({len(pk_tables)}/6 tables) (20/20)")
            subscores['pk_constraints'] = True
        elif effective_pks >= 3 or len(pk_tables) >= 3:
            score += 14
            feedback_parts.append(f"PKs added to: {', '.join(pk_tables)} ({len(pk_tables)}/6 tables) (14/20)")
            subscores['pk_constraints'] = True
        elif effective_pks >= 1 or len(pk_tables) >= 1:
            score += 7
            feedback_parts.append(f"PKs added to: {', '.join(pk_tables) or str(effective_pks) + ' tables'} (7/20)")
            subscores['pk_constraints'] = False
        else:
            feedback_parts.append("No primary key constraints added to LEGACY_OPS tables (0/20)")
            subscores['pk_constraints'] = False

        # Criterion 4: Foreign key constraints (10 pts)
        effective_fks = max(new_fk_count, fk_count)
        fk_relationships = [r for r, has_fk in [
            ("T_ORD→T_CLI", t_ord_cli_fk),
            ("T_ORD→T_EMP", t_ord_emp_fk),
            ("T_ORD_ITM→T_ORD", t_ord_itm_ord_fk),
            ("T_ORD_ITM→T_PRD", t_ord_itm_prd_fk),
            ("T_PRD→T_CAT", t_prd_cat_fk),
            ("T_EMP→T_DEPT", t_emp_dept_fk),
        ] if has_fk]

        if effective_fks >= 4 or len(fk_relationships) >= 4:
            score += 10
            feedback_parts.append(f"FKs added: {', '.join(fk_relationships[:4])}{'...' if len(fk_relationships) > 4 else ''} ({len(fk_relationships)}/6) (10/10)")
            subscores['fk_constraints'] = True
        elif effective_fks >= 2 or len(fk_relationships) >= 2:
            score += 7
            feedback_parts.append(f"FKs added: {', '.join(fk_relationships)} ({len(fk_relationships)}/6) (7/10)")
            subscores['fk_constraints'] = False
        elif effective_fks >= 1 or len(fk_relationships) >= 1:
            score += 3
            feedback_parts.append(f"FKs added: {', '.join(fk_relationships)} (3/10)")
            subscores['fk_constraints'] = False
        else:
            feedback_parts.append("No foreign key constraints added to LEGACY_OPS (0/10)")
            subscores['fk_constraints'] = False

        # Criterion 5: Schema analysis report (25 pts)
        if report_exists and report_meaningful and report_mentions_tables and report_mentions_relationships:
            score += 25
            feedback_parts.append(f"Schema analysis report complete ({report_size} bytes, covers tables and relationships) (25/25)")
            subscores['report'] = True
        elif report_exists and report_meaningful and (report_mentions_tables or report_mentions_relationships):
            score += 15
            feedback_parts.append(f"Schema analysis report exists ({report_size} bytes) but incomplete coverage (15/25)")
            subscores['report'] = False
        elif report_exists and report_size > 50:
            score += 8
            feedback_parts.append(f"Schema analysis report exists but thin ({report_size} bytes) (8/25)")
            subscores['report'] = False
        else:
            feedback_parts.append("Schema analysis report not found at /home/ga/Documents/exports/legacy_ops_analysis.txt (0/25)")
            subscores['report'] = False

        # GUI usage (absorbed into score, noted in feedback)
        gui_used, gui_frac, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(gui_frac * 10)  # up to 10 bonus for GUI in this task
        score = min(score + gui_pts, 100)
        subscores['gui'] = gui_used
        if gui_used:
            feedback_parts.append(f"GUI confirmed ({gui_details})")
        else:
            feedback_parts.append(f"GUI evidence: {gui_details}")

        # VLM bonus
        if query_vlm:
            try:
                temp_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_ss.name)
                    vlm_prompt = (
                        "Examine this Oracle SQL Developer screenshot. "
                        "Is there evidence of: COMMENT ON TABLE or COMMENT ON COLUMN statements, "
                        "ALTER TABLE ADD CONSTRAINT statements, table browser showing LEGACY_OPS schema, "
                        "or a Data Modeler diagram? "
                        "Reply VERIFIED if schema documentation or data modeling work is visible, else NOT_VERIFIED."
                    )
                    vlm_result = query_vlm(image=temp_ss.name, prompt=vlm_prompt)
                    if vlm_result and 'VERIFIED' in str(vlm_result).upper() and 'NOT_VERIFIED' not in str(vlm_result).upper():
                        if score < 95:
                            score = min(score + 5, 100)
                            feedback_parts.append("VLM: schema documentation work visible (+5 bonus)")
                finally:
                    os.unlink(temp_ss.name)
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")

        # Pass: must have table_comments + pk_constraints + score >= 60
        passed = (
            subscores.get('table_comments', False) and
            subscores.get('pk_constraints', False) and
            score >= 60
        )

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
