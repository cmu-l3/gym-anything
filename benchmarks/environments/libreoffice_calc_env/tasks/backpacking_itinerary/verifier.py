#!/usr/bin/env python3
"""
Verifier for Backpacking Itinerary Planner task
"""

import sys
import os
import logging
import re
from typing import Dict, List, Tuple, Any, Optional

# Add utils to path (relative path for host machine)
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


def parse_cell_ref(cell_ref: str) -> Tuple[int, int]:
    """Parse cell reference like 'A1' into (col_index, row_index) (0-based)"""
    col_str = ''
    row_str = ''
    for char in cell_ref:
        if char.isalpha():
            col_str += char.upper()
        elif char.isdigit():
            row_str += char
    
    col_idx = 0
    for char in col_str:
        col_idx = col_idx * 26 + (ord(char) - ord('A') + 1)
    col_idx -= 1
    
    row_idx = int(row_str) - 1
    return col_idx, row_idx


def get_column_values(sheet_data: Dict, sheet_name: str, col_index: int, 
                     start_row: int = 1, max_rows: int = 20) -> List[Any]:
    """Extract all values from a specific column"""
    values = []
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return values
    
    rows = sheets[sheet_name]
    for row_idx in range(start_row, min(len(rows), start_row + max_rows)):
        if row_idx < len(rows) and col_index < len(rows[row_idx]):
            cell_data = rows[row_idx][col_index]
            value = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
            values.append(value)
    
    return values


def find_column_by_header(sheet_data: Dict, sheet_name: str, 
                         possible_names: List[str]) -> Optional[int]:
    """Find column index by searching for header names"""
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return None
    
    rows = sheets[sheet_name]
    if not rows:
        return None
    
    header_row = rows[0]
    for col_idx, cell in enumerate(header_row):
        value = cell.get('value') if isinstance(cell, dict) else cell
        if value:
            value_str = str(value).lower().strip()
            for name in possible_names:
                if name.lower() in value_str:
                    return col_idx
    
    return None


def verify_cumulative_distance(sheet_data: Dict, sheet_name: str, 
                              distance_col: int, cumulative_col: int,
                              num_segments: int) -> Tuple[bool, str, float]:
    """
    Verify cumulative distance is correctly calculated.
    Returns (success, message, score_contribution)
    """
    try:
        distances = get_column_values(sheet_data, sheet_name, distance_col, 
                                     start_row=1, max_rows=num_segments)
        cumulatives = get_column_values(sheet_data, sheet_name, cumulative_col,
                                       start_row=1, max_rows=num_segments)
        
        if not distances or not cumulatives:
            return False, "Cumulative distance column not found or empty", 0.0
        
        if len(cumulatives) < len(distances):
            return False, f"Cumulative column incomplete ({len(cumulatives)}/{len(distances)} rows)", 0.0
        
        # Check if values are formulas or calculated
        # At least some cells should contain formulas for running totals
        formula_count = 0
        for row_idx in range(1, min(len(cumulatives) + 1, num_segments + 1)):
            formula = get_cell_formula(sheet_data, sheet_name, f"{chr(65+cumulative_col)}{row_idx+1}")
            if formula:
                formula_count += 1
        
        uses_formulas = formula_count >= len(cumulatives) - 1
        
        # Calculate expected cumulative distances
        expected_cumulative = []
        running_total = 0.0
        for dist in distances:
            try:
                dist_val = float(dist) if dist is not None else 0.0
                running_total += dist_val
                expected_cumulative.append(running_total)
            except (ValueError, TypeError):
                return False, f"Invalid distance value: {dist}", 0.0
        
        # Compare actual vs expected with tolerance
        all_correct = True
        for i, (actual, expected) in enumerate(zip(cumulatives, expected_cumulative)):
            try:
                actual_val = float(actual) if actual is not None else 0.0
                if abs(actual_val - expected) > 0.2:  # 0.2 mile tolerance
                    return False, f"Cumulative distance incorrect at row {i+2}: expected {expected:.1f}, got {actual_val:.1f}", 0.3
            except (ValueError, TypeError):
                return False, f"Invalid cumulative value at row {i+2}: {actual}", 0.3
        
        # Check final cumulative is reasonable (should be 60-75 miles for 7-day trip)
        final_cumulative = float(cumulatives[-1]) if cumulatives else 0.0
        if final_cumulative < 50 or final_cumulative > 80:
            return False, f"Final cumulative distance unrealistic: {final_cumulative:.1f} miles", 0.5
        
        if uses_formulas:
            return True, f"✅ Cumulative distance correct (formulas used, final: {final_cumulative:.1f} mi)", 1.0
        else:
            return True, f"⚠️ Cumulative distance correct but may be hardcoded (final: {final_cumulative:.1f} mi)", 0.7
        
    except Exception as e:
        logger.error(f"Error verifying cumulative distance: {e}", exc_info=True)
        return False, f"Error checking cumulative distance: {str(e)}", 0.0


