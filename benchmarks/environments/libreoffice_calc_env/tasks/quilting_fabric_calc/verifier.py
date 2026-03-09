#!/usr/bin/env python3
"""
Verifier for Quilting Fabric Calculator task.

Checks that formulas are created correctly for:
1. Area calculations (length × width × quantity)
2. Shrinkage factor (5% applied)
3. Yardage conversion (accounting for fabric width)
4. Additional needs calculation (MAX function)
5. Cost calculations
6. Total sum
"""

import sys
import os
import logging
import re

# Add utils to path - use relative path for host machine verification
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_formula(formula):
    """Normalize formula for comparison by removing spaces and converting to uppercase"""
    if not formula:
        return ""
    return formula.replace(' ', '').upper()


def extract_numeric_value(value):
    """Extract numeric value from cell, handling various formats"""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    # Handle string representations
    if isinstance(value, str):
        # Remove currency symbols, commas, etc.
        cleaned = re.sub(r'[^\d.-]', '', value)
        try:
            return float(cleaned)
        except ValueError:
            return None
    return None


def check_formula_pattern(formula, required_elements):
    """
    Check if formula contains required elements.
    
    Args:
        formula: Formula string to check
        required_elements: List of elements that should be in formula (case-insensitive)
    
    Returns:
        bool: True if all required elements found
    """
    if not formula:
        return False
    
    norm_formula = normalize_formula(formula)
    
    for element in required_elements:
        norm_element = normalize_formula(element)
        if norm_element not in norm_formula:
            return False
    
    return True


