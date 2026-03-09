#!/usr/bin/env python3
"""
Verifier for Meal Train Organizer task.
Checks for complete coverage, dietary compliance, and conflict resolution.
"""

import sys
import os
import logging
from datetime import datetime, timedelta

# Do not use /workspace/utils, since verification runs on host machine
# Use relative path to utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_date_value(date_val):
    """
    Parse various date formats into a datetime object.
    Handles ISO format, Excel serial dates, and common date strings.
    """
    if date_val is None:
        return None
    
    # If already a datetime object (shouldn't happen but be safe)
    if isinstance(date_val, datetime):
        return date_val
    
    # Try parsing as string in various formats
    if isinstance(date_val, str):
        date_str = date_val.strip()
        for fmt in [
            '%Y-%m-%d',
            '%m/%d/%Y',
            '%d/%m/%Y',
            '%Y/%m/%d',
            '%m-%d-%Y',
            '%d-%m-%Y',
            'March %d, %Y',
            '%B %d, %Y'
        ]:
            try:
                return datetime.strptime(date_str, fmt)
            except ValueError:
                continue
        
        # Try to extract year/month/day if present in string
        if '2025' in date_str and ('march' in date_str.lower() or '03' in date_str or '-3-' in date_str):
            # Extract day number
            import re
            day_match = re.search(r'\b(\d{1,2})\b', date_str)
            if day_match:
                day = int(day_match.group(1))
                if 1 <= day <= 14:
                    return datetime(2025, 3, day)
    
    # Try numeric value (Excel serial date)
    try:
        # Excel serial date: days since 1899-12-30
        serial = float(date_val)
        excel_epoch = datetime(1899, 12, 30)
        return excel_epoch + timedelta(days=serial)
    except (ValueError, TypeError):
        pass
    
    return None


def extract_dates_from_sheet(sheet_data, date_column_idx=0):
    """
    Extract and parse all dates from a specific column in sheet data.
    Returns list of datetime objects.
    """
    dates = []
    rows = sheet_data if isinstance(sheet_data, list) else []
    
    for row_idx, row in enumerate(rows):
        if row_idx == 0:  # Skip header
            continue
        
        if len(row) <= date_column_idx:
            continue
        
        cell_data = row[date_column_idx]
        date_val = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
        
        parsed_date = parse_date_value(date_val)
        if parsed_date:
            dates.append(parsed_date)
    
    return dates


def check_date_coverage(sheet_data):
    """
    Check if all 14 required dates (March 1-14, 2025) are covered exactly once.
    Returns: (all_covered, gaps, duplicates, date_counts)
    """
    # Generate required dates
    required_dates = [datetime(2025, 3, day) for day in range(1, 15)]
    
    # Extract dates from spreadsheet
    assigned_dates = extract_dates_from_sheet(sheet_data, date_column_idx=0)
    
    # Count occurrences of each required date
    date_counts = {}
    for req_date in required_dates:
        count = sum(1 for assigned_date in assigned_dates 
                   if assigned_date.date() == req_date.date())
        date_counts[req_date.date()] = count
    
    # Identify gaps (count = 0) and duplicates (count > 1)
    gaps = [date for date, count in date_counts.items() if count == 0]
    duplicates = [date for date, count in date_counts.items() if count > 1]
    
    all_covered = all(count == 1 for count in date_counts.values())
    
    return all_covered, gaps, duplicates, date_counts


def check_dietary_compliance(sheet_data, meat_column_idx=3):
    """
    Check if all meals are vegetarian (no meat).
    Returns: (all_vegetarian, violations)
    """
    violations = []
    rows = sheet_data if isinstance(sheet_data, list) else []
    
    for row_idx, row in enumerate(rows):
        if row_idx == 0:  # Skip header
            continue
        
        if len(row) <= meat_column_idx:
            continue
        
        cell_data = row[meat_column_idx]
        meat_val = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
        
        if meat_val is None:
            continue
        
        # Check if meat is present
        meat_str = str(meat_val).strip().lower()
        # Vegetarian indicators
        vegetarian_values = ['no', 'n', 'false', '0', 'vegetarian', 'veg', '']
        
        if meat_str not in vegetarian_values and meat_str != '':
            # Check for explicit "yes" or meat-related terms
            if meat_str in ['yes', 'y', 'true', '1', 'meat']:
                violations.append((row_idx + 1, meat_val))
    
    all_vegetarian = len(violations) == 0
    return all_vegetarian, violations


def check_conflict_analysis(sheet_data):
    """
    Check if conflict analysis was performed (evidence of added columns).
    Look for columns with keywords: conflict, status, flag, issue, dietary, etc.
    """
    if not sheet_data or len(sheet_data) == 0:
        return False
    
    # Get header row
    header_row = sheet_data[0]
    column_names = []
    
    for cell in header_row:
        val = cell.get('value') if isinstance(cell, dict) else cell
        if val:
            column_names.append(str(val).lower())
    
    # Analysis indicators
    analysis_keywords = [
        'conflict', 'status', 'flag', 'issue', 'problem', 
        'check', 'dietary', 'coverage', 'gap', 'duplicate',
        'ok', 'violation', 'analysis'
    ]
    
    has_analysis = any(
        any(keyword in col_name for keyword in analysis_keywords)
        for col_name in column_names
        if len(col_name) > 0
    )
    
    return has_analysis


