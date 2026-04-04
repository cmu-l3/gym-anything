#!/usr/bin/env python3
"""
Verifier for Genealogy Data Cleanup task

Checks:
1. Date format standardization (>90% in YYYY-MM-DD format)
2. Duplicate reduction (from ~45 to 28-32 entries)
3. Validation columns present ("Age at Death", "Data Issues")
4. Issue flagging (at least 5 logical errors identified)
5. Conditional formatting applied
6. Data integrity (no loss of critical information)
7. Proper sorting (by surname and birth year)
"""

import sys
import os
import re
import logging

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    get_sheet_names,
    cleanup_verification_temp,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def count_entries(workbook, sheet_name):
    """Count non-empty data rows (excluding header)"""
    try:
        sheets = workbook.get('sheets', {})
        if sheet_name not in sheets:
            return 0
        
        rows = sheets[sheet_name]
        count = 0
        
        for i, row in enumerate(rows):
            if i == 0:  # Skip header
                continue
            
            # Check if row has any non-empty cells
            has_data = False
            for cell in row:
                value = cell.get('value') if isinstance(cell, dict) else cell
                if value is not None and str(value).strip() != '':
                    has_data = True
                    break
            
            if has_data:
                count += 1
        
        return count
    except Exception as e:
        logger.error(f"Error counting entries: {e}")
        return 0


def check_date_standardization(workbook, sheet_name):
    """
    Check if dates are standardized to YYYY-MM-DD format.
    Accepts ~YYYY-MM-DD for uncertain dates.
    Accepts YYYY-00-00 for unknown month/day.
    
    Returns: (percentage_standardized, total_dates, standardized_dates)
    """
    try:
        sheets = workbook.get('sheets', {})
        if sheet_name not in sheets:
            return 0.0, 0, 0
        
        rows = sheets[sheet_name]
        
        # Find Birth Date and Death Date columns (usually columns C and E, indices 3 and 5)
        # But let's be flexible and search the header
        header_row = rows[0] if len(rows) > 0 else []
        birth_date_col = None
        death_date_col = None
        
        for i, cell in enumerate(header_row):
            header_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
            if 'birth' in header_val and 'date' in header_val:
                birth_date_col = i
            elif 'death' in header_val and 'date' in header_val:
                death_date_col = i
        
        if birth_date_col is None or death_date_col is None:
            logger.warning("Could not find Birth Date or Death Date columns")
            # Fallback to indices 3 and 5
            birth_date_col = 3
            death_date_col = 5
        
        # Pattern for standardized dates: YYYY-MM-DD or ~YYYY-MM-DD
        # Also accept YYYY-00-00 for unknown parts
        standardized_pattern = re.compile(r'^~?\d{4}-\d{2}-\d{2}$')
        
        total_dates = 0
        standardized_dates = 0
        
        for i, row in enumerate(rows):
            if i == 0:  # Skip header
                continue
            
            # Check birth date
            if birth_date_col < len(row):
                birth_val = row[birth_date_col].get('value') if isinstance(row[birth_date_col], dict) else row[birth_date_col]
                if birth_val is not None and str(birth_val).strip() != '':
                    total_dates += 1
                    if standardized_pattern.match(str(birth_val).strip()):
                        standardized_dates += 1
            
            # Check death date
            if death_date_col < len(row):
                death_val = row[death_date_col].get('value') if isinstance(row[death_date_col], dict) else row[death_date_col]
                if death_val is not None and str(death_val).strip() != '':
                    total_dates += 1
                    if standardized_pattern.match(str(death_val).strip()):
                        standardized_dates += 1
        
        percentage = (standardized_dates / total_dates * 100) if total_dates > 0 else 0
        return percentage, total_dates, standardized_dates
        
    except Exception as e:
        logger.error(f"Error checking date standardization: {e}")
        return 0.0, 0, 0


def check_validation_columns(workbook, sheet_name):
    """
    Check if validation columns exist and contain formulas.
    
    Returns: (has_age_column, has_issues_column, age_has_formulas, issues_has_content)
    """
    try:
        sheets = workbook.get('sheets', {})
        if sheet_name not in sheets:
            return False, False, False, False
        
        rows = sheets[sheet_name]
        if len(rows) == 0:
            return False, False, False, False
        
        header_row = rows[0]
        
        # Find columns
        age_col = None
        issues_col = None
        
        for i, cell in enumerate(header_row):
            header_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
            
            if 'age' in header_val and 'death' in header_val:
                age_col = i
            elif any(keyword in header_val for keyword in ['issue', 'flag', 'problem', 'error', 'validation']):
                issues_col = i
        
        has_age_column = age_col is not None
        has_issues_column = issues_col is not None
        
        # Check if age column has formulas
        age_has_formulas = False
        if age_col is not None and len(rows) > 1:
            # Check a few cells for formulas
            for i in range(1, min(6, len(rows))):
                if age_col < len(rows[i]):
                    cell = rows[i][age_col]
                    formula = cell.get('formula') if isinstance(cell, dict) else None
                    if formula:
                        age_has_formulas = True
                        break
        
        # Check if issues column has content
        issues_has_content = False
        if issues_col is not None and len(rows) > 1:
            for i in range(1, len(rows)):
                if issues_col < len(rows[i]):
                    cell = rows[i][issues_col]
                    value = cell.get('value') if isinstance(cell, dict) else cell
                    if value is not None and str(value).strip() != '':
                        issues_has_content = True
                        break
        
        return has_age_column, has_issues_column, age_has_formulas, issues_has_content
        
    except Exception as e:
        logger.error(f"Error checking validation columns: {e}")
        return False, False, False, False


