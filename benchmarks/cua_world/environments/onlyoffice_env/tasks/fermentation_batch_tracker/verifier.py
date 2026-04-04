#!/usr/bin/env python3
"""
Verifier for Fermentation Batch Tracker task
"""

import sys
import os
import logging
import tempfile
from datetime import datetime, date, timedelta
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_text(text):
    """Normalize text for comparison (lowercase, strip whitespace)"""
    if text is None:
        return ""
    return str(text).lower().strip()


def check_header_present(headers, expected_keywords):
    """Check if header row contains expected keywords (flexible matching)"""
    normalized_headers = [normalize_text(h) for h in headers]
    for keyword in expected_keywords:
        found = any(keyword.lower() in h for h in normalized_headers)
        if not found:
            return False
    return True


def extract_formula(sheet, cell_ref):
    """Extract formula from a cell using openpyxl"""
    try:
        cell = sheet[cell_ref]
        if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
            return cell.value
        # For data_only=True workbooks, need to check the formula attribute
        if hasattr(cell, 'value') and hasattr(cell, '_value'):
            return getattr(cell, '_value', None)
        return None
    except:
        return None


def has_today_function(formula):
    """Check if formula contains TODAY() or NOW() function"""
    if not formula:
        return False
    formula_upper = formula.upper()
    return 'TODAY()' in formula_upper or 'NOW()' in formula_upper


def has_if_function(formula):
    """Check if formula contains IF function"""
    if not formula:
        return False
    return formula.upper().startswith('=IF(') or '=IF(' in formula.upper()


def parse_date_value(value):
    """Parse date from various formats"""
    if isinstance(value, datetime):
        return value.date()
    elif isinstance(value, date):
        return value
    elif isinstance(value, str):
        # Try various date formats
        for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%d/%m/%Y', '%Y/%m/%d']:
            try:
                return datetime.strptime(value, fmt).date()
            except:
                continue
    return None


