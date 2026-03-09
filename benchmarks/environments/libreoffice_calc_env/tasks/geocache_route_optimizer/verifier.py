#!/usr/bin/env python3
"""
Verifier for Geocache Route Optimizer task.

Checks:
1. Time estimates calculated for all caches
2. Distance calculations present for all caches  
3. All Priority 1 caches included in route
4. Total time calculated and ≤ 240 minutes
5. Formulas used (not hardcoded values)
6. No formula errors
"""

import sys
import os
import logging
import re
from typing import Dict, List, Any, Optional, Tuple

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Constants
STARTING_LAT = 40.3200
STARTING_LON = -105.6700
TIME_BUDGET = 240  # minutes
PRIORITY_1_COUNT = 5  # Expected number of Priority 1 caches


def is_inclusion_marker(value: Any) -> bool:
    """Check if a cell value indicates inclusion (YES, TRUE, X, 1, etc.)"""
    if value is None:
        return False
    
    value_str = str(value).strip().upper()
    return value_str in ['YES', 'Y', 'TRUE', 'T', 'X', '1', '✓', 'INCLUDE', 'INCLUDED']


def extract_number(value: Any) -> Optional[float]:
    """Extract numeric value from cell, handling various formats"""
    if value is None:
        return None
    
    try:
        if isinstance(value, (int, float)):
            return float(value)
        
        # Try parsing string
        value_str = str(value).strip()
        # Remove common non-numeric characters
        value_str = re.sub(r'[^\d\.\-\+eE]', '', value_str)
        return float(value_str)
    except (ValueError, TypeError):
        return None


def find_column_by_header(sheet_data: List[List[Dict]], header_keywords: List[str]) -> Optional[int]:
    """
    Find column index by searching for header keywords in first row.
    Returns 0-based column index or None if not found.
    """
    if not sheet_data or not sheet_data[0]:
        return None
    
    first_row = sheet_data[0]
    for col_idx, cell in enumerate(first_row):
        cell_value = cell.get('value') if isinstance(cell, dict) else cell
        if cell_value is None:
            continue
        
        cell_str = str(cell_value).strip().upper()
        for keyword in header_keywords:
            if keyword.upper() in cell_str:
                return col_idx
    
    return None


def get_cache_data_rows(sheet_data: List[List[Dict]]) -> List[Tuple[int, Dict[str, Any]]]:
    """
    Extract cache data rows from sheet.
    Returns list of (row_index, cache_info_dict) tuples.
    """
    caches = []
    
    # Find column indices
    name_col = find_column_by_header(sheet_data, ['CACHE', 'NAME'])
    lat_col = find_column_by_header(sheet_data, ['LATITUDE', 'LAT'])
    lon_col = find_column_by_header(sheet_data, ['LONGITUDE', 'LON', 'LONG'])
    diff_col = find_column_by_header(sheet_data, ['DIFFICULTY', 'DIFF'])
    terrain_col = find_column_by_header(sheet_data, ['TERRAIN'])
    priority_col = find_column_by_header(sheet_data, ['PRIORITY', 'PRIO'])
    
    if name_col is None:
        logger.warning("Could not find Cache Name column")
        return caches
    
    # Start from row 1 (skip header row 0)
    for row_idx in range(1, len(sheet_data)):
        row = sheet_data[row_idx]
        
        if row_idx >= len(row) or name_col >= len(row):
            continue
        
        name_cell = row[name_col]
        name = name_cell.get('value') if isinstance(name_cell, dict) else name_cell
        
        if not name or str(name).strip() == '':
            continue
        
        cache_info = {
            'row_index': row_idx,
            'name': str(name).strip()
        }
        
        # Extract other fields if available
        if lat_col is not None and lat_col < len(row):
            lat_cell = row[lat_col]
            lat_val = lat_cell.get('value') if isinstance(lat_cell, dict) else lat_cell
            cache_info['latitude'] = extract_number(lat_val)
        
        if lon_col is not None and lon_col < len(row):
            lon_cell = row[lon_col]
            lon_val = lon_cell.get('value') if isinstance(lon_cell, dict) else lon_cell
            cache_info['longitude'] = extract_number(lon_val)
        
        if diff_col is not None and diff_col < len(row):
            diff_cell = row[diff_col]
            diff_val = diff_cell.get('value') if isinstance(diff_cell, dict) else diff_cell
            cache_info['difficulty'] = extract_number(diff_val)
        
        if terrain_col is not None and terrain_col < len(row):
            terrain_cell = row[terrain_col]
            terrain_val = terrain_cell.get('value') if isinstance(terrain_cell, dict) else terrain_cell
            cache_info['terrain'] = extract_number(terrain_val)
        
        if priority_col is not None and priority_col < len(row):
            priority_cell = row[priority_col]
            priority_val = priority_cell.get('value') if isinstance(priority_cell, dict) else priority_cell
            cache_info['priority'] = extract_number(priority_val)
        
        caches.append((row_idx, cache_info))
    
    return caches


