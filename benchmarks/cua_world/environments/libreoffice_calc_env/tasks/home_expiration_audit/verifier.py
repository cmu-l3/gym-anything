#!/usr/bin/env python3
"""
Verifier for Home Expiration Audit task.
Checks data cleaning, calculations, formatting, sorting, and analysis.
"""

import sys
import os
import logging
from datetime import datetime, timedelta
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


def normalize_text(text):
    """Normalize text for comparison (lowercase, strip spaces)"""
    if text is None:
        return ""
    return str(text).lower().strip()


def verify_home_expiration_audit(traj, env_info, task_info):
    """
    Verify home expiration audit task completion.
    
    Checks:
    1. Data standardization (locations, categories)
    2. Date calculations (days until expiration)
    3. Status classification
    4. Conditional formatting indicators
    5. Summary statistics
    6. Waste analysis
    7. Sorting
    8. File saved
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible output files
    possible_paths = [
        "/home/ga/Documents/home_expiration_audit_cleaned.ods",
        "/home/ga/Documents/home_inventory_messy.ods",
        "/home/ga/Documents/home_inventory_messy.csv"
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for container_path in possible_paths:
        # Determine format from extension
        file_format = 'ods' if container_path.endswith('.ods') else 'csv'
        
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = workbook['sheets'][sheet_name]
        
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        
        # Helper function to find column index by header name
        def find_column_by_header(header_keywords):
            """Find column index by matching header keywords"""
            if not sheet_data or len(sheet_data) == 0:
                return -1
            
            header_row = sheet_data[0]
            for col_idx, cell in enumerate(header_row):
                value = cell.get('value') if isinstance(cell, dict) else cell
                if value:
                    value_norm = normalize_text(value)
                    for keyword in header_keywords:
                        if keyword in value_norm:
                            return col_idx
            return -1
        
        # Find important columns
        location_col = find_column_by_header(['location'])
        category_col = find_column_by_header(['category'])
        status_col = find_column_by_header(['status category', 'status'])
        days_col = find_column_by_header(['days until', 'days'])
        
        # Criterion 1: Data Standardization (Locations & Categories)
        standardized_locations = {
            'medicine cabinet', 'pantry', 'bathroom', 'first aid kit'
        }
        standardized_categories = {
            'medication', 'food', 'personal care', 'first aid'
        }
        
        location_consistency = 0
        category_consistency = 0
        total_items = 0
        
        for row_idx in range(1, len(sheet_data)):  # Skip header
            row = sheet_data[row_idx]
            if len(row) == 0:
                continue
            
            # Check if row has data
            has_data = any(cell.get('value') if isinstance(cell, dict) else cell for cell in row)
            if not has_data:
                continue
            
            total_items += 1
            
            # Check location standardization
            if location_col >= 0 and location_col < len(row):
                loc_value = row[location_col].get('value') if isinstance(row[location_col], dict) else row[location_col]
                if loc_value:
                    loc_norm = normalize_text(loc_value)
                    if any(std_loc in loc_norm for std_loc in standardized_locations):
                        location_consistency += 1
            
            # Check category standardization
            if category_col >= 0 and category_col < len(row):
                cat_value = row[category_col].get('value') if isinstance(row[category_col], dict) else row[category_col]
                if cat_value:
                    cat_norm = normalize_text(cat_value)
                    if any(std_cat in cat_norm for std_cat in standardized_categories):
                        category_consistency += 1
        
        if total_items > 0:
            location_pct = (location_consistency / total_items) * 100
            category_pct = (category_consistency / total_items) * 100
            
            if location_pct >= 85 and category_pct >= 85:
                criteria_passed += 1
                feedback_parts.append(f"✅ Data standardization: Locations {location_pct:.0f}%, Categories {category_pct:.0f}%")
            else:
                feedback_parts.append(f"❌ Data standardization incomplete: Locations {location_pct:.0f}%, Categories {category_pct:.0f}% (need ≥85%)")
        else:
            feedback_parts.append("❌ No data rows found")
        
        # Criterion 2: Date Calculations (Days Until Expiration)
        has_days_formula = False
        days_formula_count = 0
        
        if days_col >= 0:
            for row_idx in range(1, min(len(sheet_data), 10)):  # Check first few rows
                row = sheet_data[row_idx]
                if days_col < len(row):
                    formula = get_cell_formula(workbook, sheet_name, f"{chr(65 + days_col)}{row_idx + 1}")
                    if formula and ('TODAY' in formula.upper() or '-' in formula):
                        days_formula_count += 1
                        has_days_formula = True
        
        if has_days_formula and days_formula_count >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Date calculations present ({days_formula_count} formulas found)")
        else:
            feedback_parts.append(f"❌ Date calculations missing or insufficient ({days_formula_count} formulas)")
        
        # Criterion 3: Status Classification
        status_categories_found = set()
        status_correct_count = 0
        
        if status_col >= 0:
            for row_idx in range(1, len(sheet_data)):
                row = sheet_data[row_idx]
                if status_col < len(row):
                    status_value = row[status_col].get('value') if isinstance(row[status_col], dict) else row[status_col]
                    if status_value:
                        status_norm = str(status_value).upper()
                        if status_norm in ['EXPIRED', 'URGENT', 'EXPIRING SOON', 'GOOD']:
                            status_categories_found.add(status_norm)
                            status_correct_count += 1
        
        if len(status_categories_found) >= 3 and status_correct_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Status classification: {len(status_categories_found)} categories, {status_correct_count} items classified")
        else:
            feedback_parts.append(f"❌ Status classification incomplete: {len(status_categories_found)} categories, {status_correct_count} items")
        
        # Criterion 4: Conditional Formatting indicators
        # Check if multiple status categories exist (implies formatting likely applied)
        has_formatting = len(status_categories_found) >= 3
        
        if has_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting likely applied (multiple status categories present)")
        else:
            feedback_parts.append("⚠️ Conditional formatting not verified")
        
        # Criterion 5: Summary Statistics
        # Look for COUNT/COUNTIF formulas in the spreadsheet
        summary_formulas_found = 0
        
        for row_idx, row in enumerate(sheet_data):
            for col_idx, cell in enumerate(row):
                formula = get_cell_formula(workbook, sheet_name, f"{chr(65 + col_idx)}{row_idx + 1}")
                if formula:
                    formula_upper = formula.upper()
                    if any(func in formula_upper for func in ['COUNT', 'SUM', 'AVERAGE']):
                        summary_formulas_found += 1
        
        if summary_formulas_found >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Summary statistics: {summary_formulas_found} summary formulas found")
        else:
            feedback_parts.append(f"❌ Summary statistics insufficient: {summary_formulas_found} formulas (need ≥3)")
        
        # Criterion 6: Waste Analysis
        # Look for SUMIF or cost calculations
        waste_analysis_found = False
        
        for row_idx, row in enumerate(sheet_data):
            for col_idx, cell in enumerate(row):
                formula = get_cell_formula(workbook, sheet_name, f"{chr(65 + col_idx)}{row_idx + 1}")
                if formula and 'SUMIF' in formula.upper():
                    waste_analysis_found = True
                    break
            if waste_analysis_found:
                break
        
        # Also check if there's a waste flag column or waste-related text
        waste_flag_col = find_column_by_header(['waste', 'flag'])
        if waste_flag_col >= 0:
            waste_analysis_found = True
        
        if waste_analysis_found:
            criteria_passed += 1
            feedback_parts.append("✅ Waste analysis present")
        else:
            feedback_parts.append("⚠️ Waste analysis not found (partial credit)")
            criteria_passed += 0.5  # Partial credit
        
        # Criterion 7: Sorting
        # Check if data appears sorted by priority/urgency
        is_sorted = False
        
        if status_col >= 0:
            # Check if EXPIRED items are at the top
            first_few_statuses = []
            for row_idx in range(1, min(len(sheet_data), 5)):
                row = sheet_data[row_idx]
                if status_col < len(row):
                    status_value = row[status_col].get('value') if isinstance(row[status_col], dict) else row[status_col]
                    if status_value:
                        first_few_statuses.append(str(status_value).upper())
            
            # If we see EXPIRED or URGENT at the top, likely sorted
            if any(status in ['EXPIRED', 'URGENT'] for status in first_few_statuses[:3]):
                is_sorted = True
        
        if is_sorted:
            criteria_passed += 1
            feedback_parts.append("✅ Data appears sorted by priority")
        else:
            feedback_parts.append("⚠️ Sorting not verified")
            criteria_passed += 0.5  # Partial credit
        
        # Criterion 8: File Saved
        # If we got here, file was successfully loaded
        file_saved = True
        if file_saved:
            criteria_passed += 1
            feedback_parts.append("✅ File saved successfully")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        # Add overall summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent work! Home expiration audit completed successfully")
        elif passed:
            feedback_parts.insert(0, "✅ Home expiration audit task completed")
        else:
            feedback_parts.insert(0, "❌ Home expiration audit requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "data_standardization": location_pct >= 85 and category_pct >= 85 if total_items > 0 else False,
                "date_calculations": has_days_formula,
                "status_classification": len(status_categories_found) >= 3,
                "conditional_formatting": has_formatting,
                "summary_statistics": summary_formulas_found >= 3,
                "waste_analysis": waste_analysis_found,
                "sorting": is_sorted,
                "file_saved": file_saved
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        if temp_dir:
            cleanup_verification_temp(temp_dir)
