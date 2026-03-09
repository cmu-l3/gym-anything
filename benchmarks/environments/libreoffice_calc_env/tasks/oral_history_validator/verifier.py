#!/usr/bin/env python3
"""
Verifier for Oral History Archive Submission Validator task.
Checks date standardization, age calculation, archive readiness validation,
conditional formatting, sort order, and data integrity.
"""

import sys
import os
import logging
import re
from datetime import datetime
from typing import Dict, Any, Tuple, List, Optional

# Use relative path to utils folder (verification runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_column_index(data: Dict[str, Any], sheet_name: str, column_name: str) -> Optional[int]:
    """Find column index by header name (case-insensitive)."""
    try:
        rows = data['sheets'][sheet_name]
        if not rows:
            return None
        
        header_row = rows[0]
        column_name_lower = column_name.lower().strip()
        
        for idx, cell in enumerate(header_row):
            cell_value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
            if str(cell_value).lower().strip() == column_name_lower:
                return idx
        
        return None
    except Exception as e:
        logger.error(f"Error finding column '{column_name}': {e}")
        return None


def verify_date_standardization(data: Dict[str, Any], sheet_name: str) -> Tuple[bool, str]:
    """
    Verify that a 'Interview Date (Standardized)' column exists with YYYY-MM-DD dates.
    """
    try:
        # Find standardized date column
        col_idx = find_column_index(data, sheet_name, "Interview Date (Standardized)")
        if col_idx is None:
            return False, "❌ 'Interview Date (Standardized)' column not found"
        
        rows = data['sheets'][sheet_name]
        date_pattern = re.compile(r'^\d{4}-\d{2}-\d{2}$')
        
        valid_dates = 0
        total_dates = 0
        
        for row in rows[1:]:  # Skip header
            if col_idx >= len(row):
                continue
            
            cell = row[col_idx]
            cell_value = cell.get('value', '') if isinstance(cell, dict) else cell
            
            if cell_value and str(cell_value).strip():
                total_dates += 1
                # Check if it matches YYYY-MM-DD format
                if date_pattern.match(str(cell_value)):
                    valid_dates += 1
                # Also accept date objects that stringify to similar format
                elif isinstance(cell_value, str) and len(cell_value) >= 10:
                    # Try to parse as date
                    try:
                        parsed = datetime.strptime(cell_value[:10], '%Y-%m-%d')
                        valid_dates += 1
                    except:
                        pass
        
        if total_dates == 0:
            return False, "❌ No dates found in standardized column"
        
        success_rate = valid_dates / total_dates
        if success_rate >= 0.8:  # Allow some tolerance
            return True, f"✅ Date standardization correct ({valid_dates}/{total_dates} dates formatted)"
        else:
            return False, f"❌ Date standardization incomplete ({valid_dates}/{total_dates} dates formatted)"
    
    except Exception as e:
        logger.error(f"Error verifying date standardization: {e}", exc_info=True)
        return False, f"❌ Error checking dates: {str(e)}"


def verify_age_calculation(data: Dict[str, Any], sheet_name: str) -> Tuple[bool, str]:
    """
    Verify that 'Age at Interview' column exists with reasonable age values (18-110).
    Check that formulas use YEAR() function.
    """
    try:
        # Find age column
        age_col_idx = find_column_index(data, sheet_name, "Age at Interview")
        if age_col_idx is None:
            return False, "❌ 'Age at Interview' column not found"
        
        # Find birth year and standardized date columns for validation
        birth_col_idx = find_column_index(data, sheet_name, "Birth Year")
        date_col_idx = find_column_index(data, sheet_name, "Interview Date (Standardized)")
        
        rows = data['sheets'][sheet_name]
        
        reasonable_ages = 0
        total_ages = 0
        has_formula = False
        
        for row_idx, row in enumerate(rows[1:], start=1):  # Skip header
            if age_col_idx >= len(row):
                continue
            
            cell = row[age_col_idx]
            cell_value = cell.get('value', '') if isinstance(cell, dict) else cell
            cell_formula = cell.get('formula', '') if isinstance(cell, dict) else ''
            
            # Check if formula uses YEAR function
            if cell_formula and 'YEAR' in cell_formula.upper():
                has_formula = True
            
            # Validate age value
            if cell_value:
                try:
                    age = int(float(cell_value))
                    total_ages += 1
                    
                    # Check if age is reasonable (18-110)
                    if 18 <= age <= 110:
                        reasonable_ages += 1
                        
                        # Spot check: verify calculation if we have birth year and date
                        if birth_col_idx is not None and date_col_idx is not None:
                            birth_year = row[birth_col_idx].get('value', '') if isinstance(row[birth_col_idx], dict) else row[birth_col_idx]
                            date_str = row[date_col_idx].get('value', '') if isinstance(row[date_col_idx], dict) else row[date_col_idx]
                            
                            if birth_year and date_str:
                                try:
                                    birth_year = int(birth_year)
                                    # Extract year from date string
                                    year_match = re.search(r'(\d{4})', str(date_str))
                                    if year_match:
                                        interview_year = int(year_match.group(1))
                                        expected_age = interview_year - birth_year
                                        
                                        # Allow small tolerance
                                        if abs(age - expected_age) > 2:
                                            logger.warning(f"Age mismatch in row {row_idx}: {age} vs expected {expected_age}")
                                except:
                                    pass
                except:
                    pass
        
        if total_ages == 0:
            return False, "❌ No age values found"
        
        success_rate = reasonable_ages / total_ages
        
        if success_rate >= 0.8 and has_formula:
            return True, f"✅ Age calculation correct ({reasonable_ages}/{total_ages} valid ages, uses YEAR formula)"
        elif success_rate >= 0.8:
            return True, f"⚠️ Age values reasonable ({reasonable_ages}/{total_ages}) but formula not detected"
        else:
            return False, f"❌ Age calculation issues ({reasonable_ages}/{total_ages} valid ages)"
    
    except Exception as e:
        logger.error(f"Error verifying age calculation: {e}", exc_info=True)
        return False, f"❌ Error checking ages: {str(e)}"


def verify_archive_formula(data: Dict[str, Any], sheet_name: str) -> Tuple[bool, str]:
    """
    Verify 'Ready for Archive?' column with AND logic checking all requirements.
    """
    try:
        # Find archive ready column
        ready_col_idx = find_column_index(data, sheet_name, "Ready for Archive?")
        if ready_col_idx is None:
            # Try alternative names
            ready_col_idx = find_column_index(data, sheet_name, "Ready for Archive")
            if ready_col_idx is None:
                ready_col_idx = find_column_index(data, sheet_name, "Archive Ready")
                if ready_col_idx is None:
                    return False, "❌ 'Ready for Archive?' column not found"
        
        # Find required columns for validation
        transcription_idx = find_column_index(data, sheet_name, "Transcription Status")
        release_idx = find_column_index(data, sheet_name, "Release Form Signed")
        tags_idx = find_column_index(data, sheet_name, "Topic Tags")
        
        rows = data['sheets'][sheet_name]
        
        # Check if formulas use AND logic
        has_and_logic = False
        sample_formula = ""
        
        for row in rows[1:3]:  # Check first couple of data rows
            if ready_col_idx >= len(row):
                continue
            
            cell = row[ready_col_idx]
            cell_formula = cell.get('formula', '') if isinstance(cell, dict) else ''
            
            if cell_formula:
                sample_formula = cell_formula
                # Check for AND function or multiple conditions
                if 'AND' in cell_formula.upper() or ('IF' in cell_formula.upper() and cell_formula.count('=') >= 3):
                    has_and_logic = True
                    break
        
        # Validate logic by spot-checking values
        correct_logic = 0
        total_checks = 0
        
        for row_idx, row in enumerate(rows[1:], start=1):
            if ready_col_idx >= len(row):
                continue
            
            # Get ready value
            ready_cell = row[ready_col_idx]
            ready_value = ready_cell.get('value', '') if isinstance(ready_cell, dict) else ready_cell
            ready_value = str(ready_value).strip().upper()
            
            # Get requirement values
            if transcription_idx is not None and release_idx is not None and tags_idx is not None:
                transcription = str(row[transcription_idx].get('value', '') if isinstance(row[transcription_idx], dict) else row[transcription_idx])
                release = str(row[release_idx].get('value', '') if isinstance(row[release_idx], dict) else row[release_idx])
                tags = str(row[tags_idx].get('value', '') if isinstance(row[tags_idx], dict) else row[tags_idx])
                
                # Check if all requirements met
                all_met = (
                    'COMPLETE' in transcription.upper() and
                    ('YES' in release.upper() or release == 'TRUE' or release == '1') and
                    tags.strip() != ''
                )
                
                total_checks += 1
                
                # Expected value
                expected = "YES" if all_met else "NO"
                
                if ready_value == expected:
                    correct_logic += 1
                else:
                    logger.debug(f"Row {row_idx}: Expected '{expected}', got '{ready_value}' (transcription={transcription}, release={release}, tags={tags})")
        
        if total_checks == 0:
            return False, "❌ Cannot validate archive formula logic"
        
        logic_accuracy = correct_logic / total_checks
        
        if has_and_logic and logic_accuracy >= 0.8:
            return True, f"✅ Archive formula correct (uses AND logic, {correct_logic}/{total_checks} accurate)"
        elif logic_accuracy >= 0.8:
            return True, f"⚠️ Archive logic mostly correct ({correct_logic}/{total_checks}) but AND formula not clearly detected"
        else:
            return False, f"❌ Archive formula incorrect ({correct_logic}/{total_checks} accurate)"
    
    except Exception as e:
        logger.error(f"Error verifying archive formula: {e}", exc_info=True)
        return False, f"❌ Error checking archive formula: {str(e)}"


def verify_conditional_formatting(data: Dict[str, Any], sheet_name: str) -> Tuple[bool, str]:
    """
    Verify conditional formatting applied (simplified check - look for YES/NO values present).
    Full formatting check would require XML parsing of ODS file.
    """
    try:
        # Find archive ready column
        ready_col_idx = find_column_index(data, sheet_name, "Ready for Archive?")
        if ready_col_idx is None:
            ready_col_idx = find_column_index(data, sheet_name, "Ready for Archive")
            if ready_col_idx is None:
                ready_col_idx = find_column_index(data, sheet_name, "Archive Ready")
        
        if ready_col_idx is None:
            return False, "❌ Cannot verify formatting - archive column not found"
        
        rows = data['sheets'][sheet_name]
        
        has_yes = False
        has_no = False
        
        for row in rows[1:]:
            if ready_col_idx >= len(row):
                continue
            
            cell = row[ready_col_idx]
            cell_value = str(cell.get('value', '') if isinstance(cell, dict) else cell).strip().upper()
            
            if cell_value == "YES":
                has_yes = True
            elif cell_value == "NO":
                has_no = True
        
        if has_yes and has_no:
            # Both values present - formatting would be meaningful
            # Note: We can't easily verify actual colors without XML parsing
            return True, "✅ Conditional formatting applicable (YES/NO values present)"
        else:
            return False, "⚠️ Conditional formatting may not be applied or values inconsistent"
    
    except Exception as e:
        logger.error(f"Error verifying conditional formatting: {e}", exc_info=True)
        return False, f"❌ Error checking formatting: {str(e)}"


def verify_sort_order(data: Dict[str, Any], sheet_name: str) -> Tuple[bool, str]:
    """
    Verify data sorted by:
    1. Primary: Ready for Archive? (NO before YES)
    2. Secondary: Interview Date (Standardized) ascending (oldest first)
    """
    try:
        ready_col_idx = find_column_index(data, sheet_name, "Ready for Archive?")
        if ready_col_idx is None:
            ready_col_idx = find_column_index(data, sheet_name, "Ready for Archive")
            if ready_col_idx is None:
                ready_col_idx = find_column_index(data, sheet_name, "Archive Ready")
        
        date_col_idx = find_column_index(data, sheet_name, "Interview Date (Standardized)")
        
        if ready_col_idx is None or date_col_idx is None:
            return False, "❌ Cannot verify sort - required columns not found"
        
        rows = data['sheets'][sheet_name][1:]  # Skip header
        
        # Check primary sort: NO before YES
        found_yes = False
        no_after_yes = False
        
        for row in rows:
            if ready_col_idx >= len(row):
                continue
            
            ready_value = str(row[ready_col_idx].get('value', '') if isinstance(row[ready_col_idx], dict) else row[ready_col_idx]).strip().upper()
            
            if ready_value == "YES":
                found_yes = True
            elif ready_value == "NO" and found_yes:
                no_after_yes = True
                break
        
        if no_after_yes:
            return False, "❌ Sort order incorrect: NO rows found after YES rows"
        
        # Check secondary sort: within NO group, dates ascending
        no_rows = []
        for row in rows:
            if ready_col_idx >= len(row) or date_col_idx >= len(row):
                continue
            
            ready_value = str(row[ready_col_idx].get('value', '') if isinstance(row[ready_col_idx], dict) else row[ready_col_idx]).strip().upper()
            
            if ready_value == "NO":
                date_value = row[date_col_idx].get('value', '') if isinstance(row[date_col_idx], dict) else row[date_col_idx]
                if date_value:
                    no_rows.append(str(date_value))
        
        # Check if NO group dates are in ascending order
        dates_sorted = True
        for i in range(len(no_rows) - 1):
            if no_rows[i] > no_rows[i + 1]:
                dates_sorted = False
                logger.debug(f"Date sort issue: {no_rows[i]} > {no_rows[i+1]}")
                break
        
        if dates_sorted:
            return True, f"✅ Sort order correct (incomplete first, oldest dates first)"
        else:
            return False, f"⚠️ Sort order partially correct (primary sort OK, but dates may not be sorted)"
    
    except Exception as e:
        logger.error(f"Error verifying sort order: {e}", exc_info=True)
        return False, f"❌ Error checking sort: {str(e)}"


