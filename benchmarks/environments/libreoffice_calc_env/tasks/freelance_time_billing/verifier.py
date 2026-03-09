#!/usr/bin/env python3
"""
Verifier for Freelance Time Billing task

Checks:
1. Duration calculations from start/end times
2. Amount calculations from duration × rate
3. Client subtotals
4. Grand total
5. Formula usage (not hardcoded values)
"""

import sys
import os
import logging
import re

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_time_to_decimal(time_value):
    """
    Parse time value to decimal hours.
    ODS stores times as decimal fractions of a day.
    """
    if isinstance(time_value, (int, float)):
        # Already decimal, convert from fraction-of-day to hours
        return float(time_value) * 24
    
    if isinstance(time_value, str):
        # Try to parse time string
        time_str = time_value.strip().upper()
        
        # Handle formats like "9:00 AM", "2:00 PM"
        if "AM" in time_str or "PM" in time_str:
            is_pm = "PM" in time_str
            time_part = time_str.replace("AM", "").replace("PM", "").strip()
            
            if ":" in time_part:
                parts = time_part.split(":")
                hour = int(parts[0])
                minute = int(parts[1]) if len(parts) > 1 else 0
            else:
                hour = int(time_part)
                minute = 0
            
            if is_pm and hour != 12:
                hour += 12
            elif not is_pm and hour == 12:
                hour = 0
            
            return hour + minute / 60.0
    
    return None


def calculate_expected_duration(start_time, end_time):
    """Calculate expected duration in decimal hours from start and end times"""
    start_decimal = parse_time_to_decimal(start_time)
    end_decimal = parse_time_to_decimal(end_time)
    
    if start_decimal is not None and end_decimal is not None:
        duration = end_decimal - start_decimal
        if duration < 0:  # Handle crossing midnight (though not expected in this task)
            duration += 24
        return duration
    
    return None


