#!/usr/bin/env python3
"""
Verifier for Fuel Economy Diagnostic Analyzer task.

Checks:
1. Data cleaning (numeric columns, standardization)
2. Formula presence and correctness
3. Conditional formatting
4. Performance categorization
5. Data integrity
"""

import sys
import os
import logging
import re
import random

# Add utils to path - use relative path since verification runs on host
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


def find_column_by_header(data, sheet_name, header_keyword):
    """
    Find column index by searching for header keyword (case-insensitive).
    Returns -1 if not found.
    """
    try:
        sheet_rows = data['sheets'][sheet_name]
        if not sheet_rows:
            return -1
        
        header_row = sheet_rows[0]
        header_keyword_lower = header_keyword.lower()
        
        for col_idx, cell in enumerate(header_row):
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value and header_keyword_lower in str(cell_value).lower():
                return col_idx
        
        return -1
    except Exception as e:
        logger.error(f"Error finding column: {e}")
        return -1


def get_column_values(data, sheet_name, col_index, skip_header=True):
    """Get all values from a column."""
    try:
        sheet_rows = data['sheets'][sheet_name]
        start_row = 1 if skip_header else 0
        values = []
        
        for row_idx in range(start_row, len(sheet_rows)):
            if col_index < len(sheet_rows[row_idx]):
                cell = sheet_rows[row_idx][col_index]
                value = cell.get('value') if isinstance(cell, dict) else cell
                values.append(value)
        
        return values
    except Exception as e:
        logger.error(f"Error getting column values: {e}")
        return []


def get_column_formulas(data, sheet_name, col_index, skip_header=True):
    """Get all formulas from a column."""
    try:
        sheet_rows = data['sheets'][sheet_name]
        start_row = 1 if skip_header else 0
        formulas = []
        
        for row_idx in range(start_row, len(sheet_rows)):
            if col_index < len(sheet_rows[row_idx]):
                cell = sheet_rows[row_idx][col_index]
                formula = cell.get('formula') if isinstance(cell, dict) else None
                formulas.append(formula)
        
        return formulas
    except Exception as e:
        logger.error(f"Error getting column formulas: {e}")
        return []


def col_idx_to_letter(col_idx):
    """Convert 0-based column index to Excel-style letter (0='A', 25='Z', 26='AA')."""
    result = ""
    col_idx += 1  # Make 1-based
    while col_idx > 0:
        col_idx -= 1
        result = chr(ord('A') + (col_idx % 26)) + result
        col_idx //= 26
    return result


def has_capitalization_duplicates(values):
    """Check if set has duplicates that differ only in capitalization."""
    seen_lower = set()
    for val in values:
        val_lower = str(val).lower()
        if val_lower in seen_lower:
            return True
        seen_lower.add(val_lower)
    return len(seen_lower) < len(values)


def check_for_formula_errors(data, sheet_name):
    """Check if any cells contain formula errors."""
    try:
        sheet_rows = data['sheets'][sheet_name]
        error_patterns = ['#DIV/0!', '#VALUE!', '#REF!', '#NAME?', '#NUM!', '#N/A', '#NULL!']
        
        for row in sheet_rows:
            for cell in row:
                value = cell.get('value') if isinstance(cell, dict) else cell
                if value and any(err in str(value) for err in error_patterns):
                    return True
        
        return False
    except Exception as e:
        logger.error(f"Error checking for formula errors: {e}")
        return False


def is_numeric_value(value):
    """Check if a value is numeric (int, float, or numeric string)."""
    if value is None:
        return False
    if isinstance(value, (int, float)):
        return True
    # Check if it's a string that can be converted to float
    try:
        float(str(value))
        return True
    except (ValueError, TypeError):
        return False


