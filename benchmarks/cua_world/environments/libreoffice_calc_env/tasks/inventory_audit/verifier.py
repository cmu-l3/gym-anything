#!/usr/bin/env python3
"""
Verifier for Inventory Audit Reconciliation task.

Checks:
1. Difference formulas in column E (=C-B)
2. Value Impact formulas in column F (=E*D or =D*E)
3. Formulas present in most/all data rows
4. Conditional formatting applied
5. Mathematical accuracy
"""

import sys
import os
import logging
import re
import random
import zipfile
from xml.etree import ElementTree as ET

# Use relative path to utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_formula(formula):
    """Normalize formula by removing spaces and converting to uppercase"""
    if not formula:
        return ""
    return formula.replace(" ", "").upper()


def check_difference_formula(formula, row_num):
    """
    Check if formula matches expected pattern for difference calculation.
    Expected: =C{row}-B{row} (Actual - Expected)
    Also accepts with $ signs for absolute references
    """
    if not formula:
        return False
    
    normalized = normalize_formula(formula)
    
    # Pattern variations to accept
    patterns = [
        f"=C{row_num}-B{row_num}",
        f"=$C{row_num}-$B{row_num}",
        f"=$C${row_num}-$B${row_num}",
        f"=C{row_num}-B{row_num}",
    ]
    
    for pattern in patterns:
        if normalized == normalize_formula(pattern):
            return True
    
    # Also accept if it's a valid subtraction of columns C and B
    # using regex for more flexibility
    pattern_regex = rf"^=\$?C\$?{row_num}-\$?B\$?{row_num}$"
    if re.match(pattern_regex, normalized):
        return True
    
    return False


def check_value_impact_formula(formula, row_num):
    """
    Check if formula matches expected pattern for value impact calculation.
    Expected: =E{row}*D{row} or =D{row}*E{row} (Difference × Unit Price)
    """
    if not formula:
        return False
    
    normalized = normalize_formula(formula)
    
    # Pattern variations (multiplication is commutative)
    patterns = [
        f"=E{row_num}*D{row_num}",
        f"=D{row_num}*E{row_num}",
        f"=$E{row_num}*$D{row_num}",
        f"=$D{row_num}*$E{row_num}",
        f"=$E${row_num}*$D${row_num}",
        f"=$D${row_num}*$E${row_num}",
    ]
    
    for pattern in patterns:
        if normalized == normalize_formula(pattern):
            return True
    
    # Regex for flexibility
    pattern_regex_1 = rf"^=\$?E\$?{row_num}\*\$?D\$?{row_num}$"
    pattern_regex_2 = rf"^=\$?D\$?{row_num}\*\$?E\$?{row_num}$"
    
    if re.match(pattern_regex_1, normalized) or re.match(pattern_regex_2, normalized):
        return True
    
    return False