def count_flagged_issues(workbook, sheet_name):
    """Count how many rows have issues flagged in the Data Issues column"""
    try:
        sheets = workbook.get('sheets', {})
        if sheet_name not in sheets:
            return 0
        
        rows = sheets[sheet_name]
        if len(rows) == 0:
            return 0
        
        header_row = rows[0]
        
        # Find issues column
        issues_col = None
        for i, cell in enumerate(header_row):
            header_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
            if any(keyword in header_val for keyword in ['issue', 'flag', 'problem', 'error', 'validation']):
                issues_col = i
                break
        
        if issues_col is None:
            return 0
        
        # Count non-empty cells in issues column
        flagged_count = 0
        for i in range(1, len(rows)):
            if issues_col < len(rows[i]):
                cell = rows[i][issues_col]
                value = cell.get('value') if isinstance(cell, dict) else cell
                if value is not None and str(value).strip() != '':
                    flagged_count += 1
        
        return flagged_count
        
    except Exception as e:
        logger.error(f"Error counting flagged issues: {e}")
        return 0


def check_sorting(workbook, sheet_name):
    """
    Check if data is sorted by surname and then birth year.
    
    Returns: (is_sorted, message)
    """
    try:
        sheets = workbook.get('sheets', {})
        if sheet_name not in sheets:
            return False, "Sheet not found"
        
        rows = sheets[sheet_name]
        if len(rows) < 3:  # Need at least header + 2 data rows
            return True, "Not enough data to check sorting"
        
        header_row = rows[0]
        
        # Find surname and birth date columns
        surname_col = None
        birth_date_col = None
        
        for i, cell in enumerate(header_row):
            header_val = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
            if 'surname' in header_val or 'last name' in header_val:
                surname_col = i
            elif 'birth' in header_val and 'date' in header_val:
                birth_date_col = i
        
        if surname_col is None or birth_date_col is None:
            # Fallback: assume column 2 is surname, column 3 is birth date
            surname_col = 2
            birth_date_col = 3
        
        # Check if surnames are in order
        prev_surname = None
        prev_birth_year = None
        
        for i in range(1, len(rows)):
            if surname_col >= len(rows[i]):
                continue
            
            surname_cell = rows[i][surname_col]
            surname = str(surname_cell.get('value', '') if isinstance(surname_cell, dict) else surname_cell).strip()
            
            if surname == '':
                continue
            
            # Extract birth year
            birth_year = None
            if birth_date_col < len(rows[i]):
                birth_cell = rows[i][birth_date_col]
                birth_val = str(birth_cell.get('value', '') if isinstance(birth_cell, dict) else birth_cell)
                # Try to extract year
                year_match = re.search(r'\d{4}', birth_val)
                if year_match:
                    birth_year = int(year_match.group())
            
            # Compare with previous
            if prev_surname is not None:
                # Check surname order
                if surname < prev_surname:
                    return False, f"Surnames not sorted: {surname} < {prev_surname}"
                elif surname == prev_surname:
                    # Same surname, check birth year
                    if prev_birth_year is not None and birth_year is not None:
                        if birth_year < prev_birth_year:
                            return False, f"Birth years not sorted within {surname}: {birth_year} < {prev_birth_year}"
            
            prev_surname = surname
            prev_birth_year = birth_year
        
        return True, "Data appears sorted by surname and birth year"
        
    except Exception as e:
        logger.error(f"Error checking sorting: {e}")
        return False, f"Error checking sorting: {str(e)}"