def verify_fuel_economy_diagnostic(traj, env_info, task_info):
    """
    Verify fuel economy diagnostic task completion.
    
    Checks:
    1. Data cleaning (Miles and Gallons numeric)
    2. Category standardization (Weather, AC Usage)
    3. Duplicate removal
    4. MPG formulas present
    5. MPG calculations correct
    6. Conditional formatting applied
    7. Performance categorization
    8. No formula errors
    9. Data integrity
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file paths as fallbacks
    file_paths = [
        ("/home/ga/Documents/fuel_economy_analyzed.ods", "ods"),
        ("/home/ga/Documents/fuel_log_messy.ods", "ods"),
        ("/home/ga/Documents/fuel_log_messy.csv", "csv"),
        ("/home/ga/Documents/fuel_economy_analyzed.csv", "csv"),
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for container_path, file_format in file_paths:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load any result file. Last error: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_rows = workbook['sheets'][sheet_name]
        
        # Initialize scoring
        criteria_met = 0
        total_criteria = 9
        feedback_parts = []
        
        # Count data rows (excluding header)
        row_count = len([row for row in sheet_rows[1:] if any(
            (cell.get('value') if isinstance(cell, dict) else cell) for cell in row
        )])
        
        logger.info(f"Sheet has {row_count} data rows (excluding header)")
        
        # Find column indices by header
        miles_col = find_column_by_header(workbook, sheet_name, "miles")
        gallons_col = find_column_by_header(workbook, sheet_name, "gallons")
        weather_col = find_column_by_header(workbook, sheet_name, "weather")
        ac_col = find_column_by_header(workbook, sheet_name, "ac")
        mpg_col = find_column_by_header(workbook, sheet_name, "mpg")
        perf_col = find_column_by_header(workbook, sheet_name, "performance")
        
        logger.info(f"Column indices - Miles: {miles_col}, Gallons: {gallons_col}, "
                   f"Weather: {weather_col}, AC: {ac_col}, MPG: {mpg_col}, Perf: {perf_col}")
        
        # ===== Criterion 1: Miles column is clean (numeric only) =====
        if miles_col >= 0:
            miles_values = get_column_values(workbook, sheet_name, miles_col, skip_header=True)
            # Filter out None/empty values
            miles_values = [v for v in miles_values if v is not None and str(v).strip() != '']
            
            numeric_count = sum(1 for v in miles_values if is_numeric_value(v))
            if numeric_count >= len(miles_values) * 0.9:  # 90% numeric
                criteria_met += 1
                feedback_parts.append("✅ Miles column cleaned (numeric only)")
            else:
                feedback_parts.append(f"❌ Miles column still contains text ({numeric_count}/{len(miles_values)} numeric)")
        else:
            feedback_parts.append("❌ Miles column not found")
        
        # ===== Criterion 2: Gallons column is clean (numeric only) =====
        if gallons_col >= 0:
            gallons_values = get_column_values(workbook, sheet_name, gallons_col, skip_header=True)
            gallons_values = [v for v in gallons_values if v is not None and str(v).strip() != '']
            
            numeric_count = sum(1 for v in gallons_values if is_numeric_value(v))
            if numeric_count >= len(gallons_values) * 0.9:
                criteria_met += 1
                feedback_parts.append("✅ Gallons column cleaned (numeric only)")
            else:
                feedback_parts.append(f"❌ Gallons column still contains text ({numeric_count}/{len(gallons_values)} numeric)")
        else:
            feedback_parts.append("❌ Gallons column not found")
        
        # ===== Criterion 3: Weather column standardized =====
        if weather_col >= 0:
            weather_values = get_column_values(workbook, sheet_name, weather_col, skip_header=True)
            weather_values = [v for v in weather_values if v is not None and str(v).strip() != '']
            unique_weather = set(str(v).strip() for v in weather_values)
            
            # Check for inconsistent capitalization (e.g., "Hot" and "hot")
            has_inconsistency = has_capitalization_duplicates(unique_weather)
            
            if len(unique_weather) <= 6 and not has_inconsistency:
                criteria_met += 1
                feedback_parts.append(f"✅ Weather column standardized ({len(unique_weather)} unique values)")
            else:
                feedback_parts.append(f"❌ Weather column has inconsistent formatting ({len(unique_weather)} unique, capitalization issues: {has_inconsistency})")
        else:
            feedback_parts.append("⚠️ Weather column not found (optional)")
        
        # ===== Criterion 4: AC Usage column standardized =====
        if ac_col >= 0:
            ac_values = get_column_values(workbook, sheet_name, ac_col, skip_header=True)
            ac_values = [v for v in ac_values if v is not None and str(v).strip() != '']
            unique_ac = set(str(v).strip() for v in ac_values)
            
            has_inconsistency = has_capitalization_duplicates(unique_ac)
            
            if len(unique_ac) <= 3 and not has_inconsistency:
                criteria_met += 1
                feedback_parts.append(f"✅ AC Usage column standardized ({len(unique_ac)} unique values)")
            else:
                feedback_parts.append(f"❌ AC Usage column has inconsistent formatting ({len(unique_ac)} unique, capitalization issues: {has_inconsistency})")
        else:
            feedback_parts.append("⚠️ AC Usage column not found (optional)")
        
        # ===== Criterion 5: Duplicate removed (row count check) =====
        # Original should have ~18 entries, after duplicate removal should be ~17
        if 15 <= row_count <= 17:
            criteria_met += 1
            feedback_parts.append(f"✅ Duplicate appears removed ({row_count} rows)")
        else:
            feedback_parts.append(f"⚠️ Row count unexpected: {row_count} (expected 15-17 after duplicate removal)")
        
        # ===== Criterion 6: MPG column has formulas =====
        if mpg_col >= 0:
            mpg_formulas = get_column_formulas(workbook, sheet_name, mpg_col, skip_header=True)
            formula_count = sum(1 for f in mpg_formulas if f and '/' in str(f))
            
            if formula_count >= row_count * 0.7:  # 70% of rows have division formulas
                criteria_met += 1
                feedback_parts.append(f"✅ MPG column contains division formulas ({formula_count} formulas)")
            else:
                feedback_parts.append(f"❌ MPG column missing formulas ({formula_count}/{row_count} rows have formulas)")
        else:
            feedback_parts.append("❌ MPG column not found")
        
        # ===== Criterion 7: MPG calculations correct (spot check) =====
        if miles_col >= 0 and gallons_col >= 0 and mpg_col >= 0:
            correct_calcs = 0
            checked_rows = 0
            
            # Sample up to 5 random rows for spot-checking
            data_row_indices = list(range(1, min(row_count + 1, len(sheet_rows))))
            sample_size = min(5, len(data_row_indices))
            
            if data_row_indices:
                sample_indices = random.sample(data_row_indices, sample_size)
                
                for row_idx in sample_indices:
                    if row_idx >= len(sheet_rows):
                        continue
                    
                    row = sheet_rows[row_idx]
                    if miles_col >= len(row) or gallons_col >= len(row) or mpg_col >= len(row):
                        continue
                    
                    miles_cell = row[miles_col]
                    gallons_cell = row[gallons_col]
                    mpg_cell = row[mpg_col]
                    
                    miles = miles_cell.get('value') if isinstance(miles_cell, dict) else miles_cell
                    gallons = gallons_cell.get('value') if isinstance(gallons_cell, dict) else gallons_cell
                    mpg = mpg_cell.get('value') if isinstance(mpg_cell, dict) else mpg_cell
                    
                    if miles and gallons and mpg and is_numeric_value(miles) and is_numeric_value(gallons):
                        try:
                            expected_mpg = float(miles) / float(gallons)
                            actual_mpg = float(mpg)
                            if abs(actual_mpg - expected_mpg) < 0.5:  # Allow 0.5 MPG tolerance
                                correct_calcs += 1
                            checked_rows += 1
                        except (ValueError, ZeroDivisionError):
                            checked_rows += 1
                
                if checked_rows > 0 and correct_calcs / checked_rows >= 0.6:  # 60% correct
                    criteria_met += 1
                    feedback_parts.append(f"✅ MPG calculations verified correct ({correct_calcs}/{checked_rows} spot checks)")
                else:
                    feedback_parts.append(f"❌ MPG calculations have errors ({correct_calcs}/{checked_rows} correct)")
            else:
                feedback_parts.append("⚠️ No data rows to verify calculations")
        else:
            feedback_parts.append("⚠️ Cannot verify calculations (columns missing)")
        
        # ===== Criterion 8: Conditional formatting applied =====
        if mpg_col >= 0:
            # Try to check for conditional formatting
            # Note: This may not work perfectly for all formats
            has_formatting = check_conditional_formatting(
                workbook, 
                sheet_name, 
                f"{col_idx_to_letter(mpg_col)}2:{col_idx_to_letter(mpg_col)}{row_count + 1}"
            )
            
            if has_formatting:
                criteria_met += 1
                feedback_parts.append("✅ Conditional formatting applied to MPG column")
            else:
                # Give partial credit if we can't detect but other criteria met
                feedback_parts.append("⚠️ Conditional formatting not detected (may be present but not parseable)")
        else:
            feedback_parts.append("⚠️ Cannot check conditional formatting (MPG column not found)")
        
        # ===== Criterion 9: Performance category column exists =====
        if perf_col >= 0:
            perf_formulas = get_column_formulas(workbook, sheet_name, perf_col, skip_header=True)
            has_if_formulas = any('IF' in str(f).upper() for f in perf_formulas if f)
            
            if has_if_formulas:
                criteria_met += 1
                feedback_parts.append("✅ Performance category column with IF logic found")
            else:
                # Check if manual categorization was done
                perf_values = get_column_values(workbook, sheet_name, perf_col, skip_header=True)
                has_categories = any(
                    str(v).lower() in ['good', 'fair', 'poor'] 
                    for v in perf_values if v
                )
                
                if has_categories:
                    criteria_met += 0.5  # Partial credit
                    feedback_parts.append("⚠️ Performance categories present but not using formulas")
                else:
                    feedback_parts.append("❌ Performance category column missing or incorrect")
        else:
            feedback_parts.append("❌ Performance column not found")
        
        # ===== Bonus Check: No formula errors =====
        has_errors = check_for_formula_errors(workbook, sheet_name)
        if not has_errors:
            feedback_parts.append("✅ No formula errors detected")
        else:
            feedback_parts.append("⚠️ Formula errors detected (#DIV/0!, #VALUE!, etc.)")
            # Don't penalize score, just warn
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        # Add overall assessment
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent fuel economy analysis!")
        elif passed:
            feedback_parts.insert(0, "✅ Fuel economy diagnostic task completed")
        else:
            feedback_parts.insert(0, "❌ Task requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "miles_cleaned": miles_col >= 0,
                "gallons_cleaned": gallons_col >= 0,
                "weather_standardized": weather_col >= 0,
                "ac_standardized": ac_col >= 0,
                "duplicate_removed": 15 <= row_count <= 17,
                "mpg_formulas": mpg_col >= 0,
                "performance_categories": perf_col >= 0,
                "no_errors": not has_errors
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
        if temp_dir:
            cleanup_verification_temp(temp_dir)
