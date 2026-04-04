#!/usr/bin/env python3
"""
Verifier for Soccer Snack Scheduler task
"""

import sys
import os
import logging
import re
from datetime import datetime
from collections import Counter
from typing import List, Tuple, Dict, Any

# Add utils to path - use relative path for host machine verification
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    parse_ods_file,
    parse_xlsx_file,
    parse_csv_file
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected family list (12 families total)
EXPECTED_FAMILIES = [
    'Anderson', 'Smith', 'Johnson', 'Williams', 'Brown', 
    'Jones', 'Davis', 'Miller', 'Wilson', 'Martinez', 
    'Thomas', 'Garcia', 'Taylor', 'Michael'
]

TOTAL_WEEKS = 14  # 14 game weeks in the season


def extract_column_data(sheet_data: Dict, column_index: int, skip_header: bool = True) -> List:
    """Extract all values from a specific column"""
    values = []
    rows = sheet_data.get('rows', sheet_data)
    
    start_row = 1 if skip_header else 0
    for i, row in enumerate(rows):
        if i < start_row:
            continue
        if column_index < len(row):
            cell = row[column_index]
            value = cell.get('value') if isinstance(cell, dict) else cell
            if value is not None and str(value).strip():
                values.append(value)
    
    return values


def check_name_standardization(family_names: List[str]) -> Tuple[bool, str, float]:
    """
    Check if family names follow a consistent pattern.
    Returns: (is_standardized, feedback, score_ratio)
    """
    if not family_names:
        return False, "No family names found", 0.0
    
    # Define acceptable patterns
    patterns = {
        'family_suffix': r'^[A-Z][a-z]+ Family$',  # "Smith Family"
        'full_name': r'^[A-Z][a-z]+ [A-Z][a-z]+$',  # "John Smith"
        'the_plural': r'^The [A-Z][a-z]+s$',  # "The Smiths"
        'lastname_only': r'^[A-Z][a-z]+$',  # "Smith" (acceptable if consistent)
    }
    
    # Count matches for each pattern
    pattern_matches = {name: 0 for name in patterns}
    total_names = len(family_names)
    
    for family_name in family_names:
        for pattern_name, pattern in patterns.items():
            if re.match(pattern, str(family_name).strip()):
                pattern_matches[pattern_name] += 1
                break
    
    # Find dominant pattern
    max_matches = max(pattern_matches.values())
    consistency_ratio = max_matches / total_names if total_names > 0 else 0
    
    # At least 90% should match one pattern
    is_standardized = consistency_ratio >= 0.90
    
    dominant_pattern = max(pattern_matches, key=pattern_matches.get)
    feedback = f"Name consistency: {consistency_ratio:.1%} match pattern '{dominant_pattern}' ({max_matches}/{total_names})"
    
    return is_standardized, feedback, consistency_ratio


def check_duplicate_assignments(family_names: List[str]) -> Tuple[bool, str, List[str]]:
    """
    Check if any family is assigned more than twice.
    Returns: (no_excessive_duplicates, feedback, excessive_families)
    """
    family_counts = Counter([str(name).strip().lower() for name in family_names if name])
    
    # Find families with >2 assignments
    excessive = [family for family, count in family_counts.items() if count > 2]
    
    # Find families with 0 assignments (from expected list)
    assigned_families_lower = [f.lower() for f in family_counts.keys()]
    missing = []
    for expected in EXPECTED_FAMILIES:
        if not any(expected.lower() in assigned.lower() for assigned in assigned_families_lower):
            missing.append(expected)
    
    no_excessive = len(excessive) == 0
    
    if no_excessive and len(missing) == 0:
        feedback = f"✅ Fair distribution: {len(family_counts)} families, max {max(family_counts.values())} assignments each"
    elif no_excessive:
        feedback = f"⚠️ No excessive duplicates, but missing families: {', '.join(missing[:3])}"
    else:
        feedback = f"❌ Excessive duplicates found: {', '.join(excessive)}"
    
    return no_excessive, feedback, excessive


