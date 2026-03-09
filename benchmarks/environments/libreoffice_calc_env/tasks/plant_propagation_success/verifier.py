#!/usr/bin/env python3
"""
Verifier for Plant Propagation Success Analyzer task.
Checks data cleaning, success rate calculations, duration analysis, and summary creation.
"""

import sys
import os
import logging
import re
from typing import Dict, Any, List, Tuple

# Do not use /workspace/utils, since verification runs on host machine
# Use relative path to utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_date_standardization(sheet_data: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if dates have been standardized.
    Look for DATE/DATEVALUE functions or converted date values.
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        # Look for date-related formulas or date type values
        date_formula_found = False
        date_conversion_found = False
        
        for row_idx, row in enumerate(rows[:50]):  # Check first 50 rows
            for col_idx, cell in enumerate(row[:15]):  # Check first 15 columns
                if isinstance(cell, dict):
                    formula = cell.get('formula', '')
                    value = cell.get('value')
                    cell_type = cell.get('type', '')
                    
                    # Check for date functions
                    if formula and isinstance(formula, str):
                        formula_upper = formula.upper()
                        if any(func in formula_upper for func in ['DATEVALUE', 'DATE(', 'VALUE(']):
                            date_formula_found = True
                            logger.info(f"Found date formula at row {row_idx}, col {col_idx}: {formula}")
                    
                    # Check for date type values (assuming conversion happened)
                    if cell_type and 'date' in cell_type.lower():
                        date_conversion_found = True
        
        if date_formula_found:
            return True, "Date standardization formulas found (DATEVALUE/DATE)"
        elif date_conversion_found:
            return True, "Date type values found (dates appear standardized)"
        else:
            return False, "No date standardization detected"
            
    except Exception as e:
        logger.error(f"Error checking date standardization: {e}", exc_info=True)
        return False, f"Error checking dates: {str(e)}"