def check_time_estimates(sheet_data: List[List[Dict]], cache_rows: List[Tuple[int, Dict]]) -> Tuple[bool, str, List[float]]:
    """
    Check if time estimates are calculated for all caches.
    Returns (success, feedback, time_values_list)
    """
    # Look for time estimate column
    time_col = find_column_by_header(sheet_data, ['ESTIMATED', 'ESTIMATE', 'TIME', 'FIND TIME', 'EST TIME'])
    
    if time_col is None:
        return False, "No time estimate column found", []
    
    time_values = []
    all_valid = True
    
    for row_idx, cache_info in cache_rows:
        if row_idx >= len(sheet_data) or time_col >= len(sheet_data[row_idx]):
            all_valid = False
            continue
        
        time_cell = sheet_data[row_idx][time_col]
        time_val = extract_number(time_cell.get('value') if isinstance(time_cell, dict) else time_cell)
        
        if time_val is None:
            all_valid = False
            continue
        
        # Check if time is in reasonable range (10-60 minutes)
        if not (5 <= time_val <= 100):
            logger.warning(f"Time estimate {time_val} out of reasonable range for {cache_info.get('name')}")
        
        time_values.append(time_val)
    
    if len(time_values) >= len(cache_rows) * 0.9:  # Allow up to 10% missing
        return True, f"Time estimates present for {len(time_values)}/{len(cache_rows)} caches", time_values
    else:
        return False, f"Time estimates missing or invalid for many caches ({len(time_values)}/{len(cache_rows)})", time_values


def check_distance_calculations(sheet_data: List[List[Dict]], cache_rows: List[Tuple[int, Dict]]) -> Tuple[bool, str, List[float]]:
    """
    Check if distance calculations are present.
    Returns (success, feedback, distance_values_list)
    """
    # Look for distance column
    dist_col = find_column_by_header(sheet_data, ['DISTANCE', 'DIST', 'KM', 'KILOMETERS'])
    
    if dist_col is None:
        return False, "No distance column found", []
    
    distance_values = []
    all_valid = True
    
    for row_idx, cache_info in cache_rows:
        if row_idx >= len(sheet_data) or dist_col >= len(sheet_data[row_idx]):
            all_valid = False
            continue
        
        dist_cell = sheet_data[row_idx][dist_col]
        dist_val = extract_number(dist_cell.get('value') if isinstance(dist_cell, dict) else dist_cell)
        
        if dist_val is None:
            all_valid = False
            continue
        
        # Check if distance is in reasonable range (0-20 km for this park)
        if not (0 <= dist_val <= 50):
            logger.warning(f"Distance {dist_val} out of reasonable range for {cache_info.get('name')}")
        
        distance_values.append(dist_val)
    
    if len(distance_values) >= len(cache_rows) * 0.9:
        return True, f"Distance calculations present for {len(distance_values)}/{len(cache_rows)} caches", distance_values
    else:
        return False, f"Distance calculations missing for many caches ({len(distance_values)}/{len(cache_rows)})", distance_values