def verify_time_estimation(sheet_data: Dict, sheet_name: str,
                          distance_col: int, elevation_col: int, 
                          time_col: int, num_segments: int) -> Tuple[bool, str, float]:
    """
    Verify time estimation formula includes both distance and elevation.
    Returns (success, message, score_contribution)
    """
    try:
        distances = get_column_values(sheet_data, sheet_name, distance_col,
                                     start_row=1, max_rows=num_segments)
        elevations = get_column_values(sheet_data, sheet_name, elevation_col,
                                      start_row=1, max_rows=num_segments)
        times = get_column_values(sheet_data, sheet_name, time_col,
                                 start_row=1, max_rows=num_segments)
        
        if not times:
            return False, "Time estimation column not found", 0.0
        
        if len(times) < len(distances):
            return False, f"Time column incomplete ({len(times)}/{len(distances)} rows)", 0.0
        
        # Check if formulas are used (at least one)
        has_formulas = False
        sample_formula = None
        for row_idx in range(1, min(len(times) + 1, num_segments + 1)):
            formula = get_cell_formula(sheet_data, sheet_name, f"{chr(65+time_col)}{row_idx+1}")
            if formula:
                has_formulas = True
                sample_formula = formula
                break
        
        if not has_formulas:
            return False, "Time column contains values instead of formulas", 0.0
        
        # Check if formula includes both distance and elevation components
        formula_upper = sample_formula.upper()
        distance_col_letter = chr(65 + distance_col)
        elevation_col_letter = chr(65 + elevation_col)
        
        has_distance_ref = distance_col_letter in formula_upper
        has_elevation_ref = elevation_col_letter in formula_upper
        
        if not (has_distance_ref and has_elevation_ref):
            return False, f"Time formula missing components (distance: {has_distance_ref}, elevation: {has_elevation_ref})", 0.3
        
        # Validate calculated times are reasonable
        for i, (time, dist, elev) in enumerate(zip(times, distances, elevations)):
            try:
                time_val = float(time) if time is not None else 0.0
                dist_val = float(dist) if dist is not None else 0.0
                elev_val = float(elev) if elev is not None else 0.0
                
                # Minimum time: very fast pace (4 mph flat)
                min_time = dist_val / 4.0
                # Maximum time: very slow pace (1.5 mph) + elevation penalty (1hr per 500ft)
                max_time = (dist_val / 1.5) + (elev_val / 500.0)
                
                if time_val < min_time * 0.5 or time_val > max_time * 1.5:
                    return False, f"Time estimate unrealistic at row {i+2}: {time_val:.1f}h for {dist_val}mi + {elev_val}ft", 0.5
                    
            except (ValueError, TypeError):
                return False, f"Invalid time value at row {i+2}: {time}", 0.3
        
        return True, f"✅ Time estimation formula correct (includes distance & elevation)", 1.0
        
    except Exception as e:
        logger.error(f"Error verifying time estimation: {e}", exc_info=True)
        return False, f"Error checking time estimation: {str(e)}", 0.0