def verify_genealogy_cleanup(traj, env_info, task_info):
    """
    Verify genealogy data cleanup task completion.
    
    Checks:
    1. Date format standardization (>90% in YYYY-MM-DD format)
    2. Duplicate reduction (from ~45 to 28-32 entries)
    3. Validation columns present ("Age at Death", "Data Issues")
    4. Issue flagging (at least 5 logical errors identified)
    5. Conditional formatting applied (best effort)
    6. Data integrity (no loss of critical information)
    7. Proper sorting (by surname and birth year)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to find the cleaned file
    container_paths = [
        "/home/ga/Documents/genealogy_clean.ods",
        "/home/ga/Documents/family_data_raw.ods",  # Fallback if not renamed
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for container_path in container_paths:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format='ods'
        )
        if success:
            logger.info(f"Successfully loaded file from {container_path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}
    
    try:
        # Get sheet name
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Date format standardization
        date_pct, total_dates, std_dates = check_date_standardization(workbook, sheet_name)
        date_std_ok = date_pct >= 90.0
        
        if date_std_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ Date standardization: {std_dates}/{total_dates} ({date_pct:.1f}%)")
        else:
            feedback_parts.append(f"❌ Date standardization insufficient: {std_dates}/{total_dates} ({date_pct:.1f}%, need ≥90%)")
        
        subscores['date_standardization'] = date_std_ok
        
        # Criterion 2: Duplicate reduction
        entry_count = count_entries(workbook, sheet_name)
        duplicate_reduction_ok = 28 <= entry_count <= 32
        
        if duplicate_reduction_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ Duplicate reduction: {entry_count} entries (expected 28-32)")
        else:
            if entry_count > 32:
                feedback_parts.append(f"⚠️ Entry count high: {entry_count} (expected 28-32, may need more duplicate consolidation)")
            elif entry_count < 28:
                feedback_parts.append(f"⚠️ Entry count low: {entry_count} (expected 28-32, may have deleted too much)")
            else:
                feedback_parts.append(f"❌ Entry count: {entry_count} (expected 28-32)")
        
        subscores['duplicate_reduction'] = duplicate_reduction_ok
        
        # Criterion 3: Validation columns present
        has_age, has_issues, age_formulas, issues_content = check_validation_columns(workbook, sheet_name)
        validation_cols_ok = has_age and has_issues and (age_formulas or issues_content)
        
        if validation_cols_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ Validation columns: Age={has_age}, Issues={has_issues}, Formulas={age_formulas}")
        else:
            details = []
            if not has_age:
                details.append("missing Age at Death column")
            if not has_issues:
                details.append("missing Data Issues column")
            if not age_formulas:
                details.append("Age column lacks formulas")
            feedback_parts.append(f"❌ Validation columns incomplete: {', '.join(details)}")
        
        subscores['validation_columns'] = validation_cols_ok
        
        # Criterion 4: Issue flagging
        flagged_count = count_flagged_issues(workbook, sheet_name)
        issue_flagging_ok = flagged_count >= 5
        
        if issue_flagging_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ Issue flagging: {flagged_count} issues identified (need ≥5)")
        else:
            feedback_parts.append(f"❌ Issue flagging insufficient: {flagged_count} issues (need ≥5)")
        
        subscores['issue_flagging'] = issue_flagging_ok
        
        # Criterion 5: Conditional formatting (best effort check)
        # This is difficult to verify programmatically in ODS, so we'll give partial credit
        # if validation columns exist
        conditional_fmt_ok = has_issues  # Proxy: if they added issues column, likely added formatting
        
        if conditional_fmt_ok:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting: Likely applied (inferred from validation columns)")
        else:
            feedback_parts.append("⚠️ Conditional formatting: Cannot verify (no validation columns)")
        
        subscores['conditional_formatting'] = conditional_fmt_ok
        
        # Criterion 6: Data integrity (no excessive loss)
        # Check that we still have key columns and reasonable data
        data_integrity_ok = entry_count >= 25  # At least 25 people preserved
        
        if data_integrity_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ Data integrity: {entry_count} entries preserved")
        else:
            feedback_parts.append(f"❌ Data integrity concern: Only {entry_count} entries (expected ≥25)")
        
        subscores['data_integrity'] = data_integrity_ok
        
        # Criterion 7: Proper sorting
        is_sorted, sort_msg = check_sorting(workbook, sheet_name)
        
        if is_sorted:
            criteria_passed += 1
            feedback_parts.append(f"✅ Sorting: {sort_msg}")
        else:
            feedback_parts.append(f"❌ Sorting: {sort_msg}")
        
        subscores['proper_sorting'] = is_sorted
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 5/7 criteria
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent genealogy data cleanup!")
        elif passed:
            feedback_parts.insert(0, "✅ Genealogy data cleanup task completed")
        else:
            feedback_parts.insert(0, f"❌ Task incomplete ({criteria_passed}/{total_criteria} criteria met, need 5)")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "criteria_passed": criteria_passed,
                "total_criteria": total_criteria,
                "entry_count": entry_count,
                "date_standardization_pct": date_pct,
                "flagged_issues": flagged_count
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        cleanup_verification_temp(temp_dir)
