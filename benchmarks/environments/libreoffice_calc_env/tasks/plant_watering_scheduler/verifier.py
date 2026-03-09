#!/usr/bin/env python3
"""
Verifier for Plant Watering Scheduler task.

Checks:
1. Data structure (5+ plants with all required columns)
2. Next Watering Date formula correctness
3. Days Until formula with TODAY() function
4. Conditional formatting applied to negative values
5. Data sorted by Days Until column (ascending)
6. Calculation accuracy
7. At least one overdue plant exists and is highlighted
"""

import sys
import os
import logging
import re
import zipfile
from datetime import datetime, timedelta
from xml.etree import ElementTree as ET

# Use relative path to utils folder (runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_date_value(value):
    """
    Parse various date formats to datetime object.
    Handles: YYYY-MM-DD, MM/DD/YYYY, DD/MM/YYYY, datetime objects
    """
    if value is None:
        return None
    
    if isinstance(value, datetime):
        return value
    
    if isinstance(value, (int, float)):
        # Excel/ODS date serial number (days since 1899-12-30)
        try:
            base_date = datetime(1899, 12, 30)
            return base_date + timedelta(days=float(value))
        except:
            return None
    
    if isinstance(value, str):
        # Try common date formats
        for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%d/%m/%Y', '%Y/%m/%d', '%d-%m-%Y', '%m-%d-%Y']:
            try:
                return datetime.strptime(value, fmt)
            except:
                continue
    
    return None


def check_formula_pattern(formula, pattern_type):
    """
    Check if formula matches expected pattern.
    
    pattern_type can be:
    - 'next_watering': Should be =C+B or =B+C (Last Watered + Frequency)
    - 'days_until': Should contain TODAY() and subtract from D (=D-TODAY())
    """
    if not formula:
        return False
    
    # Normalize formula
    formula_norm = formula.upper().replace(' ', '').replace('$', '')
    
    if pattern_type == 'next_watering':
        # Look for pattern: =C<num>+B<num> or =B<num>+C<num>
        patterns = [
            r'=C\d+\+B\d+',
            r'=B\d+\+C\d+',
            r'=.*\[\.C\d+\].*\+.*\[\.B\d+\]',  # ODS format
            r'=.*\[\.B\d+\].*\+.*\[\.C\d+\]'
        ]
        for pattern in patterns:
            if re.search(pattern, formula_norm):
                return True
    
    elif pattern_type == 'days_until':
        # Look for pattern: =D<num>-TODAY() or contains TODAY
        if 'TODAY' in formula_norm:
            # Check it involves column D (next watering date)
            if 'D' in formula_norm or '[.D' in formula_norm:
                return True
    
    return False