def check_priority1_inclusion(sheet_data: List[List[Dict]], cache_rows: List[Tuple[int, Dict]]) -> Tuple[bool, str, int]:
    """
    Check if all Priority 1 caches are marked for inclusion.
    Returns (success, feedback, count_included)
    """
    # Look for inclusion column
    include_col = find_column_by_header(sheet_data, ['INCLUDE', 'SELECT', 'SELECTED', 'YES', 'VISIT'])
    
    if include_col is None:
        return False, "No inclusion/selection column found", 0
    
    priority1_caches = [c for _, c in cache_rows if c.get('priority') == 1]
    priority1_included = 0
    
    for row_idx, cache_info in cache_rows:
        if cache_info.get('priority') != 1:
            continue
        
        if row_idx >= len(sheet_data) or include_col >= len(sheet_data[row_idx]):
            continue
        
        include_cell = sheet_data[row_idx][include_col]
        include_val = include_cell.get('value') if isinstance(include_cell, dict) else include_cell
        
        if is_inclusion_marker(include_val):
            priority1_included += 1
    
    if priority1_included >= len(priority1_caches):
        return True, f"All {priority1_included} Priority 1 caches included", priority1_included
    else:
        return False, f"Only {priority1_included}/{len(priority1_caches)} Priority 1 caches included", priority1_included


def check_total_time(sheet_data: List[List[Dict]], cache_rows: List[Tuple[int, Dict]]) -> Tuple[bool, str, Optional[float]]:
    """
    Check if total time is calculated and within budget.
    Returns (success, feedback, total_time_value)
    """
    # Look for total time cell - usually in a summary area
    # Check last few rows or columns for summary
    
    # Strategy 1: Look for "TOTAL" label in first column
    total_time = None
    
    for row in sheet_data:
        if not row:
            continue
        
        first_cell = row[0]
        first_val = first_cell.get('value') if isinstance(first_cell, dict) else first_cell
        
        if first_val and 'TOTAL' in str(first_val).upper():
            # Found total row, look for time value in adjacent cells
            for cell in row[1:6]:  # Check next few cells
                cell_val = extract_number(cell.get('value') if isinstance(cell, dict) else cell)
                if cell_val and 50 <= cell_val <= 500:  # Reasonable total time range
                    total_time = cell_val
                    break
            if total_time:
                break
    
    # Strategy 2: Look for SUMIF or SUM formulas
    if total_time is None:
        for row in sheet_data:
            for cell in row:
                if not isinstance(cell, dict):
                    continue
                formula = cell.get('formula', '')
                if formula and ('SUMIF' in formula.upper() or 'SUM(' in formula.upper()):
                    cell_val = extract_number(cell.get('value'))
                    if cell_val and 50 <= cell_val <= 500:
                        total_time = cell_val
                        break
            if total_time:
                break
    
    if total_time is None:
        return False, "Total time not calculated or not found", None
    
    if total_time <= TIME_BUDGET:
        return True, f"Total time {total_time:.1f} min ≤ {TIME_BUDGET} min budget", total_time
    else:
        return False, f"Total time {total_time:.1f} min exceeds {TIME_BUDGET} min budget", total_time


def check_formulas_used(sheet_data: List[List[Dict]], cache_rows: List[Tuple[int, Dict]]) -> Tuple[bool, str]:
    """
    Check if formulas are used (not just hardcoded values).
    Returns (success, feedback)
    """
    formula_count = 0
    total_cells_checked = 0
    
    # Check cells in cache rows (excluding first few columns which are input data)
    for row_idx, cache_info in cache_rows:
        if row_idx >= len(sheet_data):
            continue
        
        row = sheet_data[row_idx]
        # Check columns beyond the first 6 (which are input data)
        for cell in row[6:15]:  # Check calculated columns
            if not isinstance(cell, dict):
                continue
            
            total_cells_checked += 1
            formula = cell.get('formula')
            if formula and formula.startswith('='):
                formula_count += 1
    
    if total_cells_checked == 0:
        return False, "No calculated cells found"
    
    formula_ratio = formula_count / total_cells_checked
    
    if formula_ratio >= 0.5:  # At least 50% of calculated cells use formulas
        return True, f"Formulas used in {formula_count}/{total_cells_checked} calculated cells"
    else:
        return False, f"Too few formulas ({formula_count}/{total_cells_checked}) - values may be hardcoded"


