#!/usr/bin/env python3
"""Verifier for Export ER Diagram task in Oracle SQL Developer."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REQUIRED_TABLES = {"EMPLOYEES", "DEPARTMENTS", "JOBS", "LOCATIONS"}


def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used."""
    if not gui_evidence:
        return False, 0.0, "No GUI evidence collected"

    signals = 0
    total_signals = 4
    details = []

    if gui_evidence.get('mru_connection_count', 0) > 0:
        signals += 1
        details.append(f"MRU cache: {gui_evidence['mru_connection_count']}")
    if gui_evidence.get('window_title_changed', False):
        signals += 1
        details.append(f"Window: {gui_evidence.get('window_title', '')}")
    if gui_evidence.get('sqldev_oracle_sessions', 0) > 0:
        signals += 1
        details.append(f"{gui_evidence['sqldev_oracle_sessions']} DB sessions")
    if gui_evidence.get('sql_history_count', 0) > 0:
        signals += 1
        details.append(f"{gui_evidence['sql_history_count']} history entries")

    gui_used = signals >= 2
    gui_score = min(signals / total_signals, 1.0)
    return gui_used, gui_score, "; ".join(details) if details else "No GUI interaction"


def verify_export_er_diagram(traj, env_info, task_info):
    """
    Verify that an ER diagram was generated from the HR schema.

    Criteria (100 pts total):
    1. Diagram image file exists with reasonable size (20 pts)
    2. Diagram content verified - HR tables present in DM XML or SVG (15 pts)
    3. Data Modeler was used (evidence of DM activity) (15 pts)
    4. GUI usage verified (25 pts)
    5. VLM verification of diagram content (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/er_diagram_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        diagram_exists = result.get('diagram_file_exists', False)
        diagram_size = result.get('diagram_file_size', 0)
        dm_opened = result.get('data_modeler_opened', False)
        dm_designs = result.get('dm_designs_exist', False)
        dm_xml_tables_str = result.get('dm_xml_tables', '')
        diagram_content_tables_str = result.get('diagram_content_tables', '')
        gui_evidence = result.get('gui_evidence', {})

        if not diagram_exists:
            return {
                "passed": False, "score": 0,
                "feedback": "FAILED: No diagram file found in /home/ga/Documents/exports/",
                "subscores": {"diagram_file": False, "diagram_content": False,
                              "data_modeler_used": False,
                              "gui_verified": False, "vlm_verified": False}
            }

        # Criterion 1: Diagram file exists with reasonable size (20 pts)
        if diagram_size > 5000:
            score += 20
            feedback_parts.append(f"Diagram file exists ({diagram_size} bytes)")
            subscores['diagram_file'] = True
        elif diagram_size > 1000:
            score += 12
            feedback_parts.append(f"Diagram file small ({diagram_size} bytes)")
            subscores['diagram_file'] = True
        else:
            score += 3
            feedback_parts.append(f"Diagram file very small ({diagram_size} bytes)")
            subscores['diagram_file'] = False

        # Criterion 2: Diagram content - HR tables found in DM XML or SVG (15 pts)
        dm_xml_tables = set(t.strip().upper() for t in dm_xml_tables_str.split(',') if t.strip())
        svg_tables = set(t.strip().upper() for t in diagram_content_tables_str.split(',') if t.strip())
        all_content_tables = dm_xml_tables | svg_tables

        matched_tables = REQUIRED_TABLES & all_content_tables
        content_verified = len(matched_tables) >= 3

        if len(matched_tables) >= 4:
            score += 15
            feedback_parts.append(f"All {len(matched_tables)} required tables found in diagram/DM data")
            subscores['diagram_content'] = True
        elif len(matched_tables) >= 2:
            score += 8
            feedback_parts.append(f"{len(matched_tables)}/4 required tables found: {', '.join(matched_tables)}")
            subscores['diagram_content'] = True
        elif len(matched_tables) > 0:
            score += 3
            feedback_parts.append(f"Only {len(matched_tables)} table(s) found: {', '.join(matched_tables)}")
            subscores['diagram_content'] = False
        else:
            feedback_parts.append("No HR table names found in diagram content or DM data")
            subscores['diagram_content'] = False

        # Criterion 3: Data Modeler was used (15 pts)
        if dm_opened and dm_designs:
            score += 15
            feedback_parts.append("Data Modeler opened and design files created")
            subscores['data_modeler_used'] = True
        elif dm_opened or dm_designs:
            score += 8
            feedback_parts.append("Partial Data Modeler evidence")
            subscores['data_modeler_used'] = True
        else:
            feedback_parts.append("No Data Modeler evidence found")
            subscores['data_modeler_used'] = False

        # Criterion 4: GUI usage verified (25 pts)
        gui_used, gui_score_frac, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(gui_score_frac * 25)
        score += gui_pts
        subscores['gui_verified'] = gui_used
        if gui_used:
            feedback_parts.append(f"GUI confirmed ({gui_details})")
        elif gui_pts > 0:
            feedback_parts.append(f"Partial GUI evidence ({gui_details})")
        else:
            feedback_parts.append("No GUI usage evidence")

        # Criterion 5: VLM verification of diagram (25 pts)
        vlm_verified = False
        if query_vlm:
            try:
                temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
                    vlm_prompt = """Analyze this screenshot of Oracle SQL Developer.
                    Questions:
                    1. Is there an ER diagram or Data Modeler view visible?
                    2. Can you see table boxes with names like EMPLOYEES, DEPARTMENTS, JOBS, LOCATIONS?
                    3. Are there relationship lines (foreign key connections) between tables?
                    4. Does the diagram show column names within the table boxes?
                    Respond with "VERIFIED" if an ER diagram with HR schema tables is visible,
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
            score += 25
            feedback_parts.append("VLM: ER diagram with tables visible")
        elif diagram_exists and content_verified and gui_used:
            score += 5
            feedback_parts.append("VLM: Not verified (but content + GUI validates)")
        else:
            feedback_parts.append("VLM: Not verified")

        passed = diagram_exists and diagram_size > 5000 and gui_used and score >= 65

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
