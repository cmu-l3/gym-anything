#!/usr/bin/env python3
"""
Verifier for Medication Schedule Update task

Checks:
1. Formulas present in Next Dose column
2. Formulas calculate correctly (Last Dose + Frequency)
3. Metformin frequency updated to 8 hours
4. Aspirin last dose updated to 8:00 AM today
5. Conditional formatting applied to Next Dose column
6. No formula errors
"""

import sys
import os
import logging
from datetime import datetime, time
import re

# Use relative path to utils folder (verification runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    check_conditional_formatting,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_time_value(value):
    """
    Parse time value from various formats Calc might use.
    Calc stores times as fractional days (0.5 = noon, 1.0 = 24 hours).
    
    Returns: float representing fractional day, or None if can't parse
    """
    if value is None:
        return None
    
    # If already a float between 0 and 1000 (could be fractional day or date serial)
    if isinstance(value, (int, float)):
        return float(value)
    
    # Try parsing as string datetime
    if isinstance(value, str):
        # Try common date-time formats
        for fmt in ["%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M"]:
            try:
                dt = datetime.strptime(value, fmt)
                # Convert to fractional days from epoch (simplified for comparison)
                # For this task, we mainly care about the time component
                return dt.timestamp() / 86400.0  # Rough conversion
            except ValueError:
                continue
    
    return None


def check_formula_structure(formula, row_num):
    """
    Check if formula has correct structure for calculating next dose.
    Should reference: Last Dose Time (D column) and Frequency (C column)
    
    Expected patterns:
    - =D2+(C2/24)
    - =D2+C2/24
    - =D2+(C2*0.041667)  [1/24 ≈ 0.041667]
    - Other variations using TIME function, etc.
    """
    if not formula:
        return False
    
    # Normalize formula (uppercase, remove spaces)
    formula_norm = formula.upper().replace(' ', '')
    
    # Check if formula references correct cells for this row
    d_ref = f"D{row_num}"
    c_ref = f"C{row_num}"
    
    # Must reference both Last Dose Time (D) and Frequency (C) columns
    if d_ref not in formula_norm or c_ref not in formula_norm:
        return False
    
    # Should contain division by 24 or equivalent
    # Accept: /24, *0.041, *0.042, TIME function, etc.
    valid_patterns = [
        r'/24',           # Divide by 24
        r'\*0\.041',      # Multiply by ~1/24
        r'\*0\.042',      # Multiply by ~1/24
        r'TIME\(',        # Using TIME function
        r'HOUR\(',        # Using HOUR function
    ]
    
    has_time_conversion = any(re.search(pattern, formula_norm) for pattern in valid_patterns)
    
    return has_time_conversion


def verify_calculation_accuracy(last_dose, frequency_hours, next_dose, tolerance_hours=0.1):
    """
    Verify that next_dose = last_dose + frequency (in fractional days).
    
    Args:
        last_dose: Fractional day value or datetime
        frequency_hours: Number of hours (float or int)
        next_dose: Calculated next dose (fractional day value)
        tolerance_hours: Tolerance in hours (default 0.1 = 6 minutes)
    
    Returns:
        bool: True if calculation is accurate within tolerance
    """
    try:
        # Convert inputs to float
        last_dose_float = float(last_dose) if last_dose is not None else None
        frequency_float = float(frequency_hours) if frequency_hours is not None else None
        next_dose_float = float(next_dose) if next_dose is not None else None
        
        if None in [last_dose_float, frequency_float, next_dose_float]:
            return False
        
        # Calculate expected next dose
        frequency_days = frequency_float / 24.0
        expected_next_dose = last_dose_float + frequency_days
        
        # Check if within tolerance
        tolerance_days = tolerance_hours / 24.0
        difference = abs(next_dose_float - expected_next_dose)
        
        return difference <= tolerance_days
        
    except (ValueError, TypeError) as e:
        logger.debug(f"Error in calculation accuracy check: {e}")
        return False


