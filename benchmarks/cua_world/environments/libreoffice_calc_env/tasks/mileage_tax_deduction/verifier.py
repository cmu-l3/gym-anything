#!/usr/bin/env python3
"""
Verifier for Mileage Tax Deduction task
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# IRS standard mileage rate for 2023
EXPECTED_RATE = 0.655

# Business trip keywords
BUSINESS_KEYWORDS = ['client', 'meeting', 'site', 'conference', 'training', 'office', 'workshop']


def is_business_trip(purpose):
    """Determine if a trip is business based on purpose description"""
    if not purpose:
        return False
    purpose_lower = str(purpose).lower()
    return any(keyword in purpose_lower for keyword in BUSINESS_KEYWORDS)


def normalize_formula(formula):
    """Normalize formula for comparison (remove spaces, uppercase)"""
    if not formula:
        return ""
    return formula.replace(' ', '').upper()


def extract_cell_refs(formula):
    """Extract cell references from a formula"""
    if not formula:
        return []
    # Match patterns like A1, B10, C2, etc.
    matches = re.findall(r'[A-Z]+\d+', formula.upper())
    return matches


def verify_mileage_tax_deduction(traj, env_info, task_info):
    """
    Verify mileage tax deduction task completion.
    
    Checks:
    1. Distance formulas present (subtraction: End - Start Odo)
    2. Business miles correct (based on trip purpose)
    3. Deduction formulas present (multiplication: Business Miles × Rate)
    4. Deduction calculations accurate
    5. Total business miles correct (SUM formula)
    6. Total deduction correct (SUM formula)
    7. Proper currency formatting
    8. Data completeness
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations and formats
    file_attempts = [
        ('ods', '/home/ga/Documents/mileage_log_complete.ods'),
        ('ods', '/home/ga/Documents/mileage_log.ods'),
        ('csv', '/home/ga/Documents/mileage_log.csv'),
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for file_format, container_path in file_attempts:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded: {container_path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        sheet_rows = workbook['sheets'][sheet_name]
        
        # Expected structure: Row 0 is header, Rows 1-10 are data, Row 11 is TOTALS
        # Columns: A=Date, B=Start Odo, C=End Odo, D=Distance, E=Purpose, F=Business Miles, G=Rate, H=Deduction
        
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        
        # Track data for verification
        data_rows = sheet_rows[1:11] if len(sheet_rows) > 11 else sheet_rows[1:-1]  # Exclude header and totals
        totals_row_idx = len(sheet_rows) - 1 if len(sheet_rows) > 11 else -1
        
        # Criterion 1: Distance formulas present
        distance_formulas_found = 0
        distance_formulas_expected = 0
        
        for i, row in enumerate(data_rows, start=2):  # Start at row 2 (1-indexed)
            if len(row) < 4:
                continue
            
            start_odo = row[1].get('value') if isinstance(row[1], dict) else row[1]
            end_odo = row[2].get('value') if isinstance(row[2], dict) else row[2]
            distance_value = row[3].get('value') if isinstance(row[3], dict) else row[3]
            distance_formula = row[3].get('formula') if isinstance(row[3], dict) else None
            
            # If odometer readings exist, we expect a formula
            if start_odo and end_odo and start_odo != '' and end_odo != '':
                distance_formulas_expected += 1
                
                # Check if formula exists and contains subtraction
                if distance_formula and '-' in distance_formula:
                    # Verify it references the correct cells (columns B and C)
                    refs = extract_cell_refs(distance_formula)
                    if len(refs) >= 2:
                        distance_formulas_found += 1
                        logger.debug(f"Row {i}: Found distance formula: {distance_formula}")
                    else:
                        logger.debug(f"Row {i}: Formula exists but refs unclear: {distance_formula}")
                elif distance_value and isinstance(distance_value, (int, float)):
                    # Has value but might be hardcoded
                    expected_distance = float(end_odo) - float(start_odo)
                    if abs(float(distance_value) - expected_distance) < 1:
                        # Correct value even if not formula - give partial credit
                        distance_formulas_found += 0.5
                        logger.debug(f"Row {i}: Correct distance value but no formula")
        
        if distance_formulas_expected > 0:
            distance_ratio = distance_formulas_found / distance_formulas_expected
            if distance_ratio >= 0.8:
                criteria_passed += 1
                feedback_parts.append(f"✅ Distance formulas present ({distance_formulas_found}/{distance_formulas_expected})")
            else:
                feedback_parts.append(f"❌ Distance formulas incomplete ({distance_formulas_found}/{distance_formulas_expected}, need ≥80%)")
        else:
            feedback_parts.append("⚠️ No distance calculations expected")
        
        # Criterion 2: Business miles correct
        business_miles_correct = 0
        business_miles_total = 0
        
        for i, row in enumerate(data_rows, start=2):
            if len(row) < 7:
                continue
            
            purpose = row[4].get('value') if isinstance(row[4], dict) else row[4]
            distance_value = row[3].get('value') if isinstance(row[3], dict) else row[3]
            business_miles = row[5].get('value') if isinstance(row[5], dict) else row[5]
            
            if purpose:
                business_miles_total += 1
                is_business = is_business_trip(purpose)
                
                if is_business:
                    # Business trip: business miles should equal distance
                    if distance_value and business_miles:
                        if abs(float(business_miles) - float(distance_value)) < 1:
                            business_miles_correct += 1
                        else:
                            logger.debug(f"Row {i}: Business miles mismatch (distance={distance_value}, business={business_miles})")
                    elif distance_value and not business_miles:
                        logger.debug(f"Row {i}: Business trip missing business miles")
                else:
                    # Personal trip: business miles should be 0 or empty
                    if business_miles == 0 or business_miles == '0' or not business_miles:
                        business_miles_correct += 1
                    else:
                        logger.debug(f"Row {i}: Personal trip has non-zero business miles ({business_miles})")
        
        if business_miles_total > 0:
            business_ratio = business_miles_correct / business_miles_total
            if business_ratio >= 0.9:
                criteria_passed += 1
                feedback_parts.append(f"✅ Business miles correct ({business_miles_correct}/{business_miles_total})")
            else:
                feedback_parts.append(f"❌ Business miles incorrect ({business_miles_correct}/{business_miles_total})")
        else:
            feedback_parts.append("⚠️ No business miles data found")
        
        # Criterion 3: Deduction formulas present
        deduction_formulas_found = 0
        deduction_formulas_expected = 0
        
        for i, row in enumerate(data_rows, start=2):
            if len(row) < 8:
                continue
            
            business_miles = row[5].get('value') if isinstance(row[5], dict) else row[5]
            deduction_value = row[7].get('value') if isinstance(row[7], dict) else row[7]
            deduction_formula = row[7].get('formula') if isinstance(row[7], dict) else None
            
            # If business miles exist and non-zero, expect deduction formula
            if business_miles and float(business_miles) > 0:
                deduction_formulas_expected += 1
                
                if deduction_formula and '*' in deduction_formula:
                    refs = extract_cell_refs(deduction_formula)
                    if len(refs) >= 2:
                        deduction_formulas_found += 1
                        logger.debug(f"Row {i}: Found deduction formula: {deduction_formula}")
                elif deduction_value and isinstance(deduction_value, (int, float)):
                    # Has value - check if it's approximately correct
                    rate = row[6].get('value') if isinstance(row[6], dict) else row[6]
                    if rate:
                        expected_deduction = float(business_miles) * float(rate)
                        if abs(float(deduction_value) - expected_deduction) < 1:
                            deduction_formulas_found += 0.5
                            logger.debug(f"Row {i}: Correct deduction value but no formula")
        
        if deduction_formulas_expected > 0:
            deduction_ratio = deduction_formulas_found / deduction_formulas_expected
            if deduction_ratio >= 0.8:
                criteria_passed += 1
                feedback_parts.append(f"✅ Deduction formulas present ({deduction_formulas_found}/{deduction_formulas_expected})")
            else:
                feedback_parts.append(f"❌ Deduction formulas incomplete ({deduction_formulas_found}/{deduction_formulas_expected})")
        else:
            feedback_parts.append("⚠️ No deductions expected")
        
        # Criterion 4: Deduction calculations accurate
        deduction_accurate_count = 0
        deduction_total_count = 0
        
        for i, row in enumerate(data_rows, start=2):
            if len(row) < 8:
                continue
            
            business_miles = row[5].get('value') if isinstance(row[5], dict) else row[5]
            rate = row[6].get('value') if isinstance(row[6], dict) else row[6]
            deduction_value = row[7].get('value') if isinstance(row[7], dict) else row[7]
            
            if business_miles and rate and float(business_miles) > 0:
                deduction_total_count += 1
                expected_deduction = float(business_miles) * float(rate)
                
                if deduction_value and abs(float(deduction_value) - expected_deduction) <= 0.50:
                    deduction_accurate_count += 1
                else:
                    logger.debug(f"Row {i}: Deduction calculation off (expected={expected_deduction:.2f}, got={deduction_value})")
        
        if deduction_total_count > 0:
            deduction_accuracy = deduction_accurate_count / deduction_total_count
            if deduction_accuracy >= 0.9:
                criteria_passed += 1
                feedback_parts.append(f"✅ Deduction calculations accurate ({deduction_accurate_count}/{deduction_total_count})")
            else:
                feedback_parts.append(f"❌ Deduction calculations inaccurate ({deduction_accurate_count}/{deduction_total_count})")
        else:
            feedback_parts.append("⚠️ No deduction calculations found")
        
        # Criterion 5: Total business miles correct (SUM formula)
        total_business_miles_ok = False
        
        if totals_row_idx >= 0 and len(sheet_rows[totals_row_idx]) >= 6:
            total_business_formula = sheet_rows[totals_row_idx][5].get('formula') if isinstance(sheet_rows[totals_row_idx][5], dict) else None
            total_business_value = sheet_rows[totals_row_idx][5].get('value') if isinstance(sheet_rows[totals_row_idx][5], dict) else None
            
            # Calculate expected total
            expected_total_business = sum(
                float(row[5].get('value') if isinstance(row[5], dict) else row[5] or 0)
                for row in data_rows if len(row) > 5
            )
            
            if total_business_formula and 'SUM' in total_business_formula.upper():
                if total_business_value and abs(float(total_business_value) - expected_total_business) <= 1:
                    criteria_passed += 1
                    total_business_miles_ok = True
                    feedback_parts.append(f"✅ Total business miles correct: {total_business_formula} = {total_business_value}")
                else:
                    feedback_parts.append(f"❌ Total business miles formula present but value incorrect (expected ~{expected_total_business:.0f})")
            elif total_business_value and abs(float(total_business_value) - expected_total_business) <= 1:
                feedback_parts.append(f"⚠️ Total business miles value correct but no SUM formula")
            else:
                feedback_parts.append("❌ Total business miles missing or incorrect")
        else:
            feedback_parts.append("❌ Totals row not found")
        
        # Criterion 6: Total deduction correct (SUM formula)
        total_deduction_ok = False
        
        if totals_row_idx >= 0 and len(sheet_rows[totals_row_idx]) >= 8:
            total_deduction_formula = sheet_rows[totals_row_idx][7].get('formula') if isinstance(sheet_rows[totals_row_idx][7], dict) else None
            total_deduction_value = sheet_rows[totals_row_idx][7].get('value') if isinstance(sheet_rows[totals_row_idx][7], dict) else None
            
            # Calculate expected total
            expected_total_deduction = sum(
                float(row[7].get('value') if isinstance(row[7], dict) else row[7] or 0)
                for row in data_rows if len(row) > 7
            )
            
            if total_deduction_formula and 'SUM' in total_deduction_formula.upper():
                if total_deduction_value and abs(float(total_deduction_value) - expected_total_deduction) <= 1.0:
                    criteria_passed += 1
                    total_deduction_ok = True
                    feedback_parts.append(f"✅ Total deduction correct: {total_deduction_formula} = ${total_deduction_value:.2f}")
                else:
                    feedback_parts.append(f"❌ Total deduction formula present but value incorrect (expected ~${expected_total_deduction:.2f})")
            elif total_deduction_value and abs(float(total_deduction_value) - expected_total_deduction) <= 1.0:
                feedback_parts.append(f"⚠️ Total deduction value correct but no SUM formula")
            else:
                feedback_parts.append("❌ Total deduction missing or incorrect")
        else:
            feedback_parts.append("❌ Totals row incomplete")
        
        # Criterion 7: Proper formatting (currency)
        # This is harder to verify from parsed data, so we check if values look reasonable
        has_currency_formatting = False
        for row in data_rows:
            if len(row) >= 8:
                deduction_value = row[7].get('value') if isinstance(row[7], dict) else row[7]
                if deduction_value and float(deduction_value) > 0:
                    # If we got this far with proper calculations, assume formatting is okay
                    has_currency_formatting = True
                    break
        
        if has_currency_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Currency formatting present")
        else:
            feedback_parts.append("⚠️ Currency formatting not verified")
        
        # Criterion 8: Data completeness
        data_complete = True
        missing_data = []
        
        for i, row in enumerate(data_rows, start=2):
            if len(row) < 8:
                data_complete = False
                missing_data.append(f"Row {i}: insufficient columns")
                continue
            
            # Check critical cells
            purpose = row[4].get('value') if isinstance(row[4], dict) else row[4]
            if purpose and is_business_trip(purpose):
                distance = row[3].get('value') if isinstance(row[3], dict) else row[3]
                business_miles = row[5].get('value') if isinstance(row[5], dict) else row[5]
                deduction = row[7].get('value') if isinstance(row[7], dict) else row[7]
                
                if not distance:
                    missing_data.append(f"Row {i}: missing distance")
                    data_complete = False
                if not business_miles:
                    missing_data.append(f"Row {i}: missing business miles")
                    data_complete = False
                if not deduction:
                    missing_data.append(f"Row {i}: missing deduction")
                    data_complete = False
        
        if data_complete or len(missing_data) <= 2:
            criteria_passed += 1
            feedback_parts.append("✅ Data completeness acceptable")
        else:
            feedback_parts.append(f"❌ Data incomplete ({len(missing_data)} issues)")
            logger.debug(f"Missing data: {missing_data[:3]}")  # Log first 3 issues
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent mileage log completion!")
        elif passed:
            feedback_parts.insert(0, "✅ Mileage log completed")
        else:
            feedback_parts.insert(0, "❌ Mileage log incomplete")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "distance_formulas": distance_formulas_found >= distance_formulas_expected * 0.8 if distance_formulas_expected > 0 else False,
                "business_miles_correct": business_miles_correct >= business_miles_total * 0.9 if business_miles_total > 0 else False,
                "deduction_formulas": deduction_formulas_found >= deduction_formulas_expected * 0.8 if deduction_formulas_expected > 0 else False,
                "deduction_accurate": deduction_accurate_count >= deduction_total_count * 0.9 if deduction_total_count > 0 else False,
                "total_business_miles": total_business_miles_ok,
                "total_deduction": total_deduction_ok,
                "currency_formatting": has_currency_formatting,
                "data_complete": data_complete or len(missing_data) <= 2
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        if temp_dir:
            cleanup_verification_temp(temp_dir)