def verify_fabric_calculator(traj, env_info, task_info):
    """
    Verify quilting fabric calculator task completion.
    
    Checks:
    1. Formulas present in calculation columns
    2. Area calculations correct
    3. Shrinkage factor applied (5%)
    4. Yardage conversion accurate
    5. Additional needs calculated with MAX
    6. Cost calculations correct
    7. Total sum present and reasonable
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    temp_dir = None
    success = False
    file_info = None
    
    for file_path in [
        "/home/ga/Documents/fabric_calculation.ods",
        "/home/ga/Documents/fabric_template.csv",
        "/home/ga/Documents/fabric_calculation.csv",
        "/home/ga/Documents/fabric_template.ods"
    ]:
        # Determine format from extension
        if file_path.endswith('.ods'):
            formats = ['ods']
        elif file_path.endswith('.csv'):
            formats = ['csv']
        else:
            formats = ['ods', 'csv']
        
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            file_path,
            formats
        )
        
        if success:
            logger.info(f"Successfully loaded file: {file_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet file: {error}"
        }
    
    try:
        data = file_info['sheet_data']
        temp_dir = file_info.get('temp_dir')
        
        # Get sheet data
        sheet_names = list(data.get('sheets', {}).keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = data['sheets'][sheet_name]
        
        # Initialize scoring
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        subscores = {}
        
        # Expected column mappings (approximate, may vary)
        # Assuming: A=Pattern, B=Length, C=Width, D=Quantity, E=Fabric Type, 
        #           F=Fabric Width, G=Yards Purchased, H=Price per Yard
        #           I=Area per Piece, J=Total Area, K=Area with Shrinkage,
        #           L=Yards Required, M=Additional Yards, N=Additional Cost
        
        # We'll check first data row (row 2, index 1)
        data_row_idx = 1
        
        if len(sheet_data) <= data_row_idx:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Spreadsheet has insufficient rows"
            }
        
        # Helper function to get cell by row and column index
        def get_cell_by_idx(row_idx, col_idx):
            """Get cell value and formula by row and column index (0-based)"""
            if row_idx >= len(sheet_data):
                return None, None
            row = sheet_data[row_idx]
            if col_idx >= len(row):
                return None, None
            cell = row[col_idx]
            if isinstance(cell, dict):
                return cell.get('value'), cell.get('formula')
            return cell, None
        
        # Check multiple data rows for formula presence
        formula_checks_passed = 0
        total_formula_checks = 0
        
        # Check rows 1-4 (indices 1-4, row 0 is header)
        for row_idx in range(1, min(6, len(sheet_data))):
            row = sheet_data[row_idx]
            
            # Expected input columns
            try:
                length_val = extract_numeric_value(row[1].get('value') if isinstance(row[1], dict) else row[1])
                width_val = extract_numeric_value(row[2].get('value') if isinstance(row[2], dict) else row[2])
                quantity_val = extract_numeric_value(row[3].get('value') if isinstance(row[3], dict) else row[3])
                fabric_width_val = extract_numeric_value(row[5].get('value') if isinstance(row[5], dict) else row[5])
                yards_purchased_val = extract_numeric_value(row[6].get('value') if isinstance(row[6], dict) else row[6])
                price_val = extract_numeric_value(row[7].get('value') if isinstance(row[7], dict) else row[7])
            except (IndexError, AttributeError, TypeError) as e:
                logger.warning(f"Could not extract input values from row {row_idx}: {e}")
                continue
            
            if None in [length_val, width_val, quantity_val, fabric_width_val, price_val]:
                logger.warning(f"Row {row_idx} has missing input values")
                continue
            
            # Criterion 1: Area per piece formula (col I, index 8)
            area_per_piece_val, area_per_piece_formula = get_cell_by_idx(row_idx, 8)
            if area_per_piece_formula:
                total_formula_checks += 1
                # Should be length * width
                expected_area_per_piece = length_val * width_val
                actual_area = extract_numeric_value(area_per_piece_val)
                if actual_area and abs(actual_area - expected_area_per_piece) <= 0.5:
                    formula_checks_passed += 1
            
            # Criterion 2: Total area formula (col J, index 9)
            total_area_val, total_area_formula = get_cell_by_idx(row_idx, 9)
            if total_area_formula:
                total_formula_checks += 1
                # Should be area_per_piece * quantity
                expected_total_area = length_val * width_val * quantity_val
                actual_total = extract_numeric_value(total_area_val)
                if actual_total and abs(actual_total - expected_total_area) <= 1.0:
                    formula_checks_passed += 1
            
            # Criterion 3: Shrinkage formula (col K, index 10)
            shrinkage_val, shrinkage_formula = get_cell_by_idx(row_idx, 10)
            if shrinkage_formula:
                total_formula_checks += 1
                # Should be total_area * 1.05
                expected_total_area = length_val * width_val * quantity_val
                expected_shrinkage = expected_total_area * 1.05
                actual_shrinkage = extract_numeric_value(shrinkage_val)
                if actual_shrinkage and abs(actual_shrinkage - expected_shrinkage) <= 5.0:
                    formula_checks_passed += 1
                # Check if formula contains 1.05 or multiplication
                if '1.05' in normalize_formula(shrinkage_formula) or '*1.05' in normalize_formula(shrinkage_formula):
                    formula_checks_passed += 0.5
            
            # Criterion 4: Yards required formula (col L, index 11)
            yards_req_val, yards_req_formula = get_cell_by_idx(row_idx, 11)
            if yards_req_formula:
                total_formula_checks += 1
                # Should be shrinkage_area / (fabric_width * 36)
                expected_total_area = length_val * width_val * quantity_val
                expected_shrinkage = expected_total_area * 1.05
                expected_yards = expected_shrinkage / (fabric_width_val * 36)
                actual_yards = extract_numeric_value(yards_req_val)
                if actual_yards and abs(actual_yards - expected_yards) <= 0.1:
                    formula_checks_passed += 1
            
            # Criterion 5: Additional yards formula with MAX (col M, index 12)
            additional_yards_val, additional_yards_formula = get_cell_by_idx(row_idx, 12)
            if additional_yards_formula:
                total_formula_checks += 1
                # Should contain MAX and be non-negative
                if 'MAX' in normalize_formula(additional_yards_formula):
                    formula_checks_passed += 1
                # Check value is reasonable
                actual_additional = extract_numeric_value(additional_yards_val)
                if actual_additional is not None and actual_additional >= 0:
                    formula_checks_passed += 0.5
            
            # Criterion 6: Cost calculation (col N, index 13)
            cost_val, cost_formula = get_cell_by_idx(row_idx, 13)
            if cost_formula:
                total_formula_checks += 1
                # Should be additional_yards * price
                actual_cost = extract_numeric_value(cost_val)
                if actual_cost is not None and actual_cost >= 0:
                    # Verify it's reasonable (price times some yardage)
                    if actual_cost <= price_val * 10:  # Shouldn't need more than 10 yards of any fabric
                        formula_checks_passed += 1
        
        # Score criteria based on formula checks
        if total_formula_checks > 0:
            formula_success_rate = formula_checks_passed / total_formula_checks
            
            # Criterion 1: Formulas present (at least some formulas detected)
            if formula_checks_passed > 0:
                criteria_passed += 1
                subscores['formulas_present'] = True
                feedback_parts.append("✅ Formulas detected in calculation columns")
            else:
                subscores['formulas_present'] = False
                feedback_parts.append("❌ No formulas found in calculation columns")
            
            # Criterion 2: Area calculations
            if formula_success_rate >= 0.15:  # At least 15% of checks passed
                criteria_passed += 1
                subscores['area_calculations'] = True
                feedback_parts.append("✅ Area calculations appear correct")
            else:
                subscores['area_calculations'] = False
                feedback_parts.append("❌ Area calculation formulas incorrect or missing")
            
            # Criterion 3: Shrinkage applied
            # Check if any shrinkage formula contains 1.05
            shrinkage_found = False
            for row_idx in range(1, min(6, len(sheet_data))):
                _, shrinkage_formula = get_cell_by_idx(row_idx, 10)
                if shrinkage_formula and ('1.05' in normalize_formula(shrinkage_formula) or '105' in normalize_formula(shrinkage_formula)):
                    shrinkage_found = True
                    break
            
            if shrinkage_found:
                criteria_passed += 1
                subscores['shrinkage_applied'] = True
                feedback_parts.append("✅ Shrinkage factor (5%) applied correctly")
            else:
                subscores['shrinkage_applied'] = False
                feedback_parts.append("❌ Shrinkage factor not detected in formulas")
            
            # Criterion 4: Yardage conversion
            if formula_success_rate >= 0.25:
                criteria_passed += 1
                subscores['yardage_conversion'] = True
                feedback_parts.append("✅ Yardage conversion formulas present")
            else:
                subscores['yardage_conversion'] = False
                feedback_parts.append("❌ Yardage conversion formulas missing or incorrect")
            
            # Criterion 5: MAX function for additional needs
            max_found = False
            for row_idx in range(1, min(6, len(sheet_data))):
                _, additional_formula = get_cell_by_idx(row_idx, 12)
                if additional_formula and 'MAX' in normalize_formula(additional_formula):
                    max_found = True
                    break
            
            if max_found:
                criteria_passed += 1
                subscores['max_function_used'] = True
                feedback_parts.append("✅ MAX function used for additional yards calculation")
            else:
                subscores['max_function_used'] = False
                feedback_parts.append("⚠️ MAX function not detected (additional yards may be negative)")
            
            # Criterion 6: Cost calculations
            if formula_success_rate >= 0.20:
                criteria_passed += 1
                subscores['cost_calculations'] = True
                feedback_parts.append("✅ Cost calculations present")
            else:
                subscores['cost_calculations'] = False
                feedback_parts.append("❌ Cost calculation formulas missing or incorrect")
            
            # Criterion 7: Total sum present
            # Check last few rows for a SUM formula
            sum_found = False
            total_cost_val = None
            for row_idx in range(len(sheet_data) - 3, len(sheet_data)):
                if row_idx < 0:
                    continue
                for col_idx in range(12, min(15, len(sheet_data[row_idx]) if row_idx < len(sheet_data) else 0)):
                    _, formula = get_cell_by_idx(row_idx, col_idx)
                    if formula and 'SUM' in normalize_formula(formula):
                        sum_found = True
                        val, _ = get_cell_by_idx(row_idx, col_idx)
                        total_cost_val = extract_numeric_value(val)
                        break
                if sum_found:
                    break
            
            if sum_found:
                criteria_passed += 1
                subscores['total_sum_present'] = True
                if total_cost_val is not None:
                    feedback_parts.append(f"✅ Total sum calculated: ${total_cost_val:.2f}")
                else:
                    feedback_parts.append("✅ Total sum formula present")
            else:
                subscores['total_sum_present'] = False
                feedback_parts.append("❌ Total sum not found")
            
        else:
            # No formula checks possible
            feedback_parts.append("❌ Unable to verify formulas - spreadsheet structure unexpected")
            subscores = {
                'formulas_present': False,
                'area_calculations': False,
                'shrinkage_applied': False,
                'yardage_conversion': False,
                'max_function_used': False,
                'cost_calculations': False,
                'total_sum_present': False
            }
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Need 5/7 criteria (70%)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent work! Fabric calculator completed correctly.")
        elif passed:
            feedback_parts.insert(0, "✅ Fabric calculator task completed successfully.")
        else:
            feedback_parts.insert(0, "❌ Fabric calculator incomplete - more formulas needed.")
        
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
        if temp_dir:
            cleanup_verification_temp(temp_dir)