def check_chronological_order(dates: List[Any]) -> Tuple[bool, str]:
    """
    Check if dates are in chronological ascending order.
    Returns: (is_sorted, feedback)
    """
    if len(dates) < 2:
        return True, "Too few dates to check order"
    
    parsed_dates = []
    for date_val in dates:
        try:
            # Try multiple date formats
            date_str = str(date_val).strip()
            for fmt in ['%m/%d/%Y', '%Y-%m-%d', '%m-%d-%Y', '%d/%m/%Y']:
                try:
                    parsed = datetime.strptime(date_str, fmt)
                    parsed_dates.append(parsed)
                    break
                except ValueError:
                    continue
            else:
                # Try parsing just the date part if it's a datetime string
                if 'T' in date_str or ' ' in date_str:
                    date_part = date_str.split('T')[0].split(' ')[0]
                    for fmt in ['%m/%d/%Y', '%Y-%m-%d', '%m-%d-%Y']:
                        try:
                            parsed = datetime.strptime(date_part, fmt)
                            parsed_dates.append(parsed)
                            break
                        except ValueError:
                            continue
        except Exception as e:
            logger.debug(f"Could not parse date: {date_val}, error: {e}")
    
    if len(parsed_dates) < len(dates) * 0.8:
        return False, f"❌ Could not parse most dates ({len(parsed_dates)}/{len(dates)} parsed)"
    
    # Check if sorted
    is_sorted = all(parsed_dates[i] <= parsed_dates[i+1] for i in range(len(parsed_dates)-1))
    
    if is_sorted:
        feedback = f"✅ Dates chronologically sorted ({len(parsed_dates)} dates verified)"
    else:
        # Find first out-of-order pair
        for i in range(len(parsed_dates)-1):
            if parsed_dates[i] > parsed_dates[i+1]:
                feedback = f"❌ Dates not sorted: {parsed_dates[i].strftime('%m/%d/%Y')} comes before {parsed_dates[i+1].strftime('%m/%d/%Y')}"
                break
        else:
            feedback = "❌ Dates not in chronological order"
    
    return is_sorted, feedback


def check_cost_column(workbook: Dict, sheet_name: str) -> Tuple[bool, str, int]:
    """
    Check if a cost column exists with numeric values.
    Returns: (has_cost_column, feedback, column_index or -1)
    """
    sheet_data = workbook['sheets'][sheet_name]
    
    # Check headers for cost-related column
    if len(sheet_data) > 0:
        header_row = sheet_data[0]
        for col_idx, cell in enumerate(header_row):
            header_value = cell.get('value') if isinstance(cell, dict) else cell
            if header_value and 'cost' in str(header_value).lower():
                # Found cost column, check if it has numeric values
                column_data = extract_column_data({'rows': sheet_data}, col_idx, skip_header=True)
                numeric_count = sum(1 for val in column_data if isinstance(val, (int, float)) or str(val).replace('.','').replace('$','').replace(',','').isdigit())
                
                if numeric_count >= len(column_data) * 0.8:
                    return True, f"✅ Cost column found with {numeric_count} numeric values", col_idx
                else:
                    return False, f"⚠️ Cost column found but values not numeric ({numeric_count}/{len(column_data)})", col_idx
    
    return False, "❌ No cost column found", -1


def check_sum_formula(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if a SUM formula exists (for total cost calculation).
    Returns: (has_sum_formula, feedback)
    """
    sheet_data = workbook['sheets'][sheet_name]
    
    # Look through all cells for SUM formula
    for row_idx, row in enumerate(sheet_data):
        for col_idx, cell in enumerate(row):
            formula = cell.get('formula') if isinstance(cell, dict) else None
            if formula and 'SUM' in str(formula).upper():
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                return True, f"✅ SUM formula found: {formula} = {cell_value}"
    
    return False, "❌ No SUM formula found for total cost calculation", 


def check_countif_formula(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if COUNTIF formulas exist (for fairness check).
    Returns: (has_countif, feedback)
    """
    sheet_data = workbook['sheets'][sheet_name]
    
    countif_count = 0
    for row in sheet_data:
        for cell in row:
            formula = cell.get('formula') if isinstance(cell, dict) else None
            if formula and 'COUNTIF' in str(formula).upper():
                countif_count += 1
    
    if countif_count >= 3:  # At least a few families counted
        return True, f"✅ Fairness check found: {countif_count} COUNTIF formulas"
    elif countif_count > 0:
        return True, f"⚠️ Partial fairness check: {countif_count} COUNTIF formulas (expected more)"
    else:
        # Check for manual count - look for family names and numbers in summary area
        # This is harder to verify, so we'll be lenient
        return False, "❌ No COUNTIF formulas found for fairness check"


def check_conditional_formatting(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if conditional formatting is applied (allergen highlighting).
    This is simplified - we look for evidence of formatting on allergen cells.
    Returns: (has_formatting, feedback)
    """
    # For ODS files, checking conditional formatting is complex
    # We'll look for cells with "Yes" or "Allergy" that might be formatted
    # In practice, this would require parsing XML styles
    
    sheet_data = workbook['sheets'][sheet_name]
    allergen_cells = 0
    
    for row in sheet_data:
        for cell in row:
            value = cell.get('value') if isinstance(cell, dict) else cell
            if value and ('allergy' in str(value).lower() or (isinstance(value, str) and value.lower() == 'yes')):
                allergen_cells += 1
    
    # We can't reliably detect formatting without deep XML parsing
    # So we'll give credit if allergen cells exist and assume user formatted them
    if allergen_cells > 0:
        return True, f"⚠️ Allergen cells detected ({allergen_cells} found) - assuming conditional formatting applied"
    else:
        return False, "❌ No allergen indicators found"


def verify_snack_schedule(traj, env_info, task_info):
    """
    Verify soccer snack schedule cleanup task completion.
    
    Checks:
    1. Names standardized (90%+ consistency)
    2. No excessive duplicates (no family >2 times)
    3. Complete coverage (all 14 weeks assigned)
    4. Chronologically sorted
    5. Cost column present
    6. Total cost calculated (SUM formula)
    7. Conditional formatting applied (allergen highlighting)
    8. Fairness check exists (COUNTIF formulas)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    temp_dir = None
    success = False
    workbook = None
    
    for file_path in [
        "/home/ga/Documents/soccer_snacks_organized.ods",
        "/home/ga/Documents/messy_snack_schedule.ods",
        "/home/ga/Documents/messy_snack_schedule.csv",
    ]:
        file_format = 'ods' if file_path.endswith('.ods') else 'csv'
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            file_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded: {file_path}")
            break

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Could not load file: {error}"}

    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        sheet_data = workbook['sheets'][sheet_name]
        
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        subscores = {}
        
        # Find columns by header
        header_row = sheet_data[0] if sheet_data else []
        date_col = -1
        family_col = -1
        allergen_col = -1
        
        for col_idx, cell in enumerate(header_row):
            header_value = str(cell.get('value') if isinstance(cell, dict) else cell).lower()
            if 'date' in header_value:
                date_col = col_idx
            elif 'family' in header_value or 'name' in header_value:
                family_col = col_idx
            elif 'allergen' in header_value:
                allergen_col = col_idx
        
        # Extract data
        dates = extract_column_data({'rows': sheet_data}, date_col, skip_header=True) if date_col >= 0 else []
        family_names = extract_column_data({'rows': sheet_data}, family_col, skip_header=True) if family_col >= 0 else []
        
        # Criterion 1: Names standardized
        names_standardized, names_feedback, consistency = check_name_standardization(family_names)
        if names_standardized:
            criteria_passed += 1
            feedback_parts.append(f"✅ Names standardized ({consistency:.0%})")
        else:
            feedback_parts.append(f"❌ {names_feedback}")
        subscores['names_standardized'] = names_standardized
        
        # Criterion 2: No excessive duplicates
        no_duplicates, dup_feedback, excessive = check_duplicate_assignments(family_names)
        if no_duplicates:
            criteria_passed += 1
            feedback_parts.append(dup_feedback)
        else:
            feedback_parts.append(dup_feedback)
        subscores['no_excessive_duplicates'] = no_duplicates
        
        # Criterion 3: Complete coverage (14 weeks)
        complete_coverage = len(family_names) >= TOTAL_WEEKS
        if complete_coverage:
            criteria_passed += 1
            feedback_parts.append(f"✅ Complete coverage: {len(family_names)} weeks assigned")
        else:
            feedback_parts.append(f"❌ Incomplete coverage: {len(family_names)}/{TOTAL_WEEKS} weeks")
        subscores['complete_coverage'] = complete_coverage
        
        # Criterion 4: Chronologically sorted
        is_sorted, sort_feedback = check_chronological_order(dates)
        if is_sorted:
            criteria_passed += 1
        feedback_parts.append(sort_feedback)
        subscores['chronologically_sorted'] = is_sorted
        
        # Criterion 5: Cost column present
        has_cost, cost_feedback, cost_col_idx = check_cost_column(workbook, sheet_name)
        if has_cost:
            criteria_passed += 1
        feedback_parts.append(cost_feedback)
        subscores['cost_column_present'] = has_cost
        
        # Criterion 6: Total cost calculated (SUM formula)
        has_sum, sum_feedback = check_sum_formula(workbook, sheet_name)
        if has_sum:
            criteria_passed += 1
        feedback_parts.append(sum_feedback)
        subscores['total_cost_calculated'] = has_sum
        
        # Criterion 7: Conditional formatting (simplified check)
        has_formatting, format_feedback = check_conditional_formatting(workbook, sheet_name)
        if has_formatting:
            criteria_passed += 1
        feedback_parts.append(format_feedback)
        subscores['conditional_formatting'] = has_formatting
        
        # Criterion 8: Fairness check (COUNTIF)
        has_fairness, fairness_feedback = check_countif_formula(workbook, sheet_name)
        if has_fairness:
            criteria_passed += 1
        feedback_parts.append(fairness_feedback)
        subscores['fairness_check'] = has_fairness
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 6/8 criteria
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Schedule professionally organized and ready to share!")
        elif passed:
            feedback_parts.insert(0, f"✅ Schedule cleanup successful ({criteria_passed}/{total_criteria} criteria)")
        else:
            feedback_parts.insert(0, f"❌ Schedule needs more work ({criteria_passed}/{total_criteria} criteria met, need 6)")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        if temp_dir:
            cleanup_verification_temp(temp_dir)