def check_success_determination(sheet_data: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if success/failure has been determined from outcome text.
    Look for IF + SEARCH/FIND logic or a column with success/failure indicators.
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        success_formula_found = False
        success_column_found = False
        
        for row_idx, row in enumerate(rows[:50]):
            for col_idx, cell in enumerate(row[:20]):
                if isinstance(cell, dict):
                    formula = cell.get('formula', '')
                    value = cell.get('value')
                    
                    # Check for logic formulas
                    if formula and isinstance(formula, str):
                        formula_upper = formula.upper()
                        # Look for IF + text search functions
                        if 'IF' in formula_upper and any(func in formula_upper for func in ['SEARCH', 'FIND', 'ISNUMBER']):
                            success_formula_found = True
                            logger.info(f"Found success determination formula at row {row_idx}, col {col_idx}")
                    
                    # Check for success/failure indicators in values
                    if value and isinstance(value, str):
                        value_lower = value.lower()
                        if value_lower in ['success', 'failure', 'failed', 'pass', 'fail', 'yes', 'no']:
                            success_column_found = True
        
        if success_formula_found:
            return True, "Success determination logic found (IF + text search)"
        elif success_column_found:
            return True, "Success/failure column found"
        else:
            return False, "No success determination detected"
            
    except Exception as e:
        logger.error(f"Error checking success determination: {e}", exc_info=True)
        return False, f"Error: {str(e)}"


def check_duration_calculation(sheet_data: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if rooting duration has been calculated.
    Look for DAYS function or date subtraction.
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        duration_formula_found = False
        duration_values_found = False
        
        for row_idx, row in enumerate(rows[:50]):
            for col_idx, cell in enumerate(row[:20]):
                if isinstance(cell, dict):
                    formula = cell.get('formula', '')
                    value = cell.get('value')
                    
                    # Check for duration formulas
                    if formula and isinstance(formula, str):
                        formula_upper = formula.upper()
                        if 'DAYS' in formula_upper or ('-' in formula and any(ref in formula_upper for ref in ['A', 'B', 'C', 'D', 'E'])):
                            duration_formula_found = True
                            logger.info(f"Found duration formula at row {row_idx}, col {col_idx}: {formula}")
                    
                    # Check for numeric values that look like durations (5-60 days typical)
                    if isinstance(value, (int, float)) and 1 <= value <= 90:
                        duration_values_found = True
        
        if duration_formula_found:
            return True, "Duration calculation formulas found (DAYS or date subtraction)"
        elif duration_values_found:
            return True, "Duration values found (numeric days)"
        else:
            return False, "No duration calculation detected"
            
    except Exception as e:
        logger.error(f"Error checking duration: {e}", exc_info=True)
        return False, f"Error: {str(e)}"


def check_success_rate_by_category(sheet_data: Dict, sheet_name: str, 
                                   category_name: str, min_categories: int) -> Tuple[bool, str]:
    """
    Check if success rates have been calculated for a category (method or plant type).
    Look for percentage calculations with COUNTIF/COUNTIFS.
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        rate_formulas_found = []
        percentage_values_found = []
        category_labels_found = []
        
        # Scan for regions that look like summary tables
        for row_idx, row in enumerate(rows):
            row_has_percentage = False
            row_has_text = False
            
            for col_idx, cell in enumerate(row[:20]):
                if isinstance(cell, dict):
                    formula = cell.get('formula', '')
                    value = cell.get('value')
                    
                    # Check for percentage formulas
                    if formula and isinstance(formula, str):
                        formula_upper = formula.upper()
                        if ('COUNTIF' in formula_upper or 'COUNTIFS' in formula_upper) and '/' in formula:
                            rate_formulas_found.append((row_idx, col_idx, formula))
                            logger.info(f"Found rate formula at row {row_idx}, col {col_idx}")
                        if '*100' in formula_upper or '/100' in formula_upper:
                            row_has_percentage = True
                    
                    # Check for percentage values (0-100 range)
                    if isinstance(value, (int, float)) and 0 <= value <= 100:
                        percentage_values_found.append((row_idx, col_idx, value))
                        row_has_percentage = True
                    
                    # Check for category labels
                    if isinstance(value, str) and len(value) > 2:
                        value_lower = value.lower()
                        # Check for method names
                        if category_name.lower() == 'method':
                            if any(method in value_lower for method in ['water', 'soil', 'perlite', 'leca', 'sphagnum']):
                                category_labels_found.append((row_idx, col_idx, value))
                                row_has_text = True
                        # Check for plant names
                        elif category_name.lower() == 'plant':
                            if any(plant in value_lower for plant in ['pothos', 'monstera', 'philodendron', 'snake', 'spider', 'zz', 'string', 'pearl']):
                                category_labels_found.append((row_idx, col_idx, value))
                                row_has_text = True
        
        # Evaluate findings
        has_formulas = len(rate_formulas_found) >= min_categories
        has_values = len(percentage_values_found) >= min_categories
        has_labels = len(category_labels_found) >= min_categories
        
        if has_formulas and has_labels:
            return True, f"Success rate by {category_name} found ({len(rate_formulas_found)} formulas, {len(category_labels_found)} labels)"
        elif has_values and has_labels:
            return True, f"Success rate by {category_name} found ({len(percentage_values_found)} percentages, {len(category_labels_found)} labels)"
        elif has_labels:
            return False, f"Category labels found but no percentage calculations ({len(category_labels_found)} {category_name}s)"
        else:
            return False, f"No success rate analysis by {category_name} detected"
            
    except Exception as e:
        logger.error(f"Error checking success rate by {category_name}: {e}", exc_info=True)
        return False, f"Error: {str(e)}"


def check_average_rooting_time(sheet_data: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if average rooting time has been calculated.
    Look for AVERAGE/AVERAGEIF functions.
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        average_formula_found = False
        
        for row_idx, row in enumerate(rows):
            for col_idx, cell in enumerate(row[:20]):
                if isinstance(cell, dict):
                    formula = cell.get('formula', '')
                    
                    if formula and isinstance(formula, str):
                        formula_upper = formula.upper()
                        if 'AVERAGE' in formula_upper:
                            average_formula_found = True
                            logger.info(f"Found average formula at row {row_idx}, col {col_idx}: {formula}")
                            return True, "Average rooting time calculation found (AVERAGE/AVERAGEIF)"
        
        return False, "No average rooting time calculation detected"
            
    except Exception as e:
        logger.error(f"Error checking average rooting time: {e}", exc_info=True)
        return False, f"Error: {str(e)}"


def check_summary_table(sheet_data: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if a summary table exists separate from raw data.
    Look for concentrated regions with labels and calculations.
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        # Look for regions with both text labels and numeric summaries
        summary_regions = []
        
        for row_idx in range(len(rows)):
            if row_idx + 3 >= len(rows):  # Need at least 3 rows for a table
                break
                
            # Check if this could be start of a summary table
            region_has_labels = 0
            region_has_numbers = 0
            region_has_formulas = 0
            
            # Check next 5 rows
            for offset in range(min(5, len(rows) - row_idx)):
                check_row = rows[row_idx + offset]
                for cell in check_row[:15]:
                    if isinstance(cell, dict):
                        value = cell.get('value')
                        formula = cell.get('formula')
                        
                        if isinstance(value, str) and len(value) > 2:
                            region_has_labels += 1
                        if isinstance(value, (int, float)):
                            region_has_numbers += 1
                        if formula:
                            region_has_formulas += 1
            
            # If region has good mix of labels, numbers, and formulas, it's likely a summary
            if region_has_labels >= 3 and region_has_numbers >= 3 and region_has_formulas >= 2:
                summary_regions.append(row_idx)
                logger.info(f"Found potential summary table at row {row_idx}")
        
        if summary_regions:
            return True, f"Summary table(s) found ({len(summary_regions)} region(s) with structured analysis)"
        else:
            return False, "No distinct summary table detected"
            
    except Exception as e:
        logger.error(f"Error checking summary table: {e}", exc_info=True)
        return False, f"Error: {str(e)}"


def verify_propagation_analysis(traj, env_info, task_info):
    """
    Verify plant propagation analysis task completion.
    
    Checks 8 criteria:
    1. Date standardization
    2. Success determination
    3. Duration calculation
    4. Success rate by method
    5. Success rate by plant type
    6. Average rooting time
    7. Conditional formatting
    8. Summary table
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try different possible file locations
    possible_paths = [
        "/home/ga/Documents/propagation_analysis.ods",
        "/home/ga/Documents/propagation_log.ods",
        "/home/ga/Documents/propagation_log.csv"
    ]
    
    success = False
    file_info = None
    temp_dir = None
    
    for container_path in possible_paths:
        file_format = 'csv' if container_path.endswith('.csv') else 'ods'
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
            "feedback": f"Failed to load file: {error}. Tried: {', '.join(possible_paths)}"
        }
    
    try:
        sheet_data = file_info['sheet_data']
        sheet_names = list(sheet_data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        temp_dir = file_info.get('temp_dir')
        
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Date standardization
        date_ok, date_msg = check_date_standardization(sheet_data, sheet_name)
        if date_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {date_msg}")
        else:
            feedback_parts.append(f"❌ {date_msg}")
        subscores['date_standardization'] = date_ok
        
        # Criterion 2: Success determination
        success_ok, success_msg = check_success_determination(sheet_data, sheet_name)
        if success_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {success_msg}")
        else:
            feedback_parts.append(f"❌ {success_msg}")
        subscores['success_determination'] = success_ok
        
        # Criterion 3: Duration calculation
        duration_ok, duration_msg = check_duration_calculation(sheet_data, sheet_name)
        if duration_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {duration_msg}")
        else:
            feedback_parts.append(f"❌ {duration_msg}")
        subscores['duration_calculation'] = duration_ok
        
        # Criterion 4: Success rate by method
        method_rate_ok, method_rate_msg = check_success_rate_by_category(
            sheet_data, sheet_name, 'method', min_categories=3
        )
        if method_rate_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {method_rate_msg}")
        else:
            feedback_parts.append(f"❌ {method_rate_msg}")
        subscores['success_rate_by_method'] = method_rate_ok
        
        # Criterion 5: Success rate by plant type
        plant_rate_ok, plant_rate_msg = check_success_rate_by_category(
            sheet_data, sheet_name, 'plant', min_categories=5
        )
        if plant_rate_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {plant_rate_msg}")
        else:
            feedback_parts.append(f"❌ {plant_rate_msg}")
        subscores['success_rate_by_plant'] = plant_rate_ok
        
        # Criterion 6: Average rooting time
        avg_time_ok, avg_time_msg = check_average_rooting_time(sheet_data, sheet_name)
        if avg_time_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {avg_time_msg}")
        else:
            feedback_parts.append(f"❌ {avg_time_msg}")
        subscores['average_rooting_time'] = avg_time_ok
        
        # Criterion 7: Conditional formatting
        # Note: This is a simplified check - full conditional formatting detection is complex
        cond_format_ok = check_conditional_formatting(sheet_data, sheet_name, "A1:Z100")
        if cond_format_ok:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting applied")
        else:
            feedback_parts.append("⚠️ No conditional formatting detected (optional but recommended)")
            # Don't fail just for this - give partial credit
            criteria_passed += 0.5
        subscores['conditional_formatting'] = cond_format_ok
        
        # Criterion 8: Summary table exists
        summary_ok, summary_msg = check_summary_table(sheet_data, sheet_name)
        if summary_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {summary_msg}")
        else:
            feedback_parts.append(f"❌ {summary_msg}")
        subscores['summary_table'] = summary_ok
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 6/8 criteria (75%)
        
        # Add overall assessment
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent propagation analysis!")
        elif passed:
            feedback_parts.append("✅ Propagation analysis completed successfully")
        else:
            feedback_parts.append("❌ Analysis incomplete - more work needed")
        
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
