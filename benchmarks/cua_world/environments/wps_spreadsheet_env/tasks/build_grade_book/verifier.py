#!/usr/bin/env python3
"""Verifier for build_grade_book task."""

import sys
import os
import json
import tempfile
import logging

# Ensure access to WPS verification utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_grade_book(traj, env_info, task_info):
    """Verify grade book modifications."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check anti-gaming (file modification)
    if not result.get("file_modified_during_task", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "File was not modified during the task execution."
        }

    # Open spreadsheet
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/math_grades.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open spreadsheet: {error}"}

    try:
        score = 0
        feedback_parts = []
        sheet = wb.active

        # 1. Headers Check (10 points)
        f1_val = str(sheet['F1'].value or '').strip().lower()
        if 'weighted' in f1_val and 'average' in f1_val:
            score += 5
            feedback_parts.append("F1 Header: OK")
        else:
            feedback_parts.append("F1 Header: Missing/Incorrect")

        g1_val = str(sheet['G1'].value or '').strip().lower()
        if 'letter' in g1_val and 'grade' in g1_val:
            score += 5
            feedback_parts.append("G1 Header: OK")
        else:
            feedback_parts.append("G1 Header: Missing/Incorrect")

        # 2. Weighted Average Formulas & Weights (30 points)
        f_formulas = 0
        f_weights_correct = 0
        for r in range(2, 52):
            val = str(sheet.cell(row=r, column=6).value or '').upper()
            if val.startswith('='):
                f_formulas += 1
                # Check for standard weight representation (0.1, .1, 10%)
                if (('0.1' in val or '.1' in val or '10%' in val) and 
                    ('0.2' in val or '.2' in val or '20%' in val) and 
                    ('0.3' in val or '.3' in val or '30%' in val) and 
                    ('0.4' in val or '.4' in val or '40%' in val)):
                    f_weights_correct += 1

        if f_formulas == 50:
            score += 15
            feedback_parts.append("F Formulas: 50/50 present")
        elif f_formulas > 0:
            pts = int(15 * (f_formulas / 50))
            score += pts
            feedback_parts.append(f"F Formulas: {f_formulas}/50 present")
        else:
            feedback_parts.append("F Formulas: Missing")

        if f_weights_correct == 50:
            score += 15
            feedback_parts.append("F Formula Weights: All Correct")
        elif f_weights_correct > 0:
            pts = int(15 * (f_weights_correct / 50))
            score += pts
            feedback_parts.append(f"F Formula Weights: Partial ({f_weights_correct}/50)")
        else:
            feedback_parts.append("F Formula Weights: Missing/Incorrect")

        # 3. Letter Grade IF Logic (20 points)
        g_formulas = 0
        g_logic_correct = 0
        for r in range(2, 52):
            val = str(sheet.cell(row=r, column=7).value or '').upper()
            if val.startswith('='):
                g_formulas += 1
                if 'IF' in val:
                    if '90' in val and '80' in val and '70' in val and '60' in val:
                        g_logic_correct += 1

        if g_formulas == 50:
            score += 10
            feedback_parts.append("G Formulas: 50/50 present")
        elif g_formulas > 0:
            pts = int(10 * (g_formulas / 50))
            score += pts
            feedback_parts.append(f"G Formulas: {g_formulas}/50 present")
        else:
            feedback_parts.append("G Formulas: Missing")

        if g_logic_correct == 50:
            score += 10
            feedback_parts.append("G Thresholds: All Correct")
        elif g_logic_correct > 0:
            pts = int(10 * (g_logic_correct / 50))
            score += pts
            feedback_parts.append(f"G Thresholds: Partial ({g_logic_correct}/50)")
        else:
            feedback_parts.append("G Thresholds: Missing/Incorrect")

        # 4. Summary Statistics (35 points)
        summary_labels_found = 0
        for r in range(52, 58):
            label = str(sheet.cell(row=r, column=1).value or '').strip().lower()
            if 'average' in label or 'highest' in label or 'lowest' in label or 'passing' in label:
                summary_labels_found += 1
        
        if summary_labels_found >= 4:
            score += 5
            feedback_parts.append("Summary Labels: Found")
        
        # We need to find the specific rows based on their labels or their strict locations
        b53 = str(sheet['B53'].value or '').upper()
        b54 = str(sheet['B54'].value or '').upper()
        b55 = str(sheet['B55'].value or '').upper()
        b56 = str(sheet['B56'].value or '').upper()

        if b53.startswith('=') and ('AVERAGE' in b53 or 'SUM' in b53) and 'F' in b53:
            score += 8
            feedback_parts.append("Average Stat: OK")
        else:
            feedback_parts.append("Average Stat: Missing/Incorrect")

        if b54.startswith('=') and 'MAX' in b54 and 'F' in b54:
            score += 7
            feedback_parts.append("Max Stat: OK")
        else:
            feedback_parts.append("Max Stat: Missing/Incorrect")

        if b55.startswith('=') and 'MIN' in b55 and 'F' in b55:
            score += 7
            feedback_parts.append("Min Stat: OK")
        else:
            feedback_parts.append("Min Stat: Missing/Incorrect")

        if b56.startswith('=') and 'COUNTIF' in b56 and '60' in b56:
            score += 8
            feedback_parts.append("Passing Stat: OK")
        else:
            feedback_parts.append("Passing Stat: Missing/Incorrect")

        # Minimum passing condition: Needs to be doing formulas for both arrays
        passed = score >= 70 and f_formulas > 0 and g_formulas > 0

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification encountered an error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)