#!/usr/bin/env python3
"""
Verifier for Mystery Shop Report task
"""

import sys
import os
import logging
import tempfile
from typing import Dict, Any, Optional, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_mystery_shop_report(traj, env_info, task_info):
    """
    Verify that mystery shop evaluation report was completed correctly.

    Checks:
    1. Data Entry Accuracy (25 points): All 17 scores entered correctly
    2. Section Average Formulas (30 points): 5 AVERAGE formulas with correct results
    3. Weighted Average Formula (25 points): Overall score calculated correctly
    4. Percentage Calculation (10 points): Percentage formula correct
    5. Bonus Eligibility Formula (10 points): IF formula displays correct result
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/mystery_shop_riverside_diner.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_mystery_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        feedback_parts = []
        total_score = 0
        
        sheet_name = "Evaluation Report"
        
        # Expected scores mapping (row number: expected value)
        expected_scores = {
            8: 4, 9: 5, 10: 4,              # Greeting & Seating
            15: 5, 16: 3, 17: 5, 18: 4, 19: 5,  # Service Quality
            24: 4, 25: 5, 26: 5, 27: 4,     # Food Quality
            32: 3, 33: 4, 34: 4,            # Cleanliness
            39: 5, 40: 5                    # Payment & Departure
        }
        
        # ===================================================================
        # CRITERION 1: Data Entry Accuracy (25 points)
        # ===================================================================
        correct_entries = 0
        total_entries = len(expected_scores)
        
        for row_num, expected_val in expected_scores.items():
            cell_ref = f'B{row_num}'
            actual_val = get_cell_value(wb, sheet_name, cell_ref)
            
            if actual_val is not None and isinstance(actual_val, (int, float)):
                if int(actual_val) == expected_val:
                    correct_entries += 1
        
        data_score = int((correct_entries / total_entries) * 25)
        total_score += data_score
        
        if correct_entries == total_entries:
            feedback_parts.append(f"✅ Data Entry: All {total_entries} scores correct (25/25)")
        elif correct_entries >= total_entries * 0.8:
            feedback_parts.append(f"⚠️ Data Entry: {correct_entries}/{total_entries} scores correct ({data_score}/25)")
        else:
            feedback_parts.append(f"❌ Data Entry: Only {correct_entries}/{total_entries} scores correct ({data_score}/25)")
        
        # ===================================================================
        # CRITERION 2: Section Average Formulas (30 points, 6 each)
        # ===================================================================
        section_checks = [
            ('B11', 4.33, 'Greeting', 8, 10),
            ('B20', 4.40, 'Service', 15, 19),
            ('B28', 4.50, 'Food', 24, 27),
            ('B35', 3.67, 'Cleanliness', 32, 34),
            ('B41', 5.00, 'Payment', 39, 40)
        ]
        
        section_score = 0
        sections_correct = 0
        
        for cell_ref, expected_avg, section_name, start_row, end_row in section_checks:
            cell_val = get_cell_value(wb, sheet_name, cell_ref)
            
            if cell_val is not None and isinstance(cell_val, (int, float)):
                # Allow small tolerance for rounding differences
                if abs(float(cell_val) - expected_avg) <= 0.05:
                    section_score += 6
                    sections_correct += 1
                elif abs(float(cell_val) - expected_avg) <= 0.15:
                    # Partial credit if close but not exact
                    section_score += 3
        
        total_score += section_score
        
        if sections_correct == 5:
            feedback_parts.append(f"✅ Section Averages: All 5 correct (30/30)")
        elif sections_correct >= 3:
            feedback_parts.append(f"⚠️ Section Averages: {sections_correct}/5 correct ({section_score}/30)")
        else:
            feedback_parts.append(f"❌ Section Averages: Only {sections_correct}/5 correct ({section_score}/30)")
        
        # ===================================================================
        # CRITERION 3: Weighted Overall Score (25 points)
        # ===================================================================
        # Expected: 4.33*0.15 + 4.40*0.35 + 4.50*0.25 + 3.67*0.15 + 5.00*0.10
        # = 0.6495 + 1.54 + 1.125 + 0.5505 + 0.5 = 4.365
        expected_overall = 4.365
        overall_cell_val = get_cell_value(wb, sheet_name, 'B44')
        
        weighted_score = 0
        if overall_cell_val is not None and isinstance(overall_cell_val, (int, float)):
            if abs(float(overall_cell_val) - expected_overall) <= 0.05:
                weighted_score = 25
                feedback_parts.append(f"✅ Overall Score: {overall_cell_val:.2f} correct (25/25)")
            elif abs(float(overall_cell_val) - expected_overall) <= 0.15:
                weighted_score = 15
                feedback_parts.append(f"⚠️ Overall Score: {overall_cell_val:.2f} close to expected {expected_overall:.2f} (15/25)")
            else:
                feedback_parts.append(f"❌ Overall Score: {overall_cell_val:.2f} incorrect, expected ~{expected_overall:.2f} (0/25)")
        else:
            feedback_parts.append(f"❌ Overall Score: Missing or invalid (0/25)")
        
        total_score += weighted_score
        
        # ===================================================================
        # CRITERION 4: Percentage Calculation (10 points)
        # ===================================================================
        # Expected: 4.365 / 5 * 100 = 87.3%
        expected_pct = 87.3
        pct_cell_val = get_cell_value(wb, sheet_name, 'B45')
        
        pct_score = 0
        if pct_cell_val is not None and isinstance(pct_cell_val, (int, float)):
            if abs(float(pct_cell_val) - expected_pct) <= 1.0:
                pct_score = 10
                feedback_parts.append(f"✅ Percentage: {pct_cell_val:.1f}% correct (10/10)")
            elif abs(float(pct_cell_val) - expected_pct) <= 3.0:
                pct_score = 5
                feedback_parts.append(f"⚠️ Percentage: {pct_cell_val:.1f}% close (5/10)")
            else:
                feedback_parts.append(f"❌ Percentage: {pct_cell_val:.1f}% incorrect, expected ~{expected_pct:.1f}% (0/10)")
        else:
            feedback_parts.append(f"❌ Percentage: Missing or invalid (0/10)")
        
        total_score += pct_score
        
        # ===================================================================
        # CRITERION 5: Bonus Eligibility IF Formula (10 points)
        # ===================================================================
        bonus_cell_val = get_cell_value(wb, sheet_name, 'B46')
        
        bonus_score = 0
        if bonus_cell_val is not None:
            bonus_str = str(bonus_cell_val).strip().upper()
            # Expected result is "YES" since percentage should be ~87.3%
            if bonus_str == "YES":
                bonus_score = 10
                feedback_parts.append(f"✅ Bonus Eligible: YES correct (10/10)")
            elif bonus_str == "NO":
                # This would be wrong given the correct calculations
                feedback_parts.append(f"❌ Bonus Eligible: Shows NO, should be YES (0/10)")
            else:
                feedback_parts.append(f"❌ Bonus Eligible: Invalid value '{bonus_cell_val}' (0/10)")
        else:
            feedback_parts.append(f"❌ Bonus Eligible: Missing (0/10)")
        
        total_score += bonus_score
        
        # ===================================================================
        # Final Assessment
        # ===================================================================
        passed = total_score >= 85
        
        # Add summary at the beginning
        summary = f"Total Score: {total_score}/100 - {'PASSED ✅' if passed else 'FAILED ❌'}"
        feedback_parts.insert(0, summary)
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: Score={total_score}, Passed={passed}")
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
