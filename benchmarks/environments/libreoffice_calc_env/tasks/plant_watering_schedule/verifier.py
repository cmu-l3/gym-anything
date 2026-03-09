#!/usr/bin/env python3
"""
Verifier for Plant Watering Schedule task.

Checks:
1. Formulas are structurally correct (Next Due, Days Until, Priority)
2. Calculated values are accurate for sample rows
3. Conditional formatting is applied
4. Data is sorted by Next Watering Due
5. No formula errors present
"""

import sys
import os
import logging
import re
from datetime import datetime, timedelta
from typing import Dict, Any, Tuple, Optional

# Use relative path to utils folder (verifier runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    verify_data_sorted,
    check_conditional_formatting,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_date_value(date_val: Any) -> Optional[datetime]:
    """
    Parse date from various formats.
    
    Args:
        date_val: Date value (string, datetime, or number)
        
    Returns:
        datetime object or None
    """
    if date_val is None:
        return None
    
    if isinstance(date_val, datetime):
        return date_val
    
    # Try parsing string dates
    if isinstance(date_val, str):
        # Try common formats
        for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%d/%m/%Y', '%Y/%m/%d']:
            try:
                return datetime.strptime(date_val, fmt)
            except ValueError:
                continue
        
        # Try extracting date from string like "2024-01-15 00:00:00"
        match = re.search(r'(\d{4}[-/]\d{2}[-/]\d{2})', str(date_val))
        if match:
            try:
                return datetime.strptime(match.group(1), '%Y-%m-%d')
            except ValueError:
                pass
    
    # Try numeric date (Excel/Calc serial date number)
    if isinstance(date_val, (int, float)):
        try:
            # LibreOffice Calc uses 1899-12-30 as base date
            base_date = datetime(1899, 12, 30)
            return base_date + timedelta(days=int(date_val))
        except (ValueError, OverflowError):
            pass
    
    return None


def calculate_expected_priority(days_until: float) -> str:
    """Calculate expected priority based on days until watering."""
    if days_until < 0:
        return "OVERDUE"
    elif days_until == 0:
        return "TODAY"
    elif days_until <= 2:
        return "SOON"
    else:
        return "OK"


def check_formula_structure(formula: str, expected_pattern: str) -> bool:
    """
    Check if formula matches expected structure.
    
    Args:
        formula: Actual formula string
        expected_pattern: Pattern to match (e.g., "C+D" for addition)
        
    Returns:
        True if formula structure is correct
    """
    if not formula:
        return False
    
    # Normalize formula (uppercase, remove spaces)
    norm_formula = formula.upper().replace(' ', '')
    
    # Check for expected pattern
    if expected_pattern == "C+D":
        # Check for pattern like =C2+D2 or =C3+D3
        return bool(re.search(r'=C\d+\+D\d+', norm_formula))
    elif expected_pattern == "E-TODAY()":
        # Check for pattern like =E2-TODAY()
        return 'TODAY()' in norm_formula and ('-' in norm_formula or '−' in norm_formula)
    elif expected_pattern == "IF_NESTED":
        # Check for nested IF structure
        return 'IF(' in norm_formula and norm_formula.count('IF(') >= 3
    
    return False


def check_for_formula_errors(data: Dict[str, Any], sheet_name: str, 
                            start_row: int = 2, end_row: int = 20) -> bool:
    """
    Check if any cells contain formula errors.
    
    Args:
        data: Parsed spreadsheet data
        sheet_name: Sheet name
        start_row: Starting row (1-indexed)
        end_row: Ending row (1-indexed)
        
    Returns:
        True if errors found, False otherwise
    """
    try:
        sheet_data = data['sheets'][sheet_name]
        
        for row_idx in range(start_row - 1, min(end_row, len(sheet_data))):
            if row_idx >= len(sheet_data):
                break
                
            row = sheet_data[row_idx]
            for cell in row:
                value = cell.get('value') if isinstance(cell, dict) else cell
                if value and isinstance(value, str):
                    if any(err in str(value) for err in ['#VALUE!', '#REF!', '#NAME?', '#DIV/0!', '#N/A', '#NUM!']):
                        return True
        
        return False
        
    except Exception as e:
        logger.warning(f"Error checking for formula errors: {e}")
        return False