def verify_freelance_billing(traj, env_info, task_info):
    """
    Verify freelance time billing task completion.
    
    Checks:
    1. Duration calculations (from time differences)
    2. Amount calculations (duration × rate)
    3. Client subtotals
    4. Grand total
    5. Formula usage
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/freelance_timesheet.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load timesheet: {error}"}

    try:
        # Get first sheet
        sheet_names = get_sheet_names(workbook)
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]

        criteria_passed = 0.0
        total_criteria = 6
        feedback_parts = []

        # Expected data structure:
        # Row 2-4: Acme Corp entries
        # Row 5: Acme subtotal
        # Row 6-8: TechStart entries
        # Row 9: TechStart subtotal
        # Row 10-11: LocalBiz entries
        # Row 12: LocalBiz subtotal
        # Row 13: Grand total

        # Define work entry rows (row_num, client, has_times, expected_duration, rate)
        work_entries = [
            (2, "Acme Corp", True, 2.5, 75),      # 9:00 AM - 11:30 AM
            (3, "Acme Corp", False, 4.0, 75),     # Given duration
            (4, "Acme Corp", True, 2.0, 75),      # 2:00 PM - 4:00 PM
            (6, "TechStart Inc", True, 3.5, 85),  # 1:00 PM - 4:30 PM
            (7, "TechStart Inc", False, 2.5, 85), # Given duration
            (8, "TechStart Inc", True, 2.0, 85),  # 10:00 AM - 12:00 PM
            (10, "LocalBiz LLC", True, 1.25, 65), # 3:00 PM - 4:15 PM
            (11, "LocalBiz LLC", False, 3.0, 65), # Given duration
        ]

        # Criterion 1: Duration calculations
        duration_errors = []
        duration_correct_count = 0
        for row_num, client, has_times, expected_duration, rate in work_entries:
            duration_cell = f"F{row_num}"
            actual_duration = get_cell_value(workbook, sheet_name, duration_cell)
            
            if actual_duration is not None:
                try:
                    actual_duration_float = float(actual_duration)
                    if abs(actual_duration_float - expected_duration) <= 0.15:  # Tolerance for rounding
                        duration_correct_count += 1
                    else:
                        duration_errors.append(f"Row {row_num}: expected {expected_duration} hrs, got {actual_duration_float:.2f}")
                except (ValueError, TypeError):
                    duration_errors.append(f"Row {row_num}: invalid duration value")
            else:
                duration_errors.append(f"Row {row_num}: missing duration")
        
        if duration_correct_count >= 6:  # At least 6 out of 8 correct
            criteria_passed += 1.0
            feedback_parts.append(f"✅ Duration calculations correct ({duration_correct_count}/8 entries)")
        elif duration_correct_count >= 4:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Duration calculations partially correct ({duration_correct_count}/8 entries)")
        else:
            feedback_parts.append(f"❌ Duration calculations incorrect ({duration_correct_count}/8 correct)")
            if duration_errors[:2]:  # Show first 2 errors
                feedback_parts.append(f"   Examples: {'; '.join(duration_errors[:2])}")

        # Criterion 2: Amount calculations
        amount_errors = []
        amount_correct_count = 0
        for row_num, client, has_times, expected_duration, rate in work_entries:
            amount_cell = f"H{row_num}"
            actual_amount = get_cell_value(workbook, sheet_name, amount_cell)
            expected_amount = expected_duration * rate
            
            if actual_amount is not None:
                try:
                    actual_amount_float = float(actual_amount)
                    if abs(actual_amount_float - expected_amount) <= 1.0:  # $1 tolerance
                        amount_correct_count += 1
                    else:
                        amount_errors.append(f"Row {row_num}: expected ${expected_amount:.2f}, got ${actual_amount_float:.2f}")
                except (ValueError, TypeError):
                    amount_errors.append(f"Row {row_num}: invalid amount")
            else:
                amount_errors.append(f"Row {row_num}: missing amount")
        
        if amount_correct_count >= 6:  # At least 6 out of 8 correct
            criteria_passed += 1.0
            feedback_parts.append(f"✅ Amount calculations correct ({amount_correct_count}/8 entries)")
        elif amount_correct_count >= 4:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Amount calculations partially correct ({amount_correct_count}/8 entries)")
        else:
            feedback_parts.append(f"❌ Amount calculations incorrect ({amount_correct_count}/8 correct)")
            if amount_errors[:2]:
                feedback_parts.append(f"   Examples: {'; '.join(amount_errors[:2])}")

        # Criterion 3: Client subtotals
        # Expected subtotals:
        # Acme Corp (rows 2-4): 2.5*75 + 4.0*75 + 2.0*75 = 187.50 + 300 + 150 = 637.50
        # TechStart Inc (rows 6-8): 3.5*85 + 2.5*85 + 2.0*85 = 297.50 + 212.50 + 170 = 680.00
        # LocalBiz LLC (rows 10-11): 1.25*65 + 3.0*65 = 81.25 + 195 = 276.25
        
        expected_subtotals = {
            "Acme Corp": (5, 637.50),      # Row 5
            "TechStart Inc": (9, 680.00),  # Row 9
            "LocalBiz LLC": (12, 276.25),  # Row 12
        }
        
        subtotal_correct_count = 0
        for client_name, (row_num, expected_subtotal) in expected_subtotals.items():
            subtotal_cell = f"H{row_num}"
            actual_subtotal = get_cell_value(workbook, sheet_name, subtotal_cell)
            
            if actual_subtotal is not None:
                try:
                    actual_subtotal_float = float(actual_subtotal)
                    if abs(actual_subtotal_float - expected_subtotal) <= 5.0:  # $5 tolerance
                        subtotal_correct_count += 1
                    else:
                        feedback_parts.append(f"⚠️ {client_name} subtotal: expected ${expected_subtotal:.2f}, got ${actual_subtotal_float:.2f}")
                except (ValueError, TypeError):
                    feedback_parts.append(f"❌ {client_name} subtotal: invalid value")
            else:
                feedback_parts.append(f"❌ {client_name} subtotal: missing")
        
        if subtotal_correct_count == 3:
            criteria_passed += 1.0
            feedback_parts.append("✅ All client subtotals correct (3/3)")
        elif subtotal_correct_count >= 2:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Client subtotals partially correct ({subtotal_correct_count}/3)")
        else:
            feedback_parts.append(f"❌ Client subtotals incorrect ({subtotal_correct_count}/3 correct)")

        # Criterion 4: Grand total
        expected_grand_total = 637.50 + 680.00 + 276.25  # 1593.75
        grand_total_cell = "H13"
        actual_grand_total = get_cell_value(workbook, sheet_name, grand_total_cell)
        
        grand_total_correct = False
        if actual_grand_total is not None:
            try:
                actual_grand_total_float = float(actual_grand_total)
                if abs(actual_grand_total_float - expected_grand_total) <= 10.0:  # $10 tolerance
                    criteria_passed += 1.0
                    grand_total_correct = True
                    feedback_parts.append(f"✅ Grand total correct: ${actual_grand_total_float:.2f}")
                else:
                    feedback_parts.append(f"❌ Grand total incorrect: expected ${expected_grand_total:.2f}, got ${actual_grand_total_float:.2f}")
            except (ValueError, TypeError):
                feedback_parts.append("❌ Grand total: invalid value")
        else:
            feedback_parts.append("❌ Grand total: missing")

        # Criterion 5: Formula usage (spot check key cells)
        formulas_used = 0
        formula_checks = [
            ("F2", "Duration calculation"),  # Should have formula for time difference
            ("H2", "Amount calculation"),    # Should have formula for duration × rate
            ("H5", "Acme subtotal"),        # Should have SUM formula
            ("H13", "Grand total"),         # Should have SUM formula
        ]
        
        for cell_ref, description in formula_checks:
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            if formula and formula.strip():
                formulas_used += 1
                logger.debug(f"✓ {cell_ref} ({description}) has formula: {formula}")
            else:
                logger.debug(f"✗ {cell_ref} ({description}) missing formula")
        
        if formulas_used >= 3:  # At least 3 out of 4 key cells have formulas
            criteria_passed += 1.0
            feedback_parts.append(f"✅ Formulas used appropriately ({formulas_used}/4 spot-checked)")
        elif formulas_used >= 2:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Some formulas used ({formulas_used}/4 spot-checked)")
        else:
            feedback_parts.append(f"❌ Formulas not used (only {formulas_used}/4 spot-checked cells have formulas)")

        # Criterion 6: Professional formatting (currency in amount column)
        # This is a bonus criterion - check if any amount cells look formatted
        formatting_ok = False
        sample_amount = get_cell_value(workbook, sheet_name, "H2")
        if sample_amount:
            # If value includes $ or is properly numeric, consider it formatted
            if "$" in str(sample_amount) or isinstance(sample_amount, (int, float)):
                formatting_ok = True
                criteria_passed += 0.5
                feedback_parts.append("✅ Currency formatting present")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80

        # Add summary
        if passed and score >= 95:
            feedback_parts.insert(0, "🎉 Excellent work! Invoice-ready timesheet.")
        elif passed:
            feedback_parts.insert(0, "✅ Timesheet completed successfully.")
        else:
            feedback_parts.insert(0, "❌ Timesheet incomplete or has calculation errors.")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "durations_calculated": duration_correct_count >= 6,
                "amounts_calculated": amount_correct_count >= 6,
                "subtotals_correct": subtotal_correct_count >= 2,
                "grand_total_correct": grand_total_correct,
                "formulas_used": formulas_used >= 3,
                "formatting_ok": formatting_ok
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        if temp_dir:
            cleanup_verification_temp(temp_dir)