def check_no_errors(sheet_data: List[List[Dict]]) -> Tuple[bool, str]:
    """
    Check for #ERROR, #VALUE!, #REF!, etc. in formulas.
    Returns (success, feedback)
    """
    error_count = 0
    
    for row in sheet_data:
        for cell in row:
            if not isinstance(cell, dict):
                continue
            
            value = cell.get('value')
            if value and isinstance(value, str) and '#' in value:
                if any(err in value.upper() for err in ['#ERROR', '#VALUE', '#REF', '#DIV', '#NAME', '#NUM', '#NULL']):
                    error_count += 1
    
    if error_count == 0:
        return True, "No formula errors detected"
    else:
        return False, f"{error_count} formula errors detected (#VALUE!, #REF!, etc.)"


def verify_geocache_route(traj, env_info, task_info):
    """
    Main verification function for Geocache Route Optimizer task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    paths_to_try = [
        ("/home/ga/Documents/geocache_route_plan.ods", "ods"),
        ("/home/ga/Documents/geocache_data.ods", "ods"),
        ("/home/ga/Documents/geocache_data.csv", "csv"),
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for container_path, file_format in paths_to_try:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet file: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = workbook['sheets'][sheet_name]
        
        # Extract cache data rows
        cache_rows = get_cache_data_rows(sheet_data)
        
        if len(cache_rows) < 8:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Expected 10 geocaches, found only {len(cache_rows)}"
            }
        
        logger.info(f"Found {len(cache_rows)} cache rows")
        
        # Run all checks
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Time estimates present
        time_ok, time_feedback, time_values = check_time_estimates(sheet_data, cache_rows)
        if time_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {time_feedback}")
        else:
            feedback_parts.append(f"❌ {time_feedback}")
        subscores['time_estimates'] = time_ok
        
        # Criterion 2: Distance calculations present
        dist_ok, dist_feedback, dist_values = check_distance_calculations(sheet_data, cache_rows)
        if dist_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {dist_feedback}")
        else:
            feedback_parts.append(f"❌ {dist_feedback}")
        subscores['distance_calculations'] = dist_ok
        
        # Criterion 3: All Priority 1 included
        prio_ok, prio_feedback, prio_count = check_priority1_inclusion(sheet_data, cache_rows)
        if prio_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {prio_feedback}")
        else:
            feedback_parts.append(f"❌ {prio_feedback}")
        subscores['priority1_included'] = prio_ok
        
        # Criterion 4: Total time calculated and within budget
        total_ok, total_feedback, total_time = check_total_time(sheet_data, cache_rows)
        if total_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {total_feedback}")
        else:
            feedback_parts.append(f"❌ {total_feedback}")
        subscores['time_budget_met'] = total_ok
        
        # Criterion 5: Formulas used
        formula_ok, formula_feedback = check_formulas_used(sheet_data, cache_rows)
        if formula_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {formula_feedback}")
        else:
            feedback_parts.append(f"⚠️ {formula_feedback}")
        subscores['formulas_used'] = formula_ok
        
        # Criterion 6: No formula errors
        error_ok, error_feedback = check_no_errors(sheet_data)
        if error_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {error_feedback}")
        else:
            feedback_parts.append(f"❌ {error_feedback}")
        subscores['no_errors'] = error_ok
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 5/6 criteria (75%)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent geocache route planning!")
        elif passed:
            feedback_parts.append("✅ Route optimization task completed")
        else:
            feedback_parts.append("❌ Route optimization requirements not met")
        
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
