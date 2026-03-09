#!/usr/bin/env python3
"""
Verifier for Chronic Symptom Detective task

This verifier checks that a messy migraine tracking spreadsheet
has been organized into a structured symptom log with proper
analysis formulas.
"""

import sys
import os
import logging
import tempfile
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_chronic_symptom_detective(traj, env_info, task_info):
    """
    Verify the migraine trigger analysis spreadsheet task.
    
    Checks:
    1. Structured symptom log sheet exists
    2. Has required columns (Date, Migraine, Severity, Sleep, Caffeine, Stress, Screen Time)
    3. Has at least 15 rows of cleaned data
    4. Dates are properly formatted (not text like "March 3rd")
    5. Has formulas for analysis (COUNT, AVERAGE, etc.)
    6. Has conditional formulas (COUNTIF, AVERAGEIF)
    7. Data values are reasonable (no absurd numbers)
    8. Headers appear formatted (bold)
    9. Data has been transferred from raw notes
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/migraine_notes_raw.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_symptom_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Could not open spreadsheet: {error}"
            }

        feedback_parts = []
        score = 0
        max_score = 100

        # Check for symptom log sheet (Sheet2 or similar)
        sheet_names = wb.sheetnames
        logger.info(f"Found sheets: {sheet_names}")
        
        symptom_sheet = None
        
        # Look for a sheet that's NOT the raw notes
        for name in sheet_names:
            if name.lower() not in ['raw notes', 'sheet1']:
                if any(keyword in name.lower() for keyword in ['symptom', 'log', 'tracking', 'organized', 'clean', 'sheet2', 'analysis']):
                    symptom_sheet = name
                    break
        
        # If no explicitly named sheet, try Sheet2 or any second sheet
        if not symptom_sheet:
            if len(sheet_names) >= 2:
                symptom_sheet = sheet_names[1]
            else:
                # Maybe they organized it in the same sheet
                symptom_sheet = sheet_names[0] if sheet_names else None

        if not symptom_sheet:
            feedback_parts.append("❌ No symptom log sheet found (expected new sheet like 'Symptom Log')")
            return {
                "passed": False,
                "score": 0.0,
                "feedback": " | ".join(feedback_parts)
            }

        score += 10
        feedback_parts.append(f"✅ Found symptom log sheet: '{symptom_sheet}'")

        # Get sheet data
        sheet = wb[symptom_sheet]
        data = get_sheet_data(wb, symptom_sheet, max_rows=100, max_cols=20)

        if not data or len(data) < 2:
            feedback_parts.append("❌ Sheet is empty or has no data rows")
            return {
                "passed": False,
                "score": score / max_score,
                "feedback": " | ".join(feedback_parts)
            }

        # Check for required columns in header row
        header_row = [str(cell).lower().strip() if cell else "" for cell in data[0]]
        logger.info(f"Header row: {header_row}")

        required_columns = ['date', 'migraine', 'severity', 'sleep', 'caffeine', 'stress', 'screen']
        found_columns = []
        column_indices = {}

        for req_col in required_columns:
            for idx, h in enumerate(header_row):
                if req_col in h and req_col not in found_columns:
                    found_columns.append(req_col)
                    column_indices[req_col] = idx
                    break

        if len(found_columns) >= 6:  # At least 6 of 7 required columns
            score += 10
            feedback_parts.append(f"✅ Found required columns ({len(found_columns)}/7: {', '.join(found_columns)})")
        else:
            feedback_parts.append(f"❌ Missing required columns (found {len(found_columns)}/7)")
            logger.warning(f"Found columns: {found_columns}")

        # Check for data entries (at least 15 rows with dates)
        date_col_idx = column_indices.get('date')
        valid_data_rows = 0
        date_values = set()

        if date_col_idx is not None:
            for row_idx, row in enumerate(data[1:], start=2):  # Skip header
                if len(row) > date_col_idx and row[date_col_idx]:
                    date_val = row[date_col_idx]
                    # Check if it's not empty
                    if date_val and str(date_val).strip() and str(date_val).strip().lower() not in ['none', 'null', '']:
                        valid_data_rows += 1
                        date_values.add(str(date_val))

        logger.info(f"Valid data rows: {valid_data_rows}")

        if valid_data_rows >= 15:
            score += 10
            feedback_parts.append(f"✅ Has {valid_data_rows} data entries (≥15 required)")
        elif valid_data_rows >= 10:
            score += 5
            feedback_parts.append(f"⚠️ Has {valid_data_rows} data entries (need ≥15 for full credit)")
        else:
            feedback_parts.append(f"❌ Only {valid_data_rows} data entries (need ≥15)")

        # Check for proper date formatting (dates should NOT contain text like "March" or "th")
        proper_dates = 0
        improper_dates = 0

        if date_col_idx is not None:
            for row_idx, row in enumerate(data[1:25], start=2):  # Check first 24 data rows
                if len(row) > date_col_idx and row[date_col_idx]:
                    date_val = row[date_col_idx]
                    if date_val:
                        date_str = str(date_val).lower().strip()
                        # Check if it contains improper date text
                        if any(text in date_str for text in ['march', 'april', 'may', 'june', 'july', 
                                                               'august', 'september', 'october', 'november', 
                                                               'december', 'january', 'february',
                                                               'th', 'st', 'nd', 'rd']):
                            improper_dates += 1
                        elif date_str and date_str not in ['none', 'null', '']:
                            proper_dates += 1

        logger.info(f"Date formatting: {proper_dates} proper, {improper_dates} improper")

        if proper_dates > improper_dates and proper_dates >= 10:
            score += 10
            feedback_parts.append(f"✅ Dates properly formatted ({proper_dates} clean dates)")
        elif proper_dates >= 5:
            score += 5
            feedback_parts.append(f"⚠️ Some dates properly formatted ({proper_dates} clean, {improper_dates} need fixing)")
        else:
            feedback_parts.append(f"❌ Dates not properly formatted ({improper_dates} text dates found)")

        # Check for formulas (scan entire sheet)
        formula_count = 0
        has_count_formula = False
        has_average_formula = False
        has_conditional_formula = False

        for row in sheet.iter_rows(max_row=150, max_col=30):
            for cell in row:
                if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                    formula_count += 1
                    formula_upper = cell.value.upper()
                    
                    # Check for different formula types
                    if any(func in formula_upper for func in ['COUNTIF', 'COUNT(', 'COUNTA']):
                        has_count_formula = True
                    if any(func in formula_upper for func in ['AVERAGEIF', 'AVERAGE(']):
                        has_average_formula = True
                    if any(func in formula_upper for func in ['COUNTIF', 'SUMIF', 'AVERAGEIF']):
                        has_conditional_formula = True

        logger.info(f"Formulas found: {formula_count} total, count={has_count_formula}, avg={has_average_formula}, conditional={has_conditional_formula}")

        if formula_count >= 3:
            score += 5
            feedback_parts.append(f"✅ Contains formulas ({formula_count} found)")
        else:
            feedback_parts.append(f"⚠️ Few formulas found ({formula_count})")

        if has_count_formula:
            score += 10
            feedback_parts.append("✅ Has counting formula (COUNTIF/COUNT)")
        else:
            feedback_parts.append("❌ No counting formula found")

        if has_average_formula:
            score += 10
            feedback_parts.append("✅ Has average formula")
        else:
            feedback_parts.append("❌ No average formula found")

        if has_conditional_formula:
            score += 10
            feedback_parts.append("✅ Has conditional formula (IF-based)")
        else:
            feedback_parts.append("❌ No conditional formula found")

        # Check for multiple formulas suggesting analysis
        if formula_count >= 5:
            score += 5
            feedback_parts.append("✅ Multiple analysis formulas present")

        # Check data quality (no absurd values)
        has_reasonable_data = True
        absurd_values = []

        for row_idx, row in enumerate(data[1:25], start=2):  # Check first 24 rows
            for col_idx, cell in enumerate(row):
                if cell and isinstance(cell, (int, float)):
                    # Check for absurd values
                    if cell > 5000 or cell < -50:
                        has_reasonable_data = False
                        absurd_values.append((row_idx, col_idx, cell))

        if has_reasonable_data:
            score += 10
            feedback_parts.append("✅ Data values appear reasonable")
        else:
            feedback_parts.append(f"⚠️ Some data values seem incorrect: {absurd_values[:3]}")

        # Check if data was transferred (Sheet1/Raw Notes should still exist)
        if len(sheet_names) >= 2:
            has_raw_sheet = any(name.lower() in ['sheet1', 'raw notes', 'raw'] for name in sheet_names)
            if has_raw_sheet:
                score += 5
                feedback_parts.append("✅ Raw data sheet preserved")

        # Check formatting (bold headers)
        first_row_has_bold = False
        try:
            for cell in sheet[1]:
                if cell.font and cell.font.bold:
                    first_row_has_bold = True
                    break
        except Exception as e:
            logger.warning(f"Could not check font formatting: {e}")

        if first_row_has_bold:
            score += 5
            feedback_parts.append("✅ Headers formatted (bold)")
        else:
            feedback_parts.append("⚠️ Headers may not be formatted")

        # Check alignment (numbers should be right or center aligned)
        numeric_alignment_ok = False
        try:
            sample_count = 0
            for row in sheet.iter_rows(min_row=2, max_row=15, max_col=15):
                for cell in row:
                    if cell.value and isinstance(cell.value, (int, float)):
                        if cell.alignment and cell.alignment.horizontal in ['right', 'center']:
                            numeric_alignment_ok = True
                            break
                        sample_count += 1
                        if sample_count > 10:
                            break
        except Exception as e:
            logger.warning(f"Could not check alignment: {e}")

        if numeric_alignment_ok:
            score += 5
            feedback_parts.append("✅ Numeric data properly aligned")

        # Final assessment
        passed = score >= 60  # Need 60/100 to pass

        logger.info(f"Final score: {score}/{max_score}, passed: {passed}")

        return {
            "passed": passed,
            "score": score / max_score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