def verify_problem_flagging(sheet_data: Dict, sheet_name: str, filepath: str,
                           time_col: int, elevation_col: int,
                           num_segments: int) -> Tuple[bool, str, float]:
    """
    Verify problematic segments are flagged via column or conditional formatting.
    Returns (success, message, score_contribution)
    """
    try:
        times = get_column_values(sheet_data, sheet_name, time_col,
                                 start_row=1, max_rows=num_segments)
        elevations = get_column_values(sheet_data, sheet_name, elevation_col,
                                      start_row=1, max_rows=num_segments)
        
        # Find potential status/warning column
        status_col = find_column_by_header(sheet_data, sheet_name, 
                                          ['status', 'warning', 'flag', 'alert', 'problem'])
        
        # Check for conditional formatting
        has_conditional_formatting = False
        try:
            # Check if conditional formatting exists on likely columns
            for col_idx in range(time_col, time_col + 3):
                col_letter = chr(65 + col_idx)
                if check_conditional_formatting(sheet_data, sheet_name, f"{col_letter}1:{col_letter}20"):
                    has_conditional_formatting = True
                    break
        except:
            pass
        
        # Identify segments that SHOULD be flagged
        problems_expected = []
        for i, (time, elev) in enumerate(zip(times, elevations)):
            try:
                time_val = float(time) if time is not None else 0.0
                elev_val = float(elev) if elev is not None else 0.0
                
                if time_val > 6.0:
                    problems_expected.append((i, f"Long segment: {time_val:.1f}h"))
                elif elev_val > 3000:
                    problems_expected.append((i, f"Steep: {elev_val:.0f}ft"))
            except (ValueError, TypeError):
                continue
        
        if not problems_expected:
            # No problems in data, so flagging is optional
            return True, "✅ No critical problems in itinerary", 0.8
        
        # Check if problems are flagged
        if status_col is not None:
            status_values = get_column_values(sheet_data, sheet_name, status_col,
                                             start_row=1, max_rows=num_segments)
            
            # Check if flagged rows contain warning keywords
            flagged_count = 0
            for idx, reason in problems_expected:
                if idx < len(status_values):
                    status = str(status_values[idx]).upper() if status_values[idx] else ""
                    if any(word in status for word in ['WARN', 'DANGER', 'ALERT', 'PROBLEM', 
                                                        'CAUTION', 'LONG', 'STEEP', 'CONCERN']):
                        flagged_count += 1
            
            if flagged_count >= len(problems_expected) * 0.6:  # At least 60% flagged
                return True, f"✅ Problems flagged ({flagged_count}/{len(problems_expected)} critical segments)", 1.0
            else:
                return False, f"⚠️ Some problems not flagged ({flagged_count}/{len(problems_expected)} segments)", 0.4
        
        elif has_conditional_formatting:
            return True, "✅ Conditional formatting applied (visual flagging detected)", 0.8
        
        else:
            return False, "❌ No problem flagging mechanism found (no status column or conditional formatting)", 0.0
        
    except Exception as e:
        logger.error(f"Error verifying problem flagging: {e}", exc_info=True)
        return False, f"Error checking problem flagging: {str(e)}", 0.0


