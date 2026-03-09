#!/usr/bin/env python3
"""
Verifier for Fair Rent Split Calculator task.

Checks:
1. Formulas are present (not hardcoded values)
2. Total rent matches sum of individual rents
3. Higher weighted scores result in higher rents (proportional logic)
4. Mathematical consistency (proportions sum to ~1.0)
5. Reasonable distribution (no extreme outliers)
"""

import sys
import os
import logging
import re

# Add utils to path - use relative path for host machine
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

TOTAL_RENT = 3200.0
RENT_TOLERANCE = 5.0  # $5 tolerance for rounding
PROPORTION_TOLERANCE = 0.02  # 2% tolerance for proportions
MIN_RENT_PERCENTAGE = 0.15  # No room should be less than 15% of total
MAX_RENT_PERCENTAGE = 0.40  # No room should exceed 40% of total


def extract_numeric_value(value):
    """Extract numeric value from cell, handling various formats."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        # Remove currency symbols, commas, etc.
        cleaned = re.sub(r'[^\d.-]', '', value)
        try:
            return float(cleaned) if cleaned else None
        except ValueError:
            return None
    return None


def check_formula_presence(formula_value):
    """Check if a cell contains a formula (not just a static value)."""
    if formula_value is None:
        return False
    if isinstance(formula_value, str):
        # Formulas typically start with '=' or contain function names
        formula_upper = formula_value.upper()
        return (formula_value.startswith('=') or 
                'SUM' in formula_upper or 
                'IF' in formula_upper or
                'AVERAGE' in formula_upper or
                '*' in formula_value or
                '/' in formula_value or
                '+' in formula_value)
    return False


def verify_rent_split(traj, env_info, task_info):
    """
    Verify rent split calculator task completion.
    
    Checks multiple criteria:
    1. Formulas present in weighted score column
    2. Total rent matches sum of individual rents
    3. Proportional logic (higher scores = higher rents)
    4. Mathematical consistency
    5. Reasonable distribution
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    temp_dir = None
    success = False
    workbook = None
    
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/rent_split_result.ods'),
        ('ods', '/home/ga/Documents/rent_split_data.ods'),
        ('csv', '/home/ga/Documents/rent_split_data.csv')
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
            "feedback": f"Could not load spreadsheet file: {error}"
        }

    try:
        # Get first sheet
        sheets = get_sheet_names(workbook)
        if not sheets:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheets[0]
        logger.info(f"Analyzing sheet: {sheet_name}")

        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        subscores = {}

        # Extract data from expected cells
        # Assuming data is in rows 2-5 (after header in row 1)
        # Columns: A=Name, B=Room, C=SqFt, D=Bath, E=Parking, F=Floor, G=Light,
        #          H=WeightedScore, I=Proportion, J=MonthlyRent
        
        room_data = []
        for row in range(2, 6):  # Rows 2-5 for 4 rooms
            room_info = {
                'row': row,
                'name': get_cell_value(workbook, sheet_name, f'A{row}'),
                'sq_ft': get_cell_value(workbook, sheet_name, f'C{row}'),
                'weighted_score': extract_numeric_value(get_cell_value(workbook, sheet_name, f'H{row}')),
                'weighted_formula': get_cell_formula(workbook, sheet_name, f'H{row}'),
                'rent_proportion': extract_numeric_value(get_cell_value(workbook, sheet_name, f'I{row}')),
                'proportion_formula': get_cell_formula(workbook, sheet_name, f'I{row}'),
                'monthly_rent': extract_numeric_value(get_cell_value(workbook, sheet_name, f'J{row}')),
                'rent_formula': get_cell_formula(workbook, sheet_name, f'J{row}')
            }
            room_data.append(room_info)
            logger.debug(f"Row {row} data: {room_info}")

        # Criterion 1: Check for formulas in weighted score column
        formulas_present = 0
        for room in room_data:
            if check_formula_presence(room['weighted_formula']):
                formulas_present += 1
        
        if formulas_present >= 3:  # At least 3 out of 4 rooms should have formulas
            criteria_passed += 1
            subscores['formulas_present'] = True
            feedback_parts.append(f"✅ Formulas present in weighted score column ({formulas_present}/4 rooms)")
        else:
            subscores['formulas_present'] = False
            feedback_parts.append(f"❌ Missing formulas in weighted score column (only {formulas_present}/4 rooms)")

        # Criterion 2: Total rent matches
        total_rent_calculated = sum(
            room['monthly_rent'] for room in room_data 
            if room['monthly_rent'] is not None
        )
        
        rent_match = abs(total_rent_calculated - TOTAL_RENT) <= RENT_TOLERANCE
        if rent_match:
            criteria_passed += 1
            subscores['total_rent_match'] = True
            feedback_parts.append(f"✅ Total rent matches: ${total_rent_calculated:.2f} ≈ ${TOTAL_RENT}")
        else:
            subscores['total_rent_match'] = False
            feedback_parts.append(f"❌ Total rent mismatch: ${total_rent_calculated:.2f} ≠ ${TOTAL_RENT}")

        # Criterion 3: Proportional logic - higher scores should mean higher rents
        # Check correlation between weighted scores and rents
        valid_rooms = [
            room for room in room_data 
            if room['weighted_score'] is not None and room['monthly_rent'] is not None
        ]
        
        if len(valid_rooms) >= 3:
            # Sort by weighted score and by rent
            sorted_by_score = sorted(valid_rooms, key=lambda x: x['weighted_score'])
            sorted_by_rent = sorted(valid_rooms, key=lambda x: x['monthly_rent'])
            
            # Check if order is generally preserved (some flexibility allowed)
            order_matches = 0
            for i, room_by_score in enumerate(sorted_by_score):
                for j, room_by_rent in enumerate(sorted_by_rent):
                    if room_by_score['row'] == room_by_rent['row']:
                        # Allow ±1 position difference
                        if abs(i - j) <= 1:
                            order_matches += 1
                        break
            
            proportional_logic = order_matches >= len(valid_rooms) - 1
            if proportional_logic:
                criteria_passed += 1
                subscores['proportional_logic'] = True
                feedback_parts.append("✅ Proportional logic: higher scores result in higher rents")
            else:
                subscores['proportional_logic'] = False
                feedback_parts.append("❌ Proportional logic broken: rent not proportional to scores")
        else:
            subscores['proportional_logic'] = False
            feedback_parts.append(f"⚠️ Insufficient data to verify proportional logic ({len(valid_rooms)} valid rooms)")

        # Criterion 4: Mathematical consistency - proportions sum to ~1.0
        total_proportions = sum(
            room['rent_proportion'] for room in room_data 
            if room['rent_proportion'] is not None
        )
        
        if total_proportions > 0:
            proportions_consistent = abs(total_proportions - 1.0) <= PROPORTION_TOLERANCE
            if proportions_consistent:
                criteria_passed += 1
                subscores['proportions_consistent'] = True
                feedback_parts.append(f"✅ Proportions sum correctly: {total_proportions:.4f} ≈ 1.0")
            else:
                subscores['proportions_consistent'] = False
                feedback_parts.append(f"❌ Proportions don't sum to 1.0: {total_proportions:.4f}")
        else:
            subscores['proportions_consistent'] = False
            feedback_parts.append("❌ No valid proportions found")

        # Criterion 5: Reasonable distribution - no extreme outliers
        if total_rent_calculated > 0:
            all_reasonable = True
            for room in room_data:
                if room['monthly_rent'] is not None:
                    rent_percentage = room['monthly_rent'] / total_rent_calculated
                    if rent_percentage < MIN_RENT_PERCENTAGE or rent_percentage > MAX_RENT_PERCENTAGE:
                        all_reasonable = False
                        feedback_parts.append(
                            f"⚠️ Room {room['name']}: ${room['monthly_rent']:.2f} "
                            f"({rent_percentage*100:.1f}%) outside reasonable range (15-40%)"
                        )
                        break
            
            if all_reasonable:
                criteria_passed += 1
                subscores['reasonable_distribution'] = True
                feedback_parts.append("✅ Rent distribution is reasonable (no extreme outliers)")
            else:
                subscores['reasonable_distribution'] = False
                if "⚠️" not in " ".join(feedback_parts):
                    feedback_parts.append("❌ Rent distribution has extreme outliers")
        else:
            subscores['reasonable_distribution'] = False
            feedback_parts.append("❌ Cannot verify distribution (no valid rent data)")

        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 4/5 criteria
        
        # Add summary
        if passed and score >= 95:
            feedback_parts.insert(0, "🎉 Excellent rent split calculation!")
        elif passed:
            feedback_parts.insert(0, "✅ Rent split calculation successful")
        else:
            feedback_parts.insert(0, f"❌ Rent split incomplete ({criteria_passed}/{total_criteria} criteria met)")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "criteria_passed": criteria_passed,
                "total_criteria": total_criteria,
                "total_rent_calculated": total_rent_calculated,
                "formulas_detected": formulas_present
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }

    finally:
        cleanup_verification_temp(temp_dir)
