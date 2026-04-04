#!/usr/bin/env python3
"""
Verifier for Seed Library Viability Checker task
"""

import sys
import os
import logging
import re
from datetime import datetime
from typing import Dict, List, Tuple, Any

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_date_formula(formula: str) -> bool:
    """Check if formula contains date calculation functions"""
    if not formula:
        return False
    
    formula_upper = formula.upper()
    # Check for date functions
    date_functions = ['DATEDIF', 'TODAY', 'YEAR', 'NOW', 'DATE']
    return any(func in formula_upper for func in date_functions)


def check_conditional_formula(formula: str) -> bool:
    """Check if formula contains conditional logic (IF statements)"""
    if not formula:
        return False
    
    formula_upper = formula.upper()
    # Check for IF or IFS functions
    return 'IF' in formula_upper


def check_lookup_formula(formula: str) -> bool:
    """Check if formula contains lookup functions"""
    if not formula:
        return False
    
    formula_upper = formula.upper()
    # Check for lookup functions
    lookup_functions = ['VLOOKUP', 'HLOOKUP', 'INDEX', 'MATCH', 'XLOOKUP']
    return any(func in formula_upper for func in lookup_functions)


def check_sheet_reference(formula: str, reference_sheet_name: str) -> bool:
    """Check if formula references the seed lifespan reference sheet"""
    if not formula:
        return False
    
    # Check for sheet reference patterns
    patterns = [
        reference_sheet_name,
        reference_sheet_name.replace('_', ' '),
        'Seed_Lifespan',
        'Lifespan',
        'Reference'
    ]
    
    return any(pattern.lower() in formula.lower() for pattern in patterns)


def calculate_expected_age(collection_date: str) -> int:
    """Calculate expected age in years from collection date"""
    try:
        # Try various date formats
        for fmt in ['%Y-%m-%d', '%Y/%m/%d', '%m/%d/%Y', '%d/%m/%Y']:
            try:
                date_obj = datetime.strptime(collection_date, fmt)
                today = datetime.now()
                age_years = (today - date_obj).days / 365.25
                return int(age_years)
            except ValueError:
                continue
        return None
    except Exception as e:
        logger.debug(f"Could not parse date {collection_date}: {e}")
        return None


def determine_expected_status(age: int, seed_type: str, reference_data: Dict) -> str:
    """Determine expected viability status based on age and seed type"""
    # Find the seed type in reference data
    for row in reference_data:
        if len(row) >= 3 and row[0].get('value', '').lower() == seed_type.lower():
            try:
                min_viable = int(float(row[1].get('value', 0)))
                max_viable = int(float(row[2].get('value', 0)))
                
                if age < min_viable:
                    return "Good"
                elif age < max_viable:
                    return "Test"
                else:
                    return "Discard"
            except (ValueError, TypeError):
                pass
    
    return None