def verify_fermentation_tracker(traj, env_info, task_info):
    """
    Verify that fermentation tracking spreadsheet was created correctly.

    Checks:
    1. Structure: All 6 required headers present in row 1
    2. Data: All 4 batch rows present with correct batch names and types
    3. Date Formulas: Column E contains TODAY()-based formulas with correct calculations
    4. Status Formulas: Column F contains IF formulas with correct logic
    5. Accuracy: All 4 batches have correct status (2 ready, 2 fermenting)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/fermentation_tracker.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_fermentation_')

    try:
        # Copy and parse the spreadsheet (need to parse without data_only to see formulas)
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        # Get the active sheet
        if "Fermentation Tracker" in wb.sheetnames:
            sheet_name = "Fermentation Tracker"
        else:
            sheet_name = wb.sheetnames[0]
        
        sheet = wb[sheet_name]

        criteria_scores = []
        feedback_parts = []
        max_score = 100

        # Expected batch data (for reference)
        expected_batches = {
            'batch-k-01': {'type': 'kombucha', 'days_ago': 15, 'target': 12, 'status': 'ready'},
            'batch-m-03': {'type': 'mead', 'days_ago': 45, 'target': 60, 'status': 'fermenting'},
            'batch-k-02': {'type': 'kombucha', 'days_ago': 8, 'target': 12, 'status': 'fermenting'},
            'batch-m-04': {'type': 'mead', 'days_ago': 68, 'target': 60, 'status': 'ready'}
        }

        # === CRITERION 1: Structure - Headers Present (25 points) ===
        headers_row = [get_cell_value(wb, sheet_name, f'{chr(65+i)}1') for i in range(6)]
        required_keywords = ['batch', 'beverage', 'start', 'target', 'elapsed', 'status']
        
        if check_header_present(headers_row, required_keywords):
            criteria_scores.append(25)
            feedback_parts.append("✅ Structure: All 6 required headers present")
        else:
            criteria_scores.append(0)
            feedback_parts.append(f"❌ Structure: Missing required headers. Found: {headers_row[:6]}")

        # === CRITERION 2: Data Completeness (15 points) ===
        batch_names_found = []
        for row_num in range(2, 6):  # Rows 2-5
            batch_name = get_cell_value(wb, sheet_name, f'A{row_num}')
            if batch_name:
                batch_names_found.append(normalize_text(batch_name))
        
        expected_batch_names = ['batch-k-01', 'batch-m-03', 'batch-k-02', 'batch-m-04']
        batches_correct = sum(1 for name in expected_batch_names if name in batch_names_found)
        
        if batches_correct >= 4:
            criteria_scores.append(15)
            feedback_parts.append(f"✅ Data: All 4 batches present")
        elif batches_correct >= 3:
            criteria_scores.append(10)
            feedback_parts.append(f"⚠️ Data: {batches_correct}/4 batches found")
        else:
            criteria_scores.append(0)
            feedback_parts.append(f"❌ Data: Only {batches_correct}/4 batches found")

        # === CRITERION 3: Days Elapsed Formulas (30 points) ===
        days_elapsed_formula_count = 0
        days_elapsed_correct_count = 0
        
        for row_num in range(2, 6):  # Rows 2-5
            # Check if formula exists
            cell_ref = f'E{row_num}'
            cell = sheet[cell_ref]
            
            # Try to get the formula
            has_formula = False
            if hasattr(cell, 'value') and isinstance(cell.value, str) and cell.value.startswith('='):
                formula = cell.value
                has_formula = True
            
            if has_formula and has_today_function(formula):
                days_elapsed_formula_count += 1
                
                # Check if the calculated value is approximately correct
                batch_name = normalize_text(get_cell_value(wb, sheet_name, f'A{row_num}'))
                start_date_value = get_cell_value(wb, sheet_name, f'C{row_num}')
                days_elapsed_value = get_cell_value(wb, sheet_name, f'E{row_num}')
                
                if batch_name in expected_batches and start_date_value and days_elapsed_value:
                    expected_days = expected_batches[batch_name]['days_ago']
                    
                    if isinstance(days_elapsed_value, (int, float)):
                        # Allow ±2 days tolerance (for timezone differences, calculation methods)
                        if abs(days_elapsed_value - expected_days) <= 2:
                            days_elapsed_correct_count += 1
        
        if days_elapsed_formula_count >= 4 and days_elapsed_correct_count >= 3:
            criteria_scores.append(30)
            feedback_parts.append(f"✅ Formulas: Days elapsed formulas correct ({days_elapsed_correct_count}/4 accurate)")
        elif days_elapsed_formula_count >= 3:
            criteria_scores.append(20)
            feedback_parts.append(f"⚠️ Formulas: {days_elapsed_formula_count}/4 formulas found, {days_elapsed_correct_count} accurate")
        elif days_elapsed_formula_count >= 1:
            criteria_scores.append(10)
            feedback_parts.append(f"⚠️ Formulas: Only {days_elapsed_formula_count}/4 formulas with TODAY()")
        else:
            criteria_scores.append(0)
            feedback_parts.append("❌ Formulas: No TODAY()-based formulas found in Days Elapsed")

        # === CRITERION 4: Status IF Formulas (20 points) ===
        status_formula_count = 0
        
        for row_num in range(2, 6):  # Rows 2-5
            cell_ref = f'F{row_num}'
            cell = sheet[cell_ref]
            
            has_formula = False
            if hasattr(cell, 'value') and isinstance(cell.value, str) and cell.value.startswith('='):
                formula = cell.value
                has_formula = True
            
            if has_formula and has_if_function(formula):
                status_formula_count += 1
        
        if status_formula_count >= 4:
            criteria_scores.append(20)
            feedback_parts.append("✅ Logic: All 4 status cells have IF formulas")
        elif status_formula_count >= 3:
            criteria_scores.append(15)
            feedback_parts.append(f"⚠️ Logic: {status_formula_count}/4 status cells have IF formulas")
        elif status_formula_count >= 1:
            criteria_scores.append(8)
            feedback_parts.append(f"⚠️ Logic: Only {status_formula_count}/4 status cells have IF formulas")
        else:
            criteria_scores.append(0)
            feedback_parts.append("❌ Logic: No IF formulas found in Status column")

        # === CRITERION 5: Status Accuracy (10 points) ===
        correct_status_count = 0
        
        for row_num in range(2, 6):  # Rows 2-5
            batch_name = normalize_text(get_cell_value(wb, sheet_name, f'A{row_num}'))
            status_value = normalize_text(get_cell_value(wb, sheet_name, f'F{row_num}'))
            
            if batch_name in expected_batches:
                expected_status = expected_batches[batch_name]['status']
                
                if expected_status == 'ready':
                    if 'ready' in status_value or 'bottle' in status_value:
                        correct_status_count += 1
                elif expected_status == 'fermenting':
                    if 'fermenting' in status_value or 'still' in status_value:
                        correct_status_count += 1
        
        if correct_status_count >= 4:
            criteria_scores.append(10)
            feedback_parts.append("✅ Accuracy: All 4 batch statuses correct")
        elif correct_status_count >= 3:
            criteria_scores.append(7)
            feedback_parts.append(f"⚠️ Accuracy: {correct_status_count}/4 statuses correct")
        else:
            criteria_scores.append(0)
            feedback_parts.append(f"❌ Accuracy: Only {correct_status_count}/4 statuses correct")

        # Calculate total score
        total_score = sum(criteria_scores)
        passed = total_score >= 75

        feedback = " | ".join(feedback_parts)

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