#!/usr/bin/env python3
"""
Verifier for Trade Apprentice Logbook task

Verifies:
1. Data completion (3 incomplete cells filled correctly)
2. Formula correctness and results
3. Conditional formatting (bonus)
4. Professional formatting
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_apprentice_logbook(traj, env_info, task_info):
    """
    Verify the trade apprentice logbook spreadsheet.
    
    Scoring breakdown:
    - Data completion: 30 points (10 points each for 3 cells)
    - Core formulas (B18-B21): 40 points (10 points each)
    - Progress formula (B22): 10 points
    - Work type formulas (E18-E21): 10 points (partial credit possible)
    - Title and ID: 10 points
    - Bonus: Conditional formatting (not required for passing)
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/apprentice_hours_draft.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_apprentice_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        ws = wb.active
        score = 0
        max_score = 100
        feedback_parts = []

        # ===================================================================
        # PART 1: Data Completion (30 points total)
        # ===================================================================
        
        # Check D5 - should be "Commercial" (case-insensitive)
        d5_value = ws['D5'].value
        if d5_value and isinstance(d5_value, str) and 'commercial' in d5_value.lower():
            score += 10
            feedback_parts.append(f"✅ D5 work type correct: '{d5_value}'")
        else:
            feedback_parts.append(f"❌ D5 work type missing/incorrect: '{d5_value}' (expected 'Commercial')")

        # Check C9 - should be "Independent" (case-insensitive)
        c9_value = ws['C9'].value
        if c9_value and isinstance(c9_value, str) and 'independent' in c9_value.lower():
            score += 10
            feedback_parts.append(f"✅ C9 supervision correct: '{c9_value}'")
        else:
            feedback_parts.append(f"❌ C9 supervision missing/incorrect: '{c9_value}' (expected 'Independent')")

        # Check B13 - should be 9.5 (±0.5 tolerance)
        b13_value = ws['B13'].value
        if b13_value is not None and isinstance(b13_value, (int, float)):
            if abs(float(b13_value) - 9.5) <= 0.5:
                score += 10
                feedback_parts.append(f"✅ B13 hours correct: {b13_value}")
            else:
                feedback_parts.append(f"❌ B13 hours incorrect: {b13_value} (expected 9.5)")
        else:
            feedback_parts.append(f"❌ B13 hours missing: '{b13_value}'")

        # ===================================================================
        # PART 2: Core Formulas and Results (50 points total)
        # ===================================================================
        
        # Expected values (based on completed data)
        # Supervised: 35+28.5+37+30.5+24+40+26+29+33+31.5+9.5+29+24.5 = 377.5
        # Independent: 25+28 = 53
        # Total: 430.5
        # Remaining: 7569.5
        # Progress: 5.38%
        
        # B18: Total Supervised Hours
        b18_value = ws['B18'].value
        b18_has_formula = ws['B18'].data_type == 'f'
        
        if b18_value is not None and isinstance(b18_value, (int, float)):
            if 365 <= float(b18_value) <= 395:  # Allow ±13 from expected 378
                points_earned = 10
                if b18_has_formula:
                    score += points_earned
                    feedback_parts.append(f"✅ B18 supervised hours formula result correct: {b18_value:.1f}")
                else:
                    score += points_earned // 2  # Half credit for correct value without formula
                    feedback_parts.append(f"⚠️ B18 correct value but missing formula: {b18_value:.1f}")
            else:
                feedback_parts.append(f"❌ B18 supervised hours incorrect: {b18_value:.1f} (expected ~378)")
        else:
            feedback_parts.append(f"❌ B18 supervised hours missing or invalid: '{b18_value}'")

        # B19: Total Independent Hours
        b19_value = ws['B19'].value
        b19_has_formula = ws['B19'].data_type == 'f'
        
        if b19_value is not None and isinstance(b19_value, (int, float)):
            if 43 <= float(b19_value) <= 63:  # Allow ±10 from expected 53
                points_earned = 10
                if b19_has_formula:
                    score += points_earned
                    feedback_parts.append(f"✅ B19 independent hours formula result correct: {b19_value:.1f}")
                else:
                    score += points_earned // 2
                    feedback_parts.append(f"⚠️ B19 correct value but missing formula: {b19_value:.1f}")
            else:
                feedback_parts.append(f"❌ B19 independent hours incorrect: {b19_value:.1f} (expected ~53)")
        else:
            feedback_parts.append(f"❌ B19 independent hours missing or invalid: '{b19_value}'")

        # B20: Grand Total
        b20_value = ws['B20'].value
        b20_has_formula = ws['B20'].data_type == 'f'
        
        if b20_value is not None and isinstance(b20_value, (int, float)):
            if 410 <= float(b20_value) <= 450:  # Allow ±20 from expected 431
                points_earned = 10
                if b20_has_formula:
                    score += points_earned
                    feedback_parts.append(f"✅ B20 grand total formula correct: {b20_value:.1f}")
                else:
                    score += points_earned // 2
                    feedback_parts.append(f"⚠️ B20 correct value but missing formula: {b20_value:.1f}")
            else:
                feedback_parts.append(f"❌ B20 grand total incorrect: {b20_value:.1f} (expected ~431)")
        else:
            feedback_parts.append(f"❌ B20 grand total missing or invalid: '{b20_value}'")

        # B21: Hours Remaining to 8000
        b21_value = ws['B21'].value
        b21_has_formula = ws['B21'].data_type == 'f'
        
        if b21_value is not None and isinstance(b21_value, (int, float)):
            if 7550 <= float(b21_value) <= 7590:  # Allow ±20 from expected 7569
                points_earned = 10
                if b21_has_formula:
                    score += points_earned
                    feedback_parts.append(f"✅ B21 hours remaining formula correct: {b21_value:.1f}")
                else:
                    score += points_earned // 2
                    feedback_parts.append(f"⚠️ B21 correct value but missing formula: {b21_value:.1f}")
            else:
                feedback_parts.append(f"❌ B21 hours remaining incorrect: {b21_value:.1f} (expected ~7569)")
        else:
            feedback_parts.append(f"❌ B21 hours remaining missing or invalid: '{b21_value}'")

        # B22: Progress Percentage
        b22_value = ws['B22'].value
        b22_has_formula = ws['B22'].data_type == 'f'
        
        if b22_value is not None:
            # Handle both percentage format (0.054) and regular format (5.4)
            if isinstance(b22_value, (int, float)):
                progress_val = float(b22_value)
                # Check if it's in percentage format (0.054) or regular (5.4)
                if 0.048 <= progress_val <= 0.060:  # Percentage format (4.8% to 6%)
                    if b22_has_formula:
                        score += 10
                        feedback_parts.append(f"✅ B22 progress % formula correct: {progress_val*100:.1f}%")
                    else:
                        score += 5
                        feedback_parts.append(f"⚠️ B22 correct value but missing formula: {progress_val*100:.1f}%")
                elif 4.8 <= progress_val <= 6.0:  # Regular format
                    if b22_has_formula:
                        score += 10
                        feedback_parts.append(f"✅ B22 progress % formula correct: {progress_val:.1f}%")
                    else:
                        score += 5
                        feedback_parts.append(f"⚠️ B22 correct value but missing formula: {progress_val:.1f}%")
                else:
                    feedback_parts.append(f"❌ B22 progress % incorrect: {progress_val} (expected ~5.4%)")
            else:
                feedback_parts.append(f"❌ B22 progress % invalid type: '{b22_value}'")
        else:
            feedback_parts.append(f"❌ B22 progress % missing")

        # ===================================================================
        # PART 3: Work Type Breakdown Formulas (10 points total)
        # ===================================================================
        
        work_type_checks = [
            ('E18', 'Residential', 90, 130),  # Expected ~115
            ('E19', 'Commercial', 130, 170),  # Expected ~152
            ('E20', 'Industrial', 50, 70),    # Expected ~56
            ('E21', 'Service/Repair', 90, 110), # Expected ~104
        ]
        
        work_type_correct = 0
        for cell_ref, work_type, min_val, max_val in work_type_checks:
            cell_value = ws[cell_ref].value
            if cell_value is not None and isinstance(cell_value, (int, float)):
                if min_val <= float(cell_value) <= max_val:
                    work_type_correct += 1
        
        # Award partial credit: 2.5 points per correct work type
        work_type_score = int((work_type_correct / 4) * 10)
        score += work_type_score
        feedback_parts.append(f"{'✅' if work_type_correct >= 3 else '⚠️'} Work type breakdowns: {work_type_correct}/4 correct")

        # ===================================================================
        # PART 4: Professional Formatting (10 points total)
        # ===================================================================
        
        # Check for title containing "Apprenticeship" and a year
        title_found = False
        year_found = False
        for row in ws.iter_rows(min_row=1, max_row=3):  # Check first 3 rows
            for cell in row:
                if cell.value and isinstance(cell.value, str):
                    cell_text = cell.value.lower()
                    if 'apprenticeship' in cell_text:
                        title_found = True
                    if re.search(r'20\d{2}', cell.value):  # Match years like 2024
                        year_found = True
        
        if title_found and year_found:
            score += 5
            feedback_parts.append("✅ Title row with 'Apprenticeship' and year found")
        elif title_found:
            score += 3
            feedback_parts.append("⚠️ Title with 'Apprenticeship' found but missing year")
        else:
            feedback_parts.append("❌ Title row missing or incomplete")

        # Check for apprentice ID "EA-2847-TX"
        id_found = False
        for row in ws.iter_rows():
            for cell in row:
                if cell.value and isinstance(cell.value, str):
                    if 'EA-2847-TX' in cell.value or 'ea-2847-tx' in cell.value.lower():
                        id_found = True
                        break
            if id_found:
                break
        
        if id_found:
            score += 5
            feedback_parts.append("✅ Apprentice ID 'EA-2847-TX' found")
        else:
            feedback_parts.append("❌ Apprentice ID 'EA-2847-TX' not found")

        # ===================================================================
        # BONUS: Conditional Formatting (not required for passing)
        # ===================================================================
        
        # Check if conditional formatting rules exist
        # This is tricky in openpyxl, so we'll just check if they tried
        if ws.conditional_formatting:
            try:
                # Check if B19 or B22 have conditional formatting
                has_b19_cf = any('B19' in str(cf.sqref) for cf in ws.conditional_formatting._cf_rules.values())
                has_b22_cf = any('B22' in str(cf.sqref) for cf in ws.conditional_formatting._cf_rules.values())
                
                if has_b19_cf or has_b22_cf:
                    bonus_points = 5
                    score = min(100, score + bonus_points)  # Cap at 100
                    feedback_parts.append(f"🌟 BONUS: Conditional formatting detected (+{bonus_points} points)")
            except:
                pass  # Conditional formatting check failed, skip bonus

        # ===================================================================
        # Final Result
        # ===================================================================
        
        passed = score >= 70
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