def verify_backpacking_itinerary(traj, env_info, task_info):
    """
    Main verifier for backpacking itinerary task.
    
    Checks:
    1. Cumulative distance calculated correctly
    2. Time estimation formula includes distance AND elevation
    3. Problematic segments/days are flagged
    4. No formula errors
    5. Results are realistic
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try ODS first, fall back to CSV
    container_paths = [
        "/home/ga/Documents/backpacking_itinerary.ods",
        "/home/ga/Documents/trail_segments.ods",
        "/home/ga/Documents/trail_segments.csv"
    ]
    
    success = False
    file_info = None
    temp_dir = None
    
    for path in container_paths:
        fmt = 'ods' if path.endswith('.ods') else 'csv'
        success, file_info, error = setup_calc_verification(copy_from_env, path, [fmt])
        if success:
            temp_dir = file_info.get('temp_dir')
            logger.info(f"Successfully loaded file: {path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load itinerary file: {error}"
        }
    
    try:
        sheet_data = file_info['sheet_data']
        sheet_names = list(sheet_data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        # Identify columns
        distance_col = find_column_by_header(sheet_data, sheet_name, 
                                            ['distance', 'dist', 'miles', 'mi'])
        elevation_col = find_column_by_header(sheet_data, sheet_name,
                                             ['elevation', 'elev', 'gain', 'climb'])
        
        if distance_col is None or elevation_col is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not find distance or elevation columns in data"
            }
        
        # Count data rows (segments)
        num_segments = 14  # Expected based on setup
        
        # Find calculated columns (should be after the base data columns)
        # Look for cumulative distance column
        cumulative_col = find_column_by_header(sheet_data, sheet_name,
                                              ['cumulative', 'total', 'running'])
        
        # Look for time estimation column
        time_col = find_column_by_header(sheet_data, sheet_name,
                                        ['time', 'hours', 'duration', 'est'])
        
        feedback_parts = []
        total_score = 0.0
        max_score = 5.0
        
        subscores = {
            'cumulative_distance': False,
            'time_estimation': False,
            'problem_flagging': False,
            'no_errors': False,
            'realistic': False
        }
        
        # Criterion 1: Cumulative Distance
        if cumulative_col is not None:
            success, msg, score = verify_cumulative_distance(
                sheet_data, sheet_name, distance_col, cumulative_col, num_segments
            )
            feedback_parts.append(msg)
            total_score += score
            subscores['cumulative_distance'] = success
        else:
            feedback_parts.append("❌ Cumulative distance column not found")
        
        # Criterion 2: Time Estimation
        if time_col is not None:
            success, msg, score = verify_time_estimation(
                sheet_data, sheet_name, distance_col, elevation_col, 
                time_col, num_segments
            )
            feedback_parts.append(msg)
            total_score += score
            subscores['time_estimation'] = success
        else:
            feedback_parts.append("❌ Time estimation column not found")
        
        # Criterion 3: Problem Flagging
        if time_col is not None:
            success, msg, score = verify_problem_flagging(
                sheet_data, sheet_name, file_info['filepath'],
                time_col, elevation_col, num_segments
            )
            feedback_parts.append(msg)
            total_score += score
            subscores['problem_flagging'] = success
        else:
            feedback_parts.append("⚠️ Cannot check problem flagging without time column")
        
        # Criterion 4: No Formula Errors
        # Check for error values in any cells
        has_errors = False
        error_cells = []
        rows = sheet_data['sheets'][sheet_name]
        for row_idx, row in enumerate(rows[:num_segments+1], start=1):
            for col_idx, cell in enumerate(row):
                value = cell.get('value') if isinstance(cell, dict) else cell
                if value and isinstance(value, str):
                    if value.startswith('#') or 'ERR' in value.upper():
                        has_errors = True
                        col_letter = chr(65 + col_idx)
                        error_cells.append(f"{col_letter}{row_idx}")
        
        if not has_errors:
            feedback_parts.append("✅ No formula errors detected")
            total_score += 1.0
            subscores['no_errors'] = True
        else:
            feedback_parts.append(f"❌ Formula errors found: {', '.join(error_cells[:3])}")
        
        # Criterion 5: Realistic Results (sanity check)
        realistic = True
        if cumulative_col and time_col:
            cumulatives = get_column_values(sheet_data, sheet_name, cumulative_col,
                                           start_row=1, max_rows=num_segments)
            times = get_column_values(sheet_data, sheet_name, time_col,
                                     start_row=1, max_rows=num_segments)
            
            try:
                final_dist = float(cumulatives[-1]) if cumulatives else 0
                total_time = sum(float(t) for t in times if t is not None)
                
                if 55 <= final_dist <= 75 and 30 <= total_time <= 65:
                    feedback_parts.append(f"✅ Results realistic ({final_dist:.1f} mi, {total_time:.1f} hrs total)")
                    total_score += 1.0
                    subscores['realistic'] = True
                else:
                    feedback_parts.append(f"⚠️ Results may be unrealistic ({final_dist:.1f} mi, {total_time:.1f} hrs)")
                    realistic = False
            except:
                realistic = False
        
        # Calculate final score
        score_percent = int((total_score / max_score) * 100)
        passed = score_percent >= 75
        
        # Add summary message
        if passed and score_percent >= 90:
            feedback_parts.insert(0, "🎉 Excellent trip planning! Itinerary is well-analyzed.")
        elif passed:
            feedback_parts.insert(0, "✅ Trip planning completed successfully")
        else:
            feedback_parts.insert(0, "❌ Trip planning incomplete - safety assessment missing")
        
        return {
            "passed": passed,
            "score": score_percent,
            "feedback": " | ".join(feedback_parts),
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