def verify_seed_viability(traj, env_info, task_info):
    """
    Verify seed viability checker task completion.
    
    Checks:
    1. Age_Years column contains date formulas
    2. Viability_Status contains conditional logic
    3. Formulas reference the Seed_Lifespan_Reference sheet
    4. Conditional formatting applied to status column
    5. No formula errors
    6. Spot check accuracy (compare calculated vs expected results)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to find the saved file
    paths_to_try = [
        "/home/ga/Documents/seed_viability_checked.ods",
        "/home/ga/Documents/seed_inventory.ods",
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for container_path in paths_to_try:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format='ods'
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
        # Get sheet names
        sheet_names = list(workbook['sheets'].keys())
        if len(sheet_names) < 2:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Spreadsheet must have 2 sheets (Seed_Inventory and Seed_Lifespan_Reference)"
            }
        
        inventory_sheet = sheet_names[0]  # First sheet should be Seed_Inventory
        reference_sheet = sheet_names[1]  # Second sheet should be reference data
        
        inventory_data = workbook['sheets'][inventory_sheet]
        reference_data = workbook['sheets'][reference_sheet]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Determine column indices (assuming header row is first)
        header_row = inventory_data[0] if len(inventory_data) > 0 else []
        
        # Find Age_Years and Viability_Status columns
        age_col_idx = None
        status_col_idx = None
        seed_type_col_idx = None
        collection_date_col_idx = None
        
        for idx, cell in enumerate(header_row):
            cell_value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
            if 'age' in cell_value.lower():
                age_col_idx = idx
            elif 'viability' in cell_value.lower() or 'status' in cell_value.lower():
                status_col_idx = idx
            elif 'seed_type' in cell_value.lower() or cell_value.lower() == 'seed type':
                seed_type_col_idx = idx
            elif 'collection' in cell_value.lower() or 'date' in cell_value.lower():
                if collection_date_col_idx is None:  # Take first date column
                    collection_date_col_idx = idx
        
        if age_col_idx is None or status_col_idx is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not find Age_Years or Viability_Status columns. Ensure column headers are present."
            }
        
        # Criterion 1: Check Age_Years column has date formulas
        age_formulas_found = 0
        age_formulas_with_date_functions = 0
        data_rows = inventory_data[1:21]  # Check first 20 data rows
        
        for row_idx, row in enumerate(data_rows):
            if len(row) > age_col_idx:
                cell_data = row[age_col_idx]
                formula = cell_data.get('formula') if isinstance(cell_data, dict) else None
                
                if formula:
                    age_formulas_found += 1
                    if check_date_formula(formula):
                        age_formulas_with_date_functions += 1
        
        if age_formulas_with_date_functions >= 15:  # At least 15/20 rows
            criteria_passed += 1
            feedback_parts.append(f"✅ Age calculation formulas present ({age_formulas_with_date_functions} rows with date formulas)")
        else:
            feedback_parts.append(f"❌ Age_Years column missing date formulas (found {age_formulas_with_date_functions}/20, need 15+)")
        
        # Criterion 2: Check Viability_Status has conditional logic
        status_formulas_found = 0
        status_with_conditionals = 0
        status_with_lookups = 0
        
        for row_idx, row in enumerate(data_rows):
            if len(row) > status_col_idx:
                cell_data = row[status_col_idx]
                formula = cell_data.get('formula') if isinstance(cell_data, dict) else None
                
                if formula:
                    status_formulas_found += 1
                    if check_conditional_formula(formula):
                        status_with_conditionals += 1
                    if check_lookup_formula(formula) or check_sheet_reference(formula, reference_sheet):
                        status_with_lookups += 1
        
        if status_with_conditionals >= 15:
            criteria_passed += 1
            feedback_parts.append(f"✅ Viability status uses conditional logic ({status_with_conditionals} rows with IF statements)")
        else:
            feedback_parts.append(f"❌ Viability_Status missing conditional logic (found {status_with_conditionals}/20, need 15+)")
        
        # Criterion 3: Check formulas reference the reference sheet
        if status_with_lookups >= 15:
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas reference seed lifespan data ({status_with_lookups} rows with lookups)")
        else:
            feedback_parts.append(f"❌ Formulas don't reference Seed_Lifespan_Reference sheet (found {status_with_lookups}/20, need 15+)")
        
        # Criterion 4: Check for conditional formatting
        # Note: This is a simplified check - full ODS conditional formatting parsing is complex
        try:
            has_conditional_formatting = check_conditional_formatting(workbook, inventory_sheet, f"H2:H21")
            if has_conditional_formatting:
                criteria_passed += 1
                feedback_parts.append("✅ Conditional formatting detected in Viability_Status column")
            else:
                feedback_parts.append("⚠️ Conditional formatting not detected (may not be critical)")
                # Give partial credit if formulas are correct
                if status_with_conditionals >= 15:
                    criteria_passed += 0.5
        except Exception as e:
            logger.debug(f"Could not check conditional formatting: {e}")
            feedback_parts.append("⚠️ Could not verify conditional formatting")
            # Give benefit of doubt if formulas are correct
            if status_with_conditionals >= 15:
                criteria_passed += 0.5
        
        # Criterion 5: Check for no formula errors
        has_errors = False
        error_count = 0
        
        for row_idx, row in enumerate(data_rows):
            for col_idx in [age_col_idx, status_col_idx]:
                if len(row) > col_idx:
                    cell_data = row[col_idx]
                    value = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
                    
                    if isinstance(value, str) and any(err in str(value).upper() for err in ['#REF!', '#VALUE!', '#DIV/0!', '#N/A', '#NAME?', '#NULL!']):
                        has_errors = True
                        error_count += 1
        
        if not has_errors:
            criteria_passed += 1
            feedback_parts.append("✅ No formula errors detected")
        else:
            feedback_parts.append(f"❌ Formula errors found ({error_count} cells with errors)")
        
        # Criterion 6: Spot check accuracy
        spot_checks_passed = 0
        spot_checks_total = 0
        
        # Validate a few specific seeds
        for row_idx, row in enumerate(data_rows[:10]):  # Check first 10 seeds
            if len(row) > max(age_col_idx, status_col_idx, collection_date_col_idx or 0, seed_type_col_idx or 0):
                # Get collection date
                collection_date_cell = row[collection_date_col_idx] if collection_date_col_idx is not None else None
                collection_date = None
                if collection_date_cell:
                    collection_date = collection_date_cell.get('value') if isinstance(collection_date_cell, dict) else collection_date_cell
                
                # Get seed type
                seed_type_cell = row[seed_type_col_idx] if seed_type_col_idx is not None else None
                seed_type = None
                if seed_type_cell:
                    seed_type = seed_type_cell.get('value') if isinstance(seed_type_cell, dict) else seed_type_cell
                
                # Get calculated age
                age_cell = row[age_col_idx]
                calculated_age = age_cell.get('value') if isinstance(age_cell, dict) else age_cell
                
                # Get status
                status_cell = row[status_col_idx]
                calculated_status = status_cell.get('value') if isinstance(status_cell, dict) else status_cell
                
                if collection_date and seed_type and calculated_age is not None and calculated_status:
                    spot_checks_total += 1
                    
                    # Calculate expected age
                    expected_age = calculate_expected_age(str(collection_date))
                    
                    if expected_age is not None:
                        # Check age is within reasonable range (±1 year tolerance)
                        try:
                            age_val = int(float(calculated_age))
                            if abs(age_val - expected_age) <= 1:
                                # Age is correct, check status
                                expected_status = determine_expected_status(age_val, str(seed_type), reference_data)
                                
                                if expected_status and str(calculated_status).strip().lower() == expected_status.lower():
                                    spot_checks_passed += 1
                        except (ValueError, TypeError):
                            pass
        
        if spot_checks_total > 0:
            accuracy_rate = spot_checks_passed / spot_checks_total
            if accuracy_rate >= 0.7:  # 70% accuracy
                criteria_passed += 1
                feedback_parts.append(f"✅ Spot checks passed ({spot_checks_passed}/{spot_checks_total} accurate)")
            else:
                feedback_parts.append(f"❌ Spot checks failed ({spot_checks_passed}/{spot_checks_total} accurate, need {int(0.7 * spot_checks_total)}+)")
        else:
            feedback_parts.append("⚠️ Could not perform spot checks (insufficient data)")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (4/6 criteria)
        
        if passed and score >= 90:
            feedback_parts.append("🌱 Excellent! Seed viability assessment complete!")
        elif passed:
            feedback_parts.append("✅ Seed viability task completed successfully")
        else:
            feedback_parts.append("❌ Task requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "age_formulas": age_formulas_with_date_functions >= 15,
                "conditional_logic": status_with_conditionals >= 15,
                "reference_data_used": status_with_lookups >= 15,
                "conditional_formatting": has_conditional_formatting if 'has_conditional_formatting' in locals() else False,
                "no_errors": not has_errors,
                "spot_checks": spot_checks_passed / spot_checks_total if spot_checks_total > 0 else 0
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
