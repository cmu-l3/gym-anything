#!/usr/bin/env python3
"""
Verifier for Sleep Optimization Experiment task

Verifies:
1. File exists with correct name
2. Two sheets exist: "Raw_Data" and "Analysis"
3. Raw_Data has 14 rows of night data
4. Key data points are accurate (Night 3, Night 9, Night 11)
5. Analysis sheet has formulas (not hardcoded values)
6. Strategy C average is correctly calculated (~8.0-8.5)
7. Best strategy identified correctly (Strategy C)
8. Conditional formatting applied
9. Headers are bold
10. Best strategy cell is highlighted
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_has_formula(sheet, cell_ref):
    """Check if a cell contains a formula (not just a value)"""
    try:
        cell = sheet[cell_ref]
        # In openpyxl, formulas are stored in cell.value as strings starting with '='
        # But when data_only=True, we get calculated values
        # We need to check the cell's data_type or value
        if hasattr(cell, 'data_type') and cell.data_type == 'f':
            return True
        # Alternative: check if value is a string starting with '='
        if isinstance(cell.value, str) and cell.value.startswith('='):
            return True
        return False
    except:
        return False


def check_bold_formatting(sheet, cell_ref):
    """Check if a cell has bold formatting"""
    try:
        cell = sheet[cell_ref]
        if cell.font and cell.font.bold:
            return True
        return False
    except:
        return False


def check_cell_fill_color(sheet, cell_ref):
    """Check if a cell has background fill color"""
    try:
        cell = sheet[cell_ref]
        if cell.fill and cell.fill.fgColor and cell.fill.fgColor.rgb:
            color = cell.fill.fgColor.rgb
            # Return the color code (or True if any color exists)
            return color
        return None
    except:
        return None


def check_conditional_formatting_exists(sheet):
    """Check if conditional formatting rules exist on the sheet"""
    try:
        if hasattr(sheet, 'conditional_formatting') and sheet.conditional_formatting:
            return len(sheet.conditional_formatting) > 0
        return False
    except:
        return False


def verify_sleep_experiment(traj, env_info, task_info):
    """
    Verify that sleep experiment analysis was completed correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/sleep_analysis_complete.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_sleep_')

    try:
        # First, try to load with data_only=True to get calculated values
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx', dir=temp_dir)
        temp_path = temp_file.name
        temp_file.close()

        # Copy file from container
        copy_from_env(container_path, temp_path)

        if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ File not found or empty: {container_path}"
            }

        # Parse with data_only=True to get calculated values
        wb = parse_xlsx_file(temp_path)
        if wb is None:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Failed to parse XLSX file - file may be corrupted"
            }

        criteria_passed = 0
        total_criteria = 11
        feedback_parts = []

        # ===== CRITICAL CRITERIA (Must pass all) =====

        # Criterion 1: Check if both sheets exist
        if "Raw_Data" not in wb.sheetnames:
            feedback_parts.append("❌ CRITICAL: Missing 'Raw_Data' sheet")
            return {
                "passed": False,
                "score": 0.0,
                "feedback": " | ".join(feedback_parts)
            }

        if "Analysis" not in wb.sheetnames:
            feedback_parts.append("❌ CRITICAL: Missing 'Analysis' sheet")
            return {
                "passed": False,
                "score": 0.0,
                "feedback": " | ".join(feedback_parts)
            }

        criteria_passed += 1
        feedback_parts.append("✅ Both required sheets present (Raw_Data, Analysis)")

        raw_sheet = wb["Raw_Data"]
        analysis_sheet = wb["Analysis"]

        # Criterion 2: Check Raw_Data has approximately 14 rows of data
        # Count non-empty rows (excluding header)
        data_rows = 0
        for row_idx in range(2, 20):  # Check up to row 20
            # Check if any cell in the row has data
            has_data = False
            for col_idx in range(1, 10):  # Check first 9 columns
                cell_value = raw_sheet.cell(row=row_idx, column=col_idx).value
                if cell_value is not None and str(cell_value).strip() != '':
                    has_data = True
                    break
            if has_data:
                data_rows += 1

        if data_rows >= 13:  # At least 13 rows (14 nights, some might have merged or missing Night 13)
            criteria_passed += 1
            feedback_parts.append(f"✅ Raw_Data has {data_rows} data rows (expected ~14)")
        else:
            feedback_parts.append(f"❌ Raw_Data has only {data_rows} data rows (expected ~14)")

        # Criterion 3: Check Night 3 data accuracy (Strategy C only, quality 8)
        # We need to find the row with Night 3 - could be row 4 if row 1 is header
        night_3_quality = None
        night_3_found = False

        # Search for Night 3 in column A (or wherever night number is)
        for row_idx in range(2, 20):
            night_cell = raw_sheet.cell(row=row_idx, column=1).value
            if night_cell is not None and (str(night_cell) == '3' or 'night 3' in str(night_cell).lower()):
                # Found Night 3, now find sleep quality column
                # Sleep quality is likely in one of the later columns
                for col_idx in range(1, 12):
                    val = raw_sheet.cell(row=row_idx, column=col_idx).value
                    if val is not None and isinstance(val, (int, float)) and 1 <= val <= 10:
                        # This could be sleep quality
                        if abs(val - 8) <= 1:  # Should be 8
                            night_3_quality = val
                            night_3_found = True
                            break
                break

        if night_3_found and night_3_quality is not None and abs(night_3_quality - 8) <= 1:
            criteria_passed += 1
            feedback_parts.append(f"✅ Night 3 sleep quality correct: {night_3_quality}")
        else:
            feedback_parts.append(f"❌ Night 3 sleep quality incorrect or missing (expected 8)")

        # Criterion 4: Check Night 9 data accuracy (control, quality 4 - worst night)
        night_9_quality = None
        night_9_found = False

        for row_idx in range(2, 20):
            night_cell = raw_sheet.cell(row=row_idx, column=1).value
            if night_cell is not None and (str(night_cell) == '9' or 'night 9' in str(night_cell).lower()):
                for col_idx in range(1, 12):
                    val = raw_sheet.cell(row=row_idx, column=col_idx).value
                    if val is not None and isinstance(val, (int, float)) and 1 <= val <= 10:
                        if abs(val - 4) <= 1:  # Should be 4
                            night_9_quality = val
                            night_9_found = True
                            break
                break

        if night_9_found and night_9_quality is not None and abs(night_9_quality - 4) <= 1:
            criteria_passed += 1
            feedback_parts.append(f"✅ Night 9 sleep quality correct: {night_9_quality} (worst night)")
        else:
            feedback_parts.append(f"❌ Night 9 sleep quality incorrect or missing (expected 4)")

        # Criterion 5: Check Night 11 data accuracy (Strategy C only, quality 9)
        night_11_quality = None
        night_11_found = False

        for row_idx in range(2, 20):
            night_cell = raw_sheet.cell(row=row_idx, column=1).value
            if night_cell is not None and (str(night_cell) == '11' or 'night 11' in str(night_cell).lower()):
                for col_idx in range(1, 12):
                    val = raw_sheet.cell(row=row_idx, column=col_idx).value
                    if val is not None and isinstance(val, (int, float)) and 1 <= val <= 10:
                        if abs(val - 9) <= 1:  # Should be 9
                            night_11_quality = val
                            night_11_found = True
                            break
                break

        if night_11_found and night_11_quality is not None and abs(night_11_quality - 9) <= 1:
            criteria_passed += 1
            feedback_parts.append(f"✅ Night 11 sleep quality correct: {night_11_quality}")
        else:
            feedback_parts.append(f"❌ Night 11 sleep quality incorrect or missing (expected 9)")

        # Criterion 6 & 7: Check Analysis sheet has formulas and Strategy C average
        # Strategy C average should be: (8+9+7+8+9+8)/6 = 8.167
        # Look for cells in Analysis sheet that might contain this

        strategy_c_avg = None
        has_formula_in_analysis = False

        # Search Analysis sheet for average values and formulas
        for row_idx in range(1, 30):
            for col_idx in range(1, 10):
                cell = analysis_sheet.cell(row=row_idx, column=col_idx)
                cell_val = cell.value

                # Check if this cell has a formula
                if cell.data_type == 'f' or (isinstance(cell_val, str) and cell_val.startswith('=')):
                    has_formula_in_analysis = True

                # Check if this cell contains Strategy C average (around 8.0-8.5)
                if isinstance(cell_val, (int, float)) and 7.5 <= cell_val <= 8.5:
                    # This could be Strategy C average
                    # Check if "C" or "Strategy C" is nearby
                    for check_col in range(max(1, col_idx-3), min(10, col_idx+3)):
                        check_val = analysis_sheet.cell(row=row_idx, column=check_col).value
                        if check_val is not None and ('c' in str(check_val).lower() or 'strategy c' in str(check_val).lower()):
                            strategy_c_avg = cell_val
                            break

        if has_formula_in_analysis:
            criteria_passed += 1
            feedback_parts.append("✅ Analysis sheet contains formulas (not hardcoded)")
        else:
            feedback_parts.append("❌ Analysis sheet missing formulas - values appear hardcoded")

        if strategy_c_avg is not None and 7.5 <= strategy_c_avg <= 8.5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Strategy C average correctly calculated: {strategy_c_avg:.2f} (expected ~8.17)")
        else:
            feedback_parts.append(f"❌ Strategy C average incorrect or missing (expected ~8.17)")

        # Criterion 8: Check if best strategy is identified correctly (should be C)
        best_strategy_found = False

        for row_idx in range(1, 30):
            for col_idx in range(1, 10):
                cell_val = analysis_sheet.cell(row=row_idx, column=col_idx).value
                if cell_val is not None and isinstance(cell_val, str):
                    cell_text = str(cell_val).lower()
                    if 'best' in cell_text and 'strategy' in cell_text:
                        # Found label, check nearby cells for "C"
                        for check_col in range(col_idx, min(10, col_idx+5)):
                            check_val = analysis_sheet.cell(row=row_idx, column=check_col).value
                            if check_val is not None and 'c' in str(check_val).lower():
                                best_strategy_found = True
                                break
                        # Also check next row
                        for check_col in range(1, 10):
                            check_val = analysis_sheet.cell(row=row_idx+1, column=check_col).value
                            if check_val is not None and str(check_val).upper() == 'C':
                                best_strategy_found = True
                                break

        if best_strategy_found:
            criteria_passed += 1
            feedback_parts.append("✅ Best strategy correctly identified as C")
        else:
            feedback_parts.append("❌ Best strategy not identified or incorrect")

        # ===== FORMATTING CRITERIA (At least 2 of 3 required) =====

        formatting_passed = 0

        # Criterion 9: Check conditional formatting exists
        if check_conditional_formatting_exists(raw_sheet):
            formatting_passed += 1
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting applied to Raw_Data sheet")
        else:
            # Check manually if high quality cells are green and low quality are red
            green_found = False
            red_found = False

            for row_idx in range(2, 20):
                for col_idx in range(1, 12):
                    cell = raw_sheet.cell(row=row_idx, column=col_idx)
                    val = cell.value
                    fill_color = check_cell_fill_color(raw_sheet, cell.coordinate)

                    if isinstance(val, (int, float)) and 1 <= val <= 10:
                        if val >= 8 and fill_color and 'FF00' in str(fill_color):
                            green_found = True
                        if val <= 5 and fill_color and 'FF0000' in str(fill_color):
                            red_found = True

            if green_found or red_found:
                formatting_passed += 1
                criteria_passed += 1
                feedback_parts.append("⭐ Partial conditional formatting detected (green/red colors)")
            else:
                feedback_parts.append("❌ Conditional formatting not applied")

        # Criterion 10: Check if headers are bold
        bold_headers_found = False
        for col_idx in range(1, 10):
            if check_bold_formatting(raw_sheet, raw_sheet.cell(row=1, column=col_idx).coordinate):
                bold_headers_found = True
                break

        if bold_headers_found:
            formatting_passed += 1
            criteria_passed += 1
            feedback_parts.append("⭐ Headers are bold in Raw_Data sheet")
        else:
            feedback_parts.append("❌ Headers are not bold")

        # Criterion 11: Check if best strategy cell is highlighted
        best_cell_highlighted = False

        for row_idx in range(1, 30):
            for col_idx in range(1, 10):
                cell = analysis_sheet.cell(row=row_idx, column=col_idx)
                fill_color = check_cell_fill_color(analysis_sheet, cell.coordinate)

                if fill_color and len(str(fill_color)) >= 6:
                    # Check if it's yellowish (FF + FFFF or similar)
                    if 'FFFF' in str(fill_color) or 'FFF' in str(fill_color):
                        # Check if this cell or nearby cells contain "C" or "best"
                        cell_val = cell.value
                        if cell_val is not None and ('c' in str(cell_val).lower() or 'best' in str(cell_val).lower()):
                            best_cell_highlighted = True
                            break

        if best_cell_highlighted:
            formatting_passed += 1
            criteria_passed += 1
            feedback_parts.append("⭐ Best strategy cell highlighted with color")
        else:
            feedback_parts.append("❌ Best strategy cell not highlighted")

        # ===== SCORING =====

        # Must pass: 8 critical requirements (1-8)
        # Plus at least 2 formatting requirements (9-11)

        critical_passed = min(criteria_passed, 8)  # First 8 are critical
        formatting_criteria = max(0, criteria_passed - 8)  # Next 3 are formatting

        if critical_passed >= 6 and formatting_criteria >= 2:
            passed = True
            score = criteria_passed / total_criteria
        elif critical_passed >= 6:
            passed = False
            score = 0.7
            feedback_parts.append("⚠️ Partial credit: Critical requirements met but formatting incomplete")
        else:
            passed = False
            score = criteria_passed / total_criteria

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)