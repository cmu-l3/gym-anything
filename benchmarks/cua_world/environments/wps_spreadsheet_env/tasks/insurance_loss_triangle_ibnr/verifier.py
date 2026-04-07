#!/usr/bin/env python3
"""Verifier for insurance_loss_triangle_ibnr task.

This task requires building a loss development triangle from raw claims data,
computing age-to-age development factors, projecting ultimate losses using the
chain-ladder method, and comparing with the Bornhuetter-Ferguson method.

Actual verification is done externally via VLM evaluators (vlm_checklist_verifier).
This stub performs basic structural checks only.
"""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_insurance_loss_triangle_ibnr(traj, env_info, task_info):
    """Stub verifier with basic structural checks.
    Real verification is done via external VLM evaluation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read exported metadata JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Anti-gaming: file must exist and be modified during task
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output spreadsheet file not found."}

    if not result.get('file_modified_during_task', False):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task."}

    # Try to open the output file for structural checks
    found_path = result.get('found_path', '/home/ga/Documents/loss_reserve_analysis.xlsx')
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        found_path, copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open spreadsheet: {error}"}

    try:
        score = 0
        feedback_parts = []

        # Check for required sheets
        sheet_names_lower = [s.lower() for s in wb.sheetnames]

        has_triangle = any('triangle' in s for s in sheet_names_lower)
        has_factors = any('factor' in s for s in sheet_names_lower)
        has_projections = any('project' in s for s in sheet_names_lower)
        has_summary = any('summary' in s for s in sheet_names_lower)

        if has_triangle:
            score += 20
            feedback_parts.append("Triangle sheet: found")
        else:
            feedback_parts.append("Triangle sheet: NOT found")

        if has_factors:
            score += 20
            feedback_parts.append("Factors sheet: found")
        else:
            feedback_parts.append("Factors sheet: NOT found")

        if has_projections:
            score += 20
            feedback_parts.append("Projections sheet: found")
        else:
            feedback_parts.append("Projections sheet: NOT found")

        if has_summary:
            score += 20
            feedback_parts.append("Summary sheet: found")
        else:
            feedback_parts.append("Summary sheet: NOT found")

        # Check formula count as a proxy for real work
        formula_count = result.get('formula_count', 0)
        if formula_count >= 30:
            score += 20
            feedback_parts.append(f"Formulas: {formula_count} found (sufficient)")
        elif formula_count >= 10:
            score += 10
            feedback_parts.append(f"Formulas: {formula_count} found (partial)")
        else:
            feedback_parts.append(f"Formulas: {formula_count} found (insufficient)")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