def find_column_by_header(sheet_data: list, header_name: str) -> Optional[int]:
    """
    Find column index by header name.
    
    Args:
        sheet_data: Sheet data (list of rows)
        header_name: Header name to find
        
    Returns:
        Column index (0-based) or None
    """
    if not sheet_data or len(sheet_data) == 0:
        return None
    
    header_row = sheet_data[0]
    header_name_lower = header_name.lower()
    
    for col_idx, cell in enumerate(header_row):
        cell_value = cell.get('value') if isinstance(cell, dict) else cell
        if cell_value and header_name_lower in str(cell_value).lower():
            return col_idx
    
    return None


def verify_plant_watering_schedule(traj, env_info, task_info):
    """
    Verify houseplant watering schedule task completion.
    
    Checks:
    1. Formulas correct (25 points)
    2. Calculations accurate (25 points)
    3. Conditional formatting (20 points)
    4. Data sorted (20 points)
    5. No formula errors (10 points)
    
    Returns:
        Dict with passed, score, feedback, and subscores
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/plant_schedule.ods",
        "/home/ga/Documents/plants_data.ods",
        "/home/ga/Documents/plants_data.csv"
    ]
    
    success = False
    file_info = {}
    
    for container_path in possible_paths:
        # Determine format from extension
        if container_path.endswith('.csv'):
            formats = ['csv']
        else:
            formats = ['ods']
        
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            formats
        )
        
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load spreadsheet. Tried: {', '.join(possible_paths)}. Error: {error}"
        }
    
    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = data['sheets'][sheet_name]
        
        # Initialize scoring
        score = 0
        max_score = 100
        feedback_parts = []
        subscores = {}
        
        # === CRITERION 1: Formula Correctness (25 points) ===
        formula_score = 0
        
        # Check Next Watering Due formula (10 points)
        next_due_formula = get_cell_formula(data, sheet_name, "E2")
        if next_due_formula and check_formula_structure(next_due_formula, "C+D"):
            formula_score += 10
            feedback_parts.append(f"✅ Next Watering Due formula correct: {next_due_formula}")
            subscores['next_due_formula'] = True
        else:
            feedback_parts.append(f"❌ Next Watering Due formula incorrect or missing (got: {next_due_formula})")
            subscores['next_due_formula'] = False
        
        # Check Days Until formula (10 points)
        days_until_formula = get_cell_formula(data, sheet_name, "F2")
        if days_until_formula and check_formula_structure(days_until_formula, "E-TODAY()"):
            formula_score += 10
            feedback_parts.append(f"✅ Days Until formula uses TODAY(): {days_until_formula}")
            subscores['days_until_formula'] = True
        else:
            feedback_parts.append(f"❌ Days Until formula missing or doesn't use TODAY() (got: {days_until_formula})")
            subscores['days_until_formula'] = False
        
        # Check Priority formula (5 points)
        priority_formula = get_cell_formula(data, sheet_name, "G2")
        if priority_formula and check_formula_structure(priority_formula, "IF_NESTED"):
            formula_score += 5
            feedback_parts.append("✅ Priority formula uses conditional logic")
            subscores['priority_formula'] = True
        else:
            feedback_parts.append(f"❌ Priority formula missing or incorrect (got: {priority_formula})")
            subscores['priority_formula'] = False
        
        score += formula_score
        
        # === CRITERION 2: Calculation Accuracy (25 points) ===
        calculation_score = 0
        
        # Sample check row 2: verify date arithmetic
        last_watered = get_cell_value(data, sheet_name, "C2")
        frequency = get_cell_value(data, sheet_name, "D2")
        next_due = get_cell_value(data, sheet_name, "E2")
        days_until = get_cell_value(data, sheet_name, "F2")
        priority = get_cell_value(data, sheet_name, "G2")
        
        # Parse dates
        last_watered_date = parse_date_value(last_watered)
        next_due_date = parse_date_value(next_due)
        
        # Check date calculation
        if last_watered_date and frequency and next_due_date:
            try:
                frequency_num = int(frequency)
                expected_next = last_watered_date + timedelta(days=frequency_num)
                
                # Allow 1 day tolerance for calculation differences
                date_diff = abs((next_due_date - expected_next).days)
                if date_diff <= 1:
                    calculation_score += 15
                    feedback_parts.append("✅ Date calculations accurate")
                    subscores['date_calc_accurate'] = True
                else:
                    feedback_parts.append(f"❌ Date calculation error: expected {expected_next.date()}, got {next_due_date.date()}")
                    subscores['date_calc_accurate'] = False
            except (ValueError, TypeError) as e:
                feedback_parts.append(f"❌ Could not verify date calculation: {e}")
                subscores['date_calc_accurate'] = False
        else:
            feedback_parts.append("❌ Missing date data for verification")
            subscores['date_calc_accurate'] = False
        
        # Check priority logic
        if days_until is not None and priority:
            try:
                days_until_num = float(days_until)
                expected_priority = calculate_expected_priority(days_until_num)
                
                # Normalize for comparison
                priority_str = str(priority).strip().upper()
                
                if priority_str == expected_priority:
                    calculation_score += 10
                    feedback_parts.append(f"✅ Priority categorization correct: {priority}")
                    subscores['priority_correct'] = True
                else:
                    feedback_parts.append(f"❌ Priority incorrect: expected {expected_priority}, got {priority}")
                    subscores['priority_correct'] = False
            except (ValueError, TypeError):
                feedback_parts.append(f"❌ Could not verify priority calculation")
                subscores['priority_correct'] = False
        else:
            feedback_parts.append("❌ Missing priority data for verification")
            subscores['priority_correct'] = False
        
        score += calculation_score
        
        # === CRITERION 3: Conditional Formatting (20 points) ===
        # Check if conditional formatting is applied to Priority column or data range
        has_formatting = check_conditional_formatting(data, sheet_name, "G2:G20")
        
        if has_formatting:
            score += 20
            feedback_parts.append("✅ Conditional formatting applied")
            subscores['conditional_formatting'] = True
        else:
            # Also check if formatting applied to entire range
            has_formatting_alt = check_conditional_formatting(data, sheet_name, "A1:G20")
            if has_formatting_alt:
                score += 20
                feedback_parts.append("✅ Conditional formatting applied")
                subscores['conditional_formatting'] = True
            else:
                feedback_parts.append("❌ No conditional formatting detected")
                subscores['conditional_formatting'] = False
        
        # === CRITERION 4: Data Sorted (20 points) ===
        # Find Next Watering Due column index
        next_due_col = find_column_by_header(sheet_data, "Next")
        
        if next_due_col is not None:
            is_sorted, sort_msg = verify_data_sorted(
                {'rows': sheet_data},
                column=next_due_col,
                order='asc',
                start_row=1,  # Skip header
                end_row=min(13, len(sheet_data))  # Check up to 12 data rows + header
            )
            
            if is_sorted:
                score += 20
                feedback_parts.append("✅ Data sorted by Next Watering Due (ascending)")
                subscores['data_sorted'] = True
            else:
                feedback_parts.append(f"❌ Data not properly sorted: {sort_msg}")
                subscores['data_sorted'] = False
        else:
            feedback_parts.append("⚠️ Could not find Next Watering Due column for sort verification")
            subscores['data_sorted'] = False
        
        # === CRITERION 5: No Formula Errors (10 points) ===
        has_errors = check_for_formula_errors(data, sheet_name, start_row=2, end_row=13)
        
        if not has_errors:
            score += 10
            feedback_parts.append("✅ No formula errors detected")
            subscores['no_errors'] = True
        else:
            feedback_parts.append("❌ Formula errors found (#VALUE!, #REF!, etc.)")
            subscores['no_errors'] = False
        
        # Calculate final result
        passed = score >= 75  # 75% threshold
        
        # Add summary message
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent plant watering schedule created!")
        elif passed:
            feedback_parts.insert(0, "✅ Plant watering schedule completed successfully")
        else:
            feedback_parts.insert(0, "❌ Plant watering schedule requirements not fully met")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        # Clean up temporary files
        cleanup_verification_temp(file_info.get('temp_dir'))