def verify_medication_schedule(traj, env_info, task_info):
    """
    Main verification function for medication schedule update task.
    
    Returns:
        dict with keys: passed, score, feedback, subscores
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to load the file (try ODS first, then CSV)
    temp_dir = None
    success = False
    workbook = None
    
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/medication_schedule_updated.ods'),
        ('ods', '/home/ga/Documents/medication_schedule.ods'),
        ('csv', '/home/ga/Documents/medication_schedule.csv')
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet file: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook.get('sheets', {}).keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        logger.info(f"Using sheet: {sheet_name}")
        
        # Initialize scoring
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Define medication rows (assuming header in row 1, data starts row 2)
        medication_rows = {
            'Lisinopril': 2,
            'Metformin': 3,
            'Atorvastatin': 4,
            'Aspirin': 5,
            'Gabapentin': 6
        }
        
        # CRITERION 1: Check that formulas exist in Next Dose column (E)
        formulas_found = 0
        formulas_with_correct_structure = 0
        
        for med_name, row_num in medication_rows.items():
            next_dose_formula = get_cell_formula(workbook, sheet_name, f'E{row_num}')
            
            if next_dose_formula:
                formulas_found += 1
                
                # Check formula structure
                if check_formula_structure(next_dose_formula, row_num):
                    formulas_with_correct_structure += 1
                else:
                    logger.debug(f"Row {row_num} ({med_name}): Formula structure issue - {next_dose_formula}")
        
        if formulas_found >= 4:  # At least 4 out of 5 medications should have formulas
            criteria_passed += 1
            subscores['formulas_present'] = True
            feedback_parts.append(f"✅ Formulas present ({formulas_found}/5 medications)")
        else:
            subscores['formulas_present'] = False
            feedback_parts.append(f"❌ Missing formulas ({formulas_found}/5 found, need at least 4)")
        
        # CRITERION 2: Check formula calculations are accurate
        accurate_calculations = 0
        total_calculations = 0
        
        for med_name, row_num in medication_rows.items():
            last_dose = get_cell_value(workbook, sheet_name, f'D{row_num}')
            frequency = get_cell_value(workbook, sheet_name, f'C{row_num}')
            next_dose = get_cell_value(workbook, sheet_name, f'E{row_num}')
            
            if last_dose is not None and frequency is not None and next_dose is not None:
                total_calculations += 1
                
                if verify_calculation_accuracy(last_dose, frequency, next_dose):
                    accurate_calculations += 1
                else:
                    logger.debug(f"Row {row_num} ({med_name}): Calculation accuracy issue")
                    logger.debug(f"  Last Dose: {last_dose}, Frequency: {frequency}, Next Dose: {next_dose}")
        
        accuracy_rate = accurate_calculations / total_calculations if total_calculations > 0 else 0
        
        if accuracy_rate >= 0.8:  # At least 80% accurate
            criteria_passed += 1
            subscores['calculations_correct'] = True
            feedback_parts.append(f"✅ Calculations correct ({accurate_calculations}/{total_calculations})")
        else:
            subscores['calculations_correct'] = False
            feedback_parts.append(f"❌ Calculation errors ({accurate_calculations}/{total_calculations} accurate, need 80%)")
        
        # CRITERION 3: Check Metformin frequency updated to 8 hours
        metformin_row = medication_rows['Metformin']
        metformin_frequency = get_cell_value(workbook, sheet_name, f'C{metformin_row}')
        
        metformin_freq_correct = False
        if metformin_frequency is not None:
            try:
                freq_value = float(metformin_frequency)
                if abs(freq_value - 8) < 0.1:
                    criteria_passed += 1
                    metformin_freq_correct = True
                    subscores['frequency_updated'] = True
                    feedback_parts.append(f"✅ Metformin frequency updated to 8 hours")
                else:
                    subscores['frequency_updated'] = False
                    feedback_parts.append(f"❌ Metformin frequency not updated (found {freq_value}, expected 8)")
            except (ValueError, TypeError):
                subscores['frequency_updated'] = False
                feedback_parts.append(f"❌ Metformin frequency invalid: {metformin_frequency}")
        else:
            subscores['frequency_updated'] = False
            feedback_parts.append(f"❌ Metformin frequency missing")
        
        # CRITERION 4: Check Aspirin last dose updated to 8:00 AM today
        aspirin_row = medication_rows['Aspirin']
        aspirin_last_dose = get_cell_value(workbook, sheet_name, f'D{aspirin_row}')
        
        aspirin_time_correct = False
        if aspirin_last_dose is not None:
            # Check if time component is around 8:00 AM (0.333... as fractional day)
            # 8:00 AM = 8/24 = 0.333...
            try:
                # Try to extract time component
                dose_str = str(aspirin_last_dose)
                
                # Check for "08:00" or "8:00" in string representation
                if '08:00' in dose_str or '8:00' in dose_str:
                    criteria_passed += 1
                    aspirin_time_correct = True
                    subscores['last_dose_updated'] = True
                    feedback_parts.append(f"✅ Aspirin last dose updated to 8:00 AM")
                else:
                    # If it's a float, check if time component is around 8/24
                    if isinstance(aspirin_last_dose, (int, float)):
                        time_fraction = aspirin_last_dose - int(aspirin_last_dose)
                        expected_time_fraction = 8.0 / 24.0  # 0.333...
                        
                        if abs(time_fraction - expected_time_fraction) < 0.02:  # Within ~30 minutes
                            criteria_passed += 1
                            aspirin_time_correct = True
                            subscores['last_dose_updated'] = True
                            feedback_parts.append(f"✅ Aspirin last dose updated to 8:00 AM")
                        else:
                            subscores['last_dose_updated'] = False
                            feedback_parts.append(f"❌ Aspirin last dose time incorrect (expected 8:00 AM)")
                    else:
                        subscores['last_dose_updated'] = False
                        feedback_parts.append(f"❌ Aspirin last dose time not updated to 8:00 AM")
            except (ValueError, TypeError) as e:
                logger.debug(f"Error checking Aspirin time: {e}")
                subscores['last_dose_updated'] = False
                feedback_parts.append(f"❌ Aspirin last dose format issue")
        else:
            subscores['last_dose_updated'] = False
            feedback_parts.append(f"❌ Aspirin last dose missing")
        
        # CRITERION 5: Check conditional formatting applied
        has_conditional_formatting = check_conditional_formatting(
            workbook, 
            sheet_name, 
            "E2:E6"
        )
        
        if has_conditional_formatting:
            criteria_passed += 1
            subscores['conditional_formatting'] = True
            feedback_parts.append(f"✅ Conditional formatting applied")
        else:
            subscores['conditional_formatting'] = False
            feedback_parts.append(f"⚠️ Conditional formatting not detected (may not be in ODS format or not applied)")
            # Give partial credit if formulas are otherwise correct
            if formulas_with_correct_structure >= 4:
                criteria_passed += 0.5
                feedback_parts[-1] = f"⚠️ Conditional formatting not detected (partial credit for correct formulas)"
        
        # CRITERION 6: Check no formula errors
        has_errors = False
        error_indicators = ['#VALUE!', '#REF!', '#NAME?', '#DIV/0!', '#N/A', '#NUM!']
        
        for row_num in medication_rows.values():
            next_dose_value = get_cell_value(workbook, sheet_name, f'E{row_num}')
            if next_dose_value and any(err in str(next_dose_value) for err in error_indicators):
                has_errors = True
                break
        
        if not has_errors:
            criteria_passed += 1
            subscores['no_errors'] = True
            feedback_parts.append(f"✅ No formula errors")
        else:
            subscores['no_errors'] = False
            feedback_parts.append(f"❌ Formula errors detected")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold is 70%
        
        # Add overall assessment
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent! Medication schedule updated successfully")
        elif passed:
            feedback_parts.insert(0, "✅ Task completed - medication schedule functional")
        else:
            feedback_parts.insert(0, "❌ Task incomplete - check requirements")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
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
        cleanup_verification_temp(temp_dir)