def check_conditional_formatting_ods(filepath):
    """
    Check if conditional formatting exists in the ODS file.
    ODS stores conditional formatting in styles and table cells.
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            # Check content.xml for conditional formatting
            if 'content.xml' not in ods_zip.namelist():
                return False
            
            content_xml = ods_zip.read('content.xml')
            content_str = content_xml.decode('utf-8', errors='ignore')
            
            # Look for conditional formatting indicators in ODS
            # ODS uses style:map elements for conditional formatting
            cf_indicators = [
                'style:map',
                'style:condition',
                'conditional-format',
                'apply-style-name',
            ]
            
            for indicator in cf_indicators:
                if indicator in content_str:
                    logger.info(f"Found conditional formatting indicator: {indicator}")
                    return True
            
            # Also check styles.xml
            if 'styles.xml' in ods_zip.namelist():
                styles_xml = ods_zip.read('styles.xml')
                styles_str = styles_xml.decode('utf-8', errors='ignore')
                
                for indicator in cf_indicators:
                    if indicator in content_str:
                        logger.info(f"Found conditional formatting in styles: {indicator}")
                        return True
        
        return False
    
    except Exception as e:
        logger.warning(f"Could not check conditional formatting: {e}")
        return False


def spot_check_calculations(data, sheet_name, num_samples=5):
    """
    Randomly sample rows and verify calculations are mathematically correct.
    """
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False, "Sheet not found"
        
        rows = sheets[sheet_name]
        
        # Skip header row
        data_rows = rows[1:] if len(rows) > 1 else []
        
        if len(data_rows) < num_samples:
            num_samples = len(data_rows)
        
        if num_samples == 0:
            return False, "No data rows found"
        
        # Sample random rows
        sample_indices = random.sample(range(len(data_rows)), num_samples)
        
        errors = []
        
        for idx in sample_indices:
            row = data_rows[idx]
            row_num = idx + 2  # +2 because: +1 for 0-indexing, +1 for header
            
            # Columns: A=Product, B=Expected, C=Actual, D=UnitPrice, E=Difference, F=ValueImpact
            if len(row) < 6:
                continue
            
            try:
                expected_qty = row[1].get('value') if isinstance(row[1], dict) else row[1]
                actual_qty = row[2].get('value') if isinstance(row[2], dict) else row[2]
                unit_price = row[3].get('value') if isinstance(row[3], dict) else row[3]
                difference = row[4].get('value') if isinstance(row[4], dict) else row[4]
                value_impact = row[5].get('value') if isinstance(row[5], dict) else row[5]
                
                # Convert to numbers
                expected_qty = float(expected_qty) if expected_qty is not None else 0
                actual_qty = float(actual_qty) if actual_qty is not None else 0
                unit_price = float(unit_price) if unit_price is not None else 0
                
                # Calculate expected values
                expected_diff = actual_qty - expected_qty
                expected_impact = expected_diff * unit_price
                
                # Verify with tolerance
                if difference is not None:
                    difference = float(difference)
                    if abs(difference - expected_diff) > 0.01:
                        errors.append(f"Row {row_num}: Difference incorrect ({difference} vs expected {expected_diff})")
                
                if value_impact is not None:
                    value_impact = float(value_impact)
                    if abs(value_impact - expected_impact) > 0.01:
                        errors.append(f"Row {row_num}: Value impact incorrect ({value_impact} vs expected {expected_impact})")
            
            except (ValueError, TypeError, AttributeError) as e:
                logger.debug(f"Could not verify row {row_num}: {e}")
                continue
        
        if errors:
            return False, "; ".join(errors)
        
        return True, ""
    
    except Exception as e:
        logger.error(f"Error in spot check: {e}", exc_info=True)
        return False, str(e)


def verify_inventory_audit(traj, env_info, task_info):
    """
    Verify inventory audit reconciliation task completion.
    
    Checks:
    1. Difference formulas present in column E
    2. Value impact formulas present in column F
    3. Formulas in most/all rows (>80%)
    4. Conditional formatting applied
    5. Mathematical accuracy (spot check)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    container_paths = [
        "/home/ga/Documents/inventory_reconciliation.ods",
        "/home/ga/Documents/inventory_data.csv",
        "/home/ga/Documents/inventory_data.ods",
    ]
    
    success = False
    file_info = None
    
    for container_path in container_paths:
        file_format = 'ods' if container_path.endswith('.ods') else 'csv'
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            container_path,
            [file_format]
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
        data = file_info['sheet_data']
        filepath = file_info['file_path']
        
        # Get first sheet
        sheet_names = list(data.get('sheets', {}).keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        rows = data['sheets'][sheet_name]
        
        # We expect header + 45 data rows = 46 rows total
        # But be flexible in case some rows are missing
        data_rows = rows[1:] if len(rows) > 1 else []
        total_data_rows = len(data_rows)
        
        if total_data_rows < 10:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Insufficient data rows found: {total_data_rows}"
            }
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: Check Difference formulas in column E
        diff_formulas_count = 0
        diff_formulas_correct = 0
        
        for i, row in enumerate(data_rows):
            row_num = i + 2  # +2 for header and 0-indexing
            if len(row) >= 5:  # At least up to column E
                formula = get_cell_formula(data, sheet_name, f'E{row_num}')
                if formula:
                    diff_formulas_count += 1
                    if check_difference_formula(formula, row_num):
                        diff_formulas_correct += 1
        
        diff_formula_coverage = diff_formulas_count / total_data_rows if total_data_rows > 0 else 0
        diff_formula_accuracy = diff_formulas_correct / diff_formulas_count if diff_formulas_count > 0 else 0
        
        if diff_formula_coverage >= 0.8 and diff_formula_accuracy >= 0.8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Difference formulas present ({diff_formulas_correct}/{total_data_rows} rows)")
        elif diff_formula_coverage >= 0.5:
            feedback_parts.append(f"⚠️ Partial difference formulas ({diff_formulas_correct}/{total_data_rows} rows)")
        else:
            feedback_parts.append(f"❌ Missing difference formulas (only {diff_formulas_correct}/{total_data_rows} rows)")
        
        # Criterion 2: Check Value Impact formulas in column F
        impact_formulas_count = 0
        impact_formulas_correct = 0
        
        for i, row in enumerate(data_rows):
            row_num = i + 2
            if len(row) >= 6:  # At least up to column F
                formula = get_cell_formula(data, sheet_name, f'F{row_num}')
                if formula:
                    impact_formulas_count += 1
                    if check_value_impact_formula(formula, row_num):
                        impact_formulas_correct += 1
        
        impact_formula_coverage = impact_formulas_count / total_data_rows if total_data_rows > 0 else 0
        impact_formula_accuracy = impact_formulas_correct / impact_formulas_count if impact_formulas_count > 0 else 0
        
        if impact_formula_coverage >= 0.8 and impact_formula_accuracy >= 0.8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Value impact formulas present ({impact_formulas_correct}/{total_data_rows} rows)")
        elif impact_formula_coverage >= 0.5:
            feedback_parts.append(f"⚠️ Partial value impact formulas ({impact_formulas_correct}/{total_data_rows} rows)")
        else:
            feedback_parts.append(f"❌ Missing value impact formulas (only {impact_formulas_correct}/{total_data_rows} rows)")
        
        # Criterion 3: Overall formula coverage (at least 80% of rows)
        total_formulas = diff_formulas_correct + impact_formulas_correct
        max_possible_formulas = total_data_rows * 2
        overall_coverage = total_formulas / max_possible_formulas if max_possible_formulas > 0 else 0
        
        if overall_coverage >= 0.8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas in most rows ({int(overall_coverage*100)}% coverage)")
        elif overall_coverage >= 0.5:
            feedback_parts.append(f"⚠️ Partial formula coverage ({int(overall_coverage*100)}%)")
        else:
            feedback_parts.append(f"❌ Insufficient formula coverage ({int(overall_coverage*100)}%)")
        
        # Criterion 4: Check conditional formatting
        has_conditional_formatting = check_conditional_formatting_ods(filepath)
        
        if has_conditional_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting detected")
        else:
            feedback_parts.append("❌ No conditional formatting found")
        
        # Criterion 5: Spot-check mathematical accuracy
        calc_correct, calc_error = spot_check_calculations(data, sheet_name, num_samples=5)
        
        if calc_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Calculations mathematically correct")
        else:
            feedback_parts.append(f"❌ Calculation errors detected: {calc_error}")
        
        # Criterion 6: Check that original data is preserved (columns A-D intact)
        data_preserved = True
        for i in range(min(5, total_data_rows)):  # Check first 5 rows
            row_num = i + 2
            product_name = get_cell_value(data, sheet_name, f'A{row_num}')
            expected_qty = get_cell_value(data, sheet_name, f'B{row_num}')
            actual_count = get_cell_value(data, sheet_name, f'C{row_num}')
            unit_price = get_cell_value(data, sheet_name, f'D{row_num}')
            
            if not all([product_name, expected_qty is not None, actual_count is not None, unit_price is not None]):
                data_preserved = False
                break
        
        if data_preserved:
            criteria_passed += 1
            feedback_parts.append("✅ Original inventory data preserved")
        else:
            feedback_parts.append("❌ Original data appears corrupted")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (need 5/6 criteria)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent inventory reconciliation!")
        elif passed:
            feedback_parts.insert(0, "✅ Inventory audit completed")
        else:
            feedback_parts.insert(0, "❌ Inventory audit incomplete")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "difference_formulas": diff_formula_coverage >= 0.8 and diff_formula_accuracy >= 0.8,
                "value_impact_formulas": impact_formula_coverage >= 0.8 and impact_formula_accuracy >= 0.8,
                "formula_coverage": overall_coverage >= 0.8,
                "conditional_formatting": has_conditional_formatting,
                "calculations_correct": calc_correct,
                "data_preserved": data_preserved
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
        cleanup_verification_temp(file_info.get('temp_dir'))