def verify_data_integrity(data: Dict[str, Any], sheet_name: str) -> Tuple[bool, str]:
    """
    Verify original data preserved and no formula errors.
    """
    try:
        rows = data['sheets'][sheet_name]
        
        # Check we have expected number of rows (header + at least 8 data rows)
        if len(rows) < 9:
            return False, f"❌ Data rows missing (found {len(rows)-1}, expected at least 10)"
        
        # Check for formula errors
        error_patterns = ['#VALUE!', '#REF!', '#NAME?', '#DIV/0!', '#N/A', '#NUM!']
        errors_found = []
        
        for row_idx, row in enumerate(rows):
            for col_idx, cell in enumerate(row):
                cell_value = str(cell.get('value', '') if isinstance(cell, dict) else cell)
                
                for error_pattern in error_patterns:
                    if error_pattern in cell_value:
                        errors_found.append(f"Row {row_idx+1}, Col {col_idx+1}: {error_pattern}")
        
        if errors_found:
            return False, f"❌ Formula errors detected: {', '.join(errors_found[:3])}"
        
        # Check original columns still exist
        required_columns = ['Interviewee Name', 'Birth Year', 'Interview Date']
        missing_columns = []
        
        for col_name in required_columns:
            if find_column_index(data, sheet_name, col_name) is None:
                missing_columns.append(col_name)
        
        if missing_columns:
            return False, f"❌ Original columns missing: {', '.join(missing_columns)}"
        
        return True, "✅ Data integrity maintained (no errors, all original data present)"
    
    except Exception as e:
        logger.error(f"Error verifying data integrity: {e}", exc_info=True)
        return False, f"❌ Error checking data integrity: {str(e)}"


def verify_oral_history(traj, env_info, task_info):
    """
    Main verifier for Oral History Archive Submission Validator task.
    
    Checks:
    1. Date standardization (YYYY-MM-DD format)
    2. Age calculation (reasonable values, uses formula)
    3. Archive readiness validation (AND logic)
    4. Conditional formatting (YES/NO values present)
    5. Sort order (incomplete first, oldest dates first)
    6. Data integrity (no errors, data preserved)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    possible_paths = [
        "/home/ga/Documents/oral_history_cleaned.ods",
        "/home/ga/Documents/oral_history_interviews.ods",
        "/home/ga/Documents/oral_history_interviews.csv"
    ]
    
    success = False
    file_info = None
    temp_dir = None
    
    for container_path in possible_paths:
        # Determine format from extension
        file_format = 'ods' if container_path.endswith('.ods') else 'csv'
        
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            container_path,
            [file_format]
        )
        
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            temp_dir = file_info.get('temp_dir')
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet file. Tried: {', '.join(possible_paths)}"
        }
    
    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        # Run all verification checks
        criteria_results = {}
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 6
        
        # 1. Date Standardization
        result, message = verify_date_standardization(data, sheet_name)
        criteria_results['date_standardization'] = result
        feedback_parts.append(message)
        if result:
            criteria_passed += 1
        
        # 2. Age Calculation
        result, message = verify_age_calculation(data, sheet_name)
        criteria_results['age_calculation'] = result
        feedback_parts.append(message)
        if result:
            criteria_passed += 1
        
        # 3. Archive Readiness Formula
        result, message = verify_archive_formula(data, sheet_name)
        criteria_results['archive_formula'] = result
        feedback_parts.append(message)
        if result:
            criteria_passed += 1
        
        # 4. Conditional Formatting
        result, message = verify_conditional_formatting(data, sheet_name)
        criteria_results['conditional_formatting'] = result
        feedback_parts.append(message)
        if result:
            criteria_passed += 1
        
        # 5. Sort Order
        result, message = verify_sort_order(data, sheet_name)
        criteria_results['sort_order'] = result
        feedback_parts.append(message)
        if result:
            criteria_passed += 1
        
        # 6. Data Integrity
        result, message = verify_data_integrity(data, sheet_name)
        criteria_results['data_integrity'] = result
        feedback_parts.append(message)
        if result:
            criteria_passed += 1
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 4/6 criteria (70%)
        
        # Add summary message
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent work! Archive validation complete")
        elif passed:
            feedback_parts.append("✅ Task completed successfully")
        else:
            feedback_parts.append(f"❌ Task incomplete ({criteria_passed}/{total_criteria} criteria met, need {int(total_criteria * 0.7)})")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": criteria_results
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