def check_summary_present(sheet_data):
    """
    Check if summary statistics are present.
    Look for cells containing summary keywords and numerical counts.
    """
    summary_keywords = [
        'total', 'count', 'coverage', 'conflict', 'gap', 
        'violation', 'summary', 'statistic'
    ]
    
    # Check first few rows and last few rows for summary data
    rows_to_check = []
    if len(sheet_data) > 0:
        rows_to_check.extend(sheet_data[:5])  # First 5 rows
    if len(sheet_data) > 20:
        rows_to_check.extend(sheet_data[-5:])  # Last 5 rows
    
    for row in rows_to_check:
        for cell in row:
            val = cell.get('value') if isinstance(cell, dict) else cell
            if val and isinstance(val, str):
                val_lower = val.lower()
                if any(keyword in val_lower for keyword in summary_keywords):
                    return True
    
    return False


def verify_meal_train_organizer(traj, env_info, task_info):
    """
    Verify meal train organizer task completion.
    
    Checks:
    1. Complete coverage: All 14 dates have exactly one meal
    2. Dietary compliance: All meals are vegetarian
    3. No date conflicts: Each date appears exactly once
    4. Conflict identified: Evidence of analysis columns
    5. Gap resolution: Missing dates now covered
    6. Summary present: Coverage statistics calculated
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    possible_paths = [
        "/home/ga/Documents/meal_train_resolved.ods",
        "/home/ga/Documents/meal_train_signups.ods",
        "/home/ga/Documents/meal_train_signups.csv"
    ]
    
    success = False
    file_info = None
    
    for container_path in possible_paths:
        # Determine format from extension
        if container_path.endswith('.csv'):
            formats = ['csv', 'ods']
        else:
            formats = ['ods', 'csv']
        
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            formats
        )
        
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load meal train file: {error}"
        }
    
    try:
        # Get sheet data
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = sheet_names[0]
        sheet_rows = data['sheets'][sheet_name]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: Complete coverage
        all_covered, gaps, duplicates, date_counts = check_date_coverage(sheet_rows)
        
        if all_covered:
            criteria_passed += 1
            feedback_parts.append("✅ Complete coverage: All 14 dates have exactly one meal")
        else:
            feedback_parts.append(
                f"❌ Incomplete coverage: {len(gaps)} gaps, {len(duplicates)} duplicates"
            )
        
        # Criterion 2: Dietary compliance
        all_vegetarian, violations = check_dietary_compliance(sheet_rows)
        
        if all_vegetarian:
            criteria_passed += 1
            feedback_parts.append("✅ Dietary compliance: All meals are vegetarian")
        else:
            feedback_parts.append(
                f"❌ Dietary violations: {len(violations)} meals contain meat"
            )
        
        # Criterion 3: No date conflicts (same as complete coverage check)
        no_duplicates = len(duplicates) == 0
        
        if no_duplicates:
            criteria_passed += 1
            feedback_parts.append("✅ No date conflicts: Each date appears exactly once")
        else:
            feedback_parts.append(
                f"❌ Date conflicts: {len(duplicates)} dates have multiple signups"
            )
        
        # Criterion 4: Conflict analysis evidence
        has_analysis = check_conflict_analysis(sheet_rows)
        
        if has_analysis:
            criteria_passed += 1
            feedback_parts.append("✅ Conflict analysis: Evidence of analysis columns found")
        else:
            feedback_parts.append("⚠️ No conflict analysis columns detected")
        
        # Criterion 5: Gap resolution
        # Check if original gaps (March 7, 10) are now covered
        original_gap_dates = [datetime(2025, 3, 7).date(), datetime(2025, 3, 10).date()]
        gaps_resolved = all(
            date_counts.get(gap_date, 0) >= 1 
            for gap_date in original_gap_dates
        )
        
        if gaps_resolved:
            criteria_passed += 1
            feedback_parts.append("✅ Gap resolution: Previously missing dates now covered")
        else:
            uncovered = [date for date in original_gap_dates if date_counts.get(date, 0) == 0]
            feedback_parts.append(
                f"❌ Gaps remain: {len(uncovered)} originally missing dates still uncovered"
            )
        
        # Criterion 6: Summary statistics
        has_summary = check_summary_present(sheet_rows)
        
        if has_summary:
            criteria_passed += 1
            feedback_parts.append("✅ Summary present: Coverage statistics found")
        else:
            feedback_parts.append("⚠️ No summary statistics detected")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 70% (4/6 criteria)
        
        # Add final summary
        if passed and score >= 95:
            feedback_parts.append("🎉 Excellent meal train organization!")
        elif passed:
            feedback_parts.append("✅ Meal train conflicts resolved")
        else:
            feedback_parts.append("❌ Meal train requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "complete_coverage": all_covered,
                "dietary_compliance": all_vegetarian,
                "no_conflicts": no_duplicates,
                "analysis_performed": has_analysis,
                "gaps_resolved": gaps_resolved,
                "summary_present": has_summary
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
        cleanup_verification_temp(file_info.get('temp_dir') if file_info else None)
