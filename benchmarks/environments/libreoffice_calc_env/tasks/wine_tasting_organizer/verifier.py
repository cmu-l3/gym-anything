#!/usr/bin/env python3
"""
Verifier for Wine Tasting Organizer task
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_environment,
    get_cell_value,
    get_cell_formula
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_wine_tasting_organizer(traj, env_info, task_info):
    """
    Verify that wine tasting data was properly organized and analyzed
    
    Checks:
    1. Standardized Rating column exists
    2. All ratings numeric (1-10 scale)
    3. Value Score calculated
    4. Category averages computed (AVERAGEIF formulas)
    5. Price data cleaned (numeric, no $)
    6. Summary section present (MAX/COUNT formulas)
    7. Top wines identified (MAX formulas)
    8. No formula errors
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to load the organized file, fall back to original CSV if needed
    success = False
    file_info = None
    error = ""
    
    for container_path in [
        "/home/ga/Documents/wine_journal_organized.ods",
        "/home/ga/Documents/wine_journal.ods",
        "/home/ga/Documents/wine_journal.csv"
    ]:
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            container_path,
            expected_formats=['ods', 'xlsx', 'csv']
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}
    
    try:
        data = file_info['sheet_data']
        sheets = list(data.get('sheets', {}).keys())
        
        if not sheets:
            cleanup_verification_environment(file_info.get('temp_dir'))
            return {"passed": False, "score": 0, "feedback": "No sheets found in spreadsheet"}
        
        sheet_name = sheets[0]
        sheet_data = data['sheets'][sheet_name]
        
        if not sheet_data or len(sheet_data) < 2:
            cleanup_verification_environment(file_info.get('temp_dir'))
            return {"passed": False, "score": 0, "feedback": "Sheet is empty or has insufficient data"}
        
        criteria_met = 0
        total_criteria = 8
        feedback = []
        
        # Get header row to find column indices
        header_row = sheet_data[0] if sheet_data else []
        header_values = []
        for cell in header_row:
            val = cell.get('value', '') if isinstance(cell, dict) else cell
            header_values.append(str(val).lower() if val else '')
        
        # Criterion 1: Standardized Rating Column Exists
        rating_col_idx = None
        for idx, header in enumerate(header_values):
            if 'standard' in header and 'rating' in header:
                rating_col_idx = idx
                criteria_met += 1
                feedback.append("✅ Standardized rating column found")
                break
        
        if rating_col_idx is None:
            # Try alternative names
            for idx, header in enumerate(header_values):
                if 'normalized' in header or ('rating' in header and 'original' not in header and header != 'original rating'):
                    # Make sure it's not the original rating column
                    if 'original' not in header:
                        rating_col_idx = idx
                        criteria_met += 1
                        feedback.append("✅ Rating column found")
                        break
        
        if rating_col_idx is None:
            feedback.append("✗ No standardized rating column found")
        
        # Criterion 2: All Ratings Numeric (1-10 scale)
        if rating_col_idx is not None:
            all_numeric = True
            in_range = True
            rating_count = 0
            
            for row in sheet_data[1:]:  # Skip header
                if rating_col_idx < len(row):
                    cell = row[rating_col_idx]
                    val = cell.get('value', '') if isinstance(cell, dict) else cell
                    
                    if val is not None and val != '' and val != 0:
                        rating_count += 1
                        try:
                            numeric_val = float(val)
                            if not (1 <= numeric_val <= 10):
                                in_range = False
                        except (ValueError, TypeError):
                            all_numeric = False
            
            if rating_count >= 8 and all_numeric and in_range:
                criteria_met += 1
                feedback.append(f"✅ All ratings properly converted to 1-10 numeric scale ({rating_count} ratings)")
            elif rating_count >= 8 and all_numeric:
                feedback.append(f"⚠️ Ratings are numeric but some may be out of 1-10 range")
            else:
                feedback.append("✗ Some ratings not properly standardized or missing")
        
        # Criterion 3: Value Score Calculated
        value_col_idx = None
        for idx, header in enumerate(header_values):
            if 'value' in header and ('score' in header or 'ratio' in header or header.strip() == 'value'):
                value_col_idx = idx
                criteria_met += 1
                feedback.append("✅ Value score column found")
                break
        
        if value_col_idx is None:
            feedback.append("✗ No value score column found")
        
        # Criterion 4: Category Averages Computed (AVERAGEIF formulas)
        category_average_found = False
        averageif_count = 0
        
        for row in sheet_data:
            for cell in row:
                formula = cell.get('formula', '') if isinstance(cell, dict) else ''
                if formula:
                    formula_upper = str(formula).upper()
                    if 'AVERAGEIF' in formula_upper or 'AVERAGE(IF' in formula_upper:
                        averageif_count += 1
                        category_average_found = True
        
        if category_average_found:
            criteria_met += 1
            feedback.append(f"✅ Category average calculations found ({averageif_count} formula(s))")
        else:
            # Check for manual average calculations by category
            avg_found = False
            for row in sheet_data:
                for cell in row:
                    formula = cell.get('formula', '') if isinstance(cell, dict) else ''
                    if formula and 'AVERAGE' in str(formula).upper():
                        avg_found = True
                        break
            
            if avg_found:
                feedback.append("⚠️ Average formulas found but may not be category-specific (no AVERAGEIF)")
            else:
                feedback.append("✗ No category average formulas detected")
        
        # Criterion 5: Price Data Cleaned
        price_col_idx = None
        for idx, header in enumerate(header_values):
            if 'price' in header:
                price_col_idx = idx
                break
        
        if price_col_idx is not None:
            prices_clean = True
            price_count = 0
            
            for row in sheet_data[1:]:
                if price_col_idx < len(row):
                    cell = row[price_col_idx]
                    val = cell.get('value', '') if isinstance(cell, dict) else cell
                    
                    if val is not None and val != '':
                        price_count += 1
                        # Check if it's numeric
                        if not isinstance(val, (int, float)):
                            # Check if it's a string with $ that should be cleaned
                            if isinstance(val, str) and ('$' in val or not str(val).replace('.', '').replace(',', '').replace('-', '').isdigit()):
                                prices_clean = False
                                break
            
            if prices_clean and price_count >= 8:
                criteria_met += 1
                feedback.append("✅ Price data properly cleaned (numeric)")
            else:
                feedback.append("✗ Some prices still have $ symbols or non-numeric format")
        else:
            feedback.append("⚠️ Could not locate price column")
        
        # Criterion 6: Summary Section Present (MAX/COUNT formulas)
        summary_formulas_found = 0
        max_count = 0
        count_count = 0
        
        for row in sheet_data:
            for cell in row:
                formula = cell.get('formula', '') if isinstance(cell, dict) else ''
                if formula:
                    formula_upper = str(formula).upper()
                    if 'MAX' in formula_upper:
                        max_count += 1
                        summary_formulas_found += 1
                    if 'COUNT' in formula_upper:
                        count_count += 1
                        summary_formulas_found += 1
        
        if summary_formulas_found >= 2:
            criteria_met += 1
            feedback.append(f"✅ Summary section with aggregate formulas found (MAX: {max_count}, COUNT: {count_count})")
        elif max_count >= 1:
            feedback.append("⚠️ Some summary formulas found but incomplete (need both MAX and COUNT types)")
        else:
            feedback.append("✗ Insufficient summary statistics (need MAX/COUNT formulas)")
        
        # Criterion 7: Top Wines Identified (MAX formulas)
        max_formula_found = max_count > 0
        
        if max_formula_found:
            criteria_met += 1
            feedback.append("✅ Top wine identification formula found")
        else:
            feedback.append("✗ No MAX formula for identifying top wines")
        
        # Criterion 8: No Formula Errors
        has_errors = False
        error_list = []
        
        for row_idx, row in enumerate(sheet_data):
            for col_idx, cell in enumerate(row):
                val = cell.get('value', '') if isinstance(cell, dict) else cell
                val_str = str(val) if val is not None else ''
                
                if val_str.startswith('#'):
                    error_types = ['DIV/0', 'VALUE', 'REF', 'NAME', 'NUM', 'N/A', 'NULL']
                    if any(err in val_str.upper() for err in error_types):
                        has_errors = True
                        error_list.append(f"Row {row_idx+1}, Col {col_idx+1}")
                        if len(error_list) >= 3:  # Limit error reporting
                            break
            if has_errors and len(error_list) >= 3:
                break
        
        if not has_errors:
            criteria_met += 1
            feedback.append("✅ No formula errors detected")
        else:
            feedback.append(f"✗ Formula errors present at: {', '.join(error_list[:3])}")
        
        # Calculate final score
        score = (criteria_met / total_criteria) * 100
        
        # Generate feedback message
        feedback_msg = f"Wine Tasting Organizer Verification ({criteria_met}/{total_criteria} criteria met):\n"
        feedback_msg += "\n".join(feedback)
        feedback_msg += f"\n\nFinal Score: {score:.1f}%"
        
        passed = score >= 75
        
        if passed:
            feedback_msg += " - PASS ✓"
        else:
            feedback_msg += " - FAIL ✗"
        
        # Cleanup
        cleanup_verification_environment(file_info.get('temp_dir'))
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": feedback_msg,
            "subscores": {
                "standardized_rating_column": rating_col_idx is not None,
                "ratings_numeric": criteria_met >= 2,
                "value_score_calculated": value_col_idx is not None,
                "category_averages": category_average_found,
                "price_data_cleaned": criteria_met >= 5,
                "summary_section": summary_formulas_found >= 2,
                "top_wines_identified": max_formula_found,
                "no_errors": not has_errors
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