def check_conditional_formatting_in_ods(filepath, sheet_name='Sheet1'):
    """
    Check if conditional formatting exists for negative values in ODS file.
    Returns: (has_formatting, targets_negative, has_color)
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False, False, False
            
            content_xml = ods_zip.read('content.xml')
            content = content_xml.decode('utf-8')
            
            # Check for conditional formatting markers
            has_conditional = ('conditional-format' in content.lower() or 
                             'style:map' in content.lower())
            
            # Check for condition on negative or less than zero
            targets_negative = ('<0' in content or 
                              'less than 0' in content.lower() or
                              'cell-content()<0' in content)
            
            # Check for color formatting (red, background, etc.)
            has_color = ('color' in content.lower() or 
                        'background' in content.lower() or
                        'fo:color' in content or
                        'fo:background-color' in content)
            
            return has_conditional, targets_negative, has_color
            
    except Exception as e:
        logger.debug(f"Could not check conditional formatting: {e}")
        return False, False, False


def verify_data_structure(data, sheet_name, min_plants=5):
    """
    Verify that the spreadsheet has proper structure with required columns.
    Returns: (is_valid, plant_count, feedback)
    """
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False, 0, "Sheet not found"
        
        rows = sheets[sheet_name]
        if len(rows) < min_plants + 1:  # Header + plants
            return False, 0, f"Not enough rows (need {min_plants + 1}, got {len(rows)})"
        
        # Check header row (row 0)
        if len(rows[0]) < 5:
            return False, 0, "Not enough columns"
        
        # Count non-empty plant rows
        plant_count = 0
        for i in range(1, min(len(rows), 15)):  # Check up to row 15
            row = rows[i]
            # Check if row has data in first 3 columns (Name, Frequency, Last Watered)
            has_data = False
            if len(row) >= 3:
                for j in range(3):
                    cell_val = row[j].get('value') if isinstance(row[j], dict) else row[j]
                    if cell_val is not None and str(cell_val).strip():
                        has_data = True
                        break
            
            if has_data:
                plant_count += 1
        
        if plant_count < min_plants:
            return False, plant_count, f"Not enough plants (need {min_plants}, got {plant_count})"
        
        return True, plant_count, "Data structure valid"
        
    except Exception as e:
        return False, 0, f"Structure check error: {str(e)}"


def verify_formulas_in_column(data, sheet_name, column, pattern_type, start_row=1, min_formulas=3):
    """
    Verify that formulas exist in a column and match expected pattern.
    Returns: (has_formulas, count, feedback)
    """
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False, 0, "Sheet not found"
        
        rows = sheets[sheet_name]
        formula_count = 0
        
        for i in range(start_row, min(len(rows), 15)):
            if len(rows[i]) <= column:
                continue
            
            cell = rows[i][column]
            formula = cell.get('formula') if isinstance(cell, dict) else None
            
            if formula and check_formula_pattern(formula, pattern_type):
                formula_count += 1
        
        if formula_count >= min_formulas:
            return True, formula_count, f"Found {formula_count} correct formulas"
        else:
            return False, formula_count, f"Not enough correct formulas (need {min_formulas}, got {formula_count})"
            
    except Exception as e:
        return False, 0, f"Formula check error: {str(e)}"


def verify_sort_order(data, sheet_name, column=4, order='asc'):
    """
    Verify that data is sorted by specified column.
    column: 0-based index (4 = column E = Days Until)
    Returns: (is_sorted, feedback)
    """
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False, "Sheet not found"
        
        rows = sheets[sheet_name]
        values = []
        
        # Extract numeric values from the column (skip header)
        for i in range(1, min(len(rows), 15)):
            if len(rows[i]) <= column:
                continue
            
            cell = rows[i][column]
            cell_val = cell.get('value') if isinstance(cell, dict) else cell
            
            # Try to convert to number
            if cell_val is not None:
                try:
                    num_val = float(cell_val)
                    values.append((i, num_val))
                except (ValueError, TypeError):
                    pass
        
        if len(values) < 3:
            return False, f"Not enough numeric values to verify sort (got {len(values)})"
        
        # Check sort order
        for i in range(len(values) - 1):
            curr_row, curr_val = values[i]
            next_row, next_val = values[i + 1]
            
            if order == 'asc':
                # Allow small tolerance for TODAY() timing differences
                if curr_val > next_val + 1:
                    return False, f"Not sorted ascending: row {curr_row + 1} ({curr_val}) > row {next_row + 1} ({next_val})"
            else:  # desc
                if curr_val < next_val - 1:
                    return False, f"Not sorted descending: row {curr_row + 1} ({curr_val}) < row {next_row + 1} ({next_val})"
        
        # Check that most negative values are at the top (for ascending)
        if order == 'asc' and len(values) >= 3:
            first_val = values[0][1]
            last_val = values[-1][1]
            if first_val > last_val:
                return False, "Data appears sorted in wrong order (descending instead of ascending)"
        
        return True, f"Data correctly sorted ({order}) by column {column + 1}"
        
    except Exception as e:
        return False, f"Sort check error: {str(e)}"


def check_for_overdue_plants(data, sheet_name, column=4):
    """
    Check if at least one plant is overdue (negative days until value).
    Returns: (has_overdue, count, feedback)
    """
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False, 0, "Sheet not found"
        
        rows = sheets[sheet_name]
        overdue_count = 0
        
        for i in range(1, min(len(rows), 15)):
            if len(rows[i]) <= column:
                continue
            
            cell = rows[i][column]
            cell_val = cell.get('value') if isinstance(cell, dict) else cell
            
            if cell_val is not None:
                try:
                    num_val = float(cell_val)
                    if num_val < 0:
                        overdue_count += 1
                except (ValueError, TypeError):
                    pass
        
        if overdue_count > 0:
            return True, overdue_count, f"Found {overdue_count} overdue plant(s)"
        else:
            return False, 0, "No overdue plants found (all days until values are positive)"
            
    except Exception as e:
        return False, 0, f"Overdue check error: {str(e)}"


def verify_plant_watering_scheduler(traj, env_info, task_info):
    """
    Comprehensive verification of plant watering scheduler task.
    
    Checks 7 criteria:
    1. Data structure (5+ plants with all columns)
    2. Next Watering formula correctness
    3. Days Until formula with TODAY()
    4. Conditional formatting applied
    5. Sorted by priority (ascending)
    6. At least one overdue plant
    7. Calculation accuracy
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Setup verification
    container_path = "/home/ga/Documents/plant_watering_schedule.ods"
    success, file_info, error = setup_calc_verification(
        copy_from_env,
        container_path,
        expected_formats=['ods', 'xlsx']
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"File not found or unreadable: {error}"}
    
    try:
        data = file_info['sheet_data']
        sheet_names = get_sheet_names(data)
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        feedback_parts = []
        criteria_met = 0
        total_criteria = 7
        
        # Criterion 1: Data structure (5+ plants)
        structure_ok, plant_count, struct_msg = verify_data_structure(data, sheet_name, min_plants=5)
        if structure_ok:
            criteria_met += 1
            feedback_parts.append(f"✅ Data structure valid ({plant_count} plants)")
        else:
            feedback_parts.append(f"❌ Data structure issue: {struct_msg}")
        
        # Criterion 2: Next Watering Date formula (column D, index 3)
        next_formula_ok, next_count, next_msg = verify_formulas_in_column(
            data, sheet_name, column=3, pattern_type='next_watering', min_formulas=3
        )
        if next_formula_ok:
            criteria_met += 1
            feedback_parts.append(f"✅ Next Watering formulas correct ({next_count} found)")
        else:
            feedback_parts.append(f"❌ Next Watering formulas: {next_msg}")
        
        # Criterion 3: Days Until formula with TODAY() (column E, index 4)
        days_formula_ok, days_count, days_msg = verify_formulas_in_column(
            data, sheet_name, column=4, pattern_type='days_until', min_formulas=3
        )
        if days_formula_ok:
            criteria_met += 1
            feedback_parts.append(f"✅ Days Until formulas with TODAY() correct ({days_count} found)")
        else:
            feedback_parts.append(f"❌ Days Until formulas: {days_msg}")
        
        # Criterion 4: Conditional formatting
        has_cond_fmt, targets_neg, has_color = check_conditional_formatting_in_ods(
            file_info['file_path'], sheet_name
        )
        
        if has_cond_fmt and (targets_neg or has_color):
            criteria_met += 1
            feedback_parts.append("✅ Conditional formatting applied")
        else:
            if has_cond_fmt:
                feedback_parts.append("⚠️ Conditional formatting found but may not target negative values")
                criteria_met += 0.5  # Partial credit
            else:
                feedback_parts.append("❌ No conditional formatting detected")
        
        # Criterion 5: Sorted by Days Until (ascending)
        sorted_ok, sort_msg = verify_sort_order(data, sheet_name, column=4, order='asc')
        if sorted_ok:
            criteria_met += 1
            feedback_parts.append("✅ Data sorted by priority (ascending)")
        else:
            feedback_parts.append(f"❌ Sort issue: {sort_msg}")
        
        # Criterion 6: At least one overdue plant
        has_overdue, overdue_count, overdue_msg = check_for_overdue_plants(data, sheet_name, column=4)
        if has_overdue:
            criteria_met += 1
            feedback_parts.append(f"✅ Overdue plants present ({overdue_count} overdue)")
        else:
            feedback_parts.append(f"❌ No overdue plants: {overdue_msg}")
        
        # Criterion 7: Basic calculation accuracy check
        # Check if at least one Next Watering Date looks reasonable
        calc_ok = False
        try:
            # Check row 2 as sample
            freq_val = get_cell_value(data, sheet_name, 'B2')
            last_water_val = get_cell_value(data, sheet_name, 'C2')
            next_water_val = get_cell_value(data, sheet_name, 'D2')
            
            if freq_val and last_water_val and next_water_val:
                freq_num = float(freq_val)
                last_date = parse_date_value(last_water_val)
                next_date = parse_date_value(next_water_val)
                
                if last_date and next_date:
                    expected_next = last_date + timedelta(days=freq_num)
                    diff_days = abs((next_date - expected_next).total_seconds() / 86400)
                    
                    if diff_days <= 1:  # Allow 1 day tolerance
                        calc_ok = True
        except Exception as e:
            logger.debug(f"Calculation check error: {e}")
        
        if calc_ok:
            criteria_met += 1
            feedback_parts.append("✅ Calculations accurate")
        else:
            feedback_parts.append("⚠️ Could not verify calculation accuracy")
            criteria_met += 0.5  # Partial credit if we can't verify
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 70  # Pass threshold is 70% (5/7 criteria)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent plant watering tracker!")
        elif passed:
            feedback_parts.insert(0, "✅ Plant watering tracker completed")
        else:
            feedback_parts.insert(0, "❌ Tracker incomplete - review requirements")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "data_structure": structure_ok,
                "next_watering_formula": next_formula_ok,
                "days_until_formula": days_formula_ok,
                "conditional_formatting": has_cond_fmt and (targets_neg or has_color),
                "sorted_correctly": sorted_ok,
                "has_overdue_plants": has_overdue,
                "calculations_accurate": calc_ok
            },
            "criteria_met": criteria_met,
            "criteria_total": total_criteria
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        cleanup_verification_temp(file_info.get('temp_dir'))
