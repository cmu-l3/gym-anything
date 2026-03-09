#!/usr/bin/env python3
"""
Verifier for Commute Route Analyzer task.

Checks:
1. AVERAGE formulas for each route
2. STDEV formulas for reliability analysis
3. Cost calculations (especially toll costs for Highway)
4. Numerical reasonableness of results
5. Summary organization
6. Evidence of recommendation
"""

import sys
import os
import logging
from typing import Dict, Any, Tuple, List

# Use relative path to utils folder (runs on host, not container)
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


def find_formulas_in_sheet(workbook: Dict[str, Any], sheet_name: str, formula_pattern: str) -> List[Dict]:
    """
    Find all cells containing a specific formula pattern.
    
    Args:
        workbook: Parsed spreadsheet data
        sheet_name: Name of sheet to search
        formula_pattern: Pattern to search for (e.g., "AVERAGE", "STDEV")
        
    Returns:
        List of dicts with cell info: {'row': int, 'col': int, 'formula': str, 'value': Any}
    """
    matches = []
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return matches
    
    rows = sheets[sheet_name]
    for row_idx, row in enumerate(rows):
        for col_idx, cell in enumerate(row):
            formula = cell.get('formula', '')
            if formula and formula_pattern.upper() in formula.upper():
                matches.append({
                    'row': row_idx,
                    'col': col_idx,
                    'formula': formula,
                    'value': cell.get('value')
                })
    
    return matches


def check_numerical_reasonableness(values: List[Any], min_val: float, max_val: float, value_type: str) -> Tuple[int, str]:
    """
    Check if numerical values are within reasonable ranges.
    
    Returns:
        Tuple of (count_reasonable, feedback_message)
    """
    reasonable_count = 0
    for val in values:
        if val is not None:
            try:
                num_val = float(val)
                if min_val <= num_val <= max_val:
                    reasonable_count += 1
            except (ValueError, TypeError):
                pass
    
    if reasonable_count >= len([v for v in values if v is not None]) * 0.8:
        return reasonable_count, f"✅ {value_type} values reasonable ({reasonable_count}/{len(values)})"
    else:
        return reasonable_count, f"⚠️ Some {value_type} values outside expected range"


def count_non_empty_rows(workbook: Dict[str, Any], sheet_name: str) -> int:
    """Count rows with at least one non-empty cell."""
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return 0
    
    rows = sheets[sheet_name]
    count = 0
    for row in rows:
        if any(cell.get('value') for cell in row):
            count += 1
    
    return count


def verify_commute_analysis(traj, env_info, task_info):
    """
    Verify commute route analysis task completion.
    
    Scoring criteria (100 points total):
    1. AVERAGE formulas present (25 pts) - need at least 3
    2. STDEV formulas present (25 pts) - need at least 3
    3. Cost calculations (20 pts) - toll costs around $35-70 detected
    4. Numerical reasonableness (15 pts) - times 20-60 min, costs reasonable
    5. Summary organization (10 pts) - sufficient rows and structure
    6. Evidence of analysis depth (5 pts) - multiple formula types used
    
    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/commute_analysis.ods",
        "/home/ga/Documents/commute_data.ods",
        "/home/ga/Documents/commute_data.csv"
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for path in possible_paths:
        # Determine format from extension
        if path.endswith('.ods'):
            file_format = 'ods'
        elif path.endswith('.csv'):
            file_format = 'csv'
        else:
            file_format = 'ods'
        
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path,
            copy_from_env,
            file_format=file_format
        )
        
        if success:
            logger.info(f"Successfully loaded file from: {path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet from any expected location: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = get_sheet_names(workbook)
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        logger.info(f"Analyzing sheet: {sheet_name}")
        
        score = 0
        max_score = 100
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: AVERAGE formulas (25 points)
        average_formulas = find_formulas_in_sheet(workbook, sheet_name, "AVERAGE")
        avg_count = len(average_formulas)
        
        if avg_count >= 3:
            score += 25
            feedback_parts.append(f"✅ AVERAGE formulas found ({avg_count} instances)")
            subscores['average_formulas'] = True
        elif avg_count >= 2:
            score += 18
            feedback_parts.append(f"⚠️ Some AVERAGE formulas found ({avg_count}/3)")
            subscores['average_formulas'] = False
        elif avg_count >= 1:
            score += 10
            feedback_parts.append(f"⚠️ Only {avg_count} AVERAGE formula found (need 3)")
            subscores['average_formulas'] = False
        else:
            feedback_parts.append("❌ No AVERAGE formulas detected")
            subscores['average_formulas'] = False
        
        # Criterion 2: STDEV formulas (25 points)
        stdev_formulas = find_formulas_in_sheet(workbook, sheet_name, "STDEV")
        stdev_count = len(stdev_formulas)
        
        if stdev_count >= 3:
            score += 25
            feedback_parts.append(f"✅ Reliability (STDEV) formulas found ({stdev_count} instances)")
            subscores['stdev_formulas'] = True
        elif stdev_count >= 2:
            score += 18
            feedback_parts.append(f"⚠️ Some STDEV formulas found ({stdev_count}/3)")
            subscores['stdev_formulas'] = False
        elif stdev_count >= 1:
            score += 10
            feedback_parts.append(f"⚠️ Only {stdev_count} STDEV formula found (need 3)")
            subscores['stdev_formulas'] = False
        else:
            feedback_parts.append("❌ No STDEV formulas detected")
            subscores['stdev_formulas'] = False
        
        # Criterion 3: Cost calculations with tolls (20 points)
        # Look for values in the $35-70 range (Highway toll costs) or formulas with toll calculations
        toll_calculation_found = False
        cost_formulas = 0
        
        sheets = workbook.get('sheets', {})
        rows = sheets[sheet_name]
        
        for row in rows:
            for cell in row:
                value = cell.get('value')
                formula = cell.get('formula', '')
                
                # Check for toll-related costs ($35-70 range suggests toll + gas for Highway)
                if isinstance(value, (int, float)) and 35 <= value <= 70:
                    toll_calculation_found = True
                
                # Check for formulas that might be cost calculations (multiplication by 10 for 10 trips)
                if formula and ('*' in formula or '+' in formula):
                    if '3.5' in formula or '3.50' in formula or '35' in formula:
                        toll_calculation_found = True
                    if any(char.isdigit() for char in formula):
                        cost_formulas += 1
        
        if toll_calculation_found:
            score += 20
            feedback_parts.append("✅ Cost calculations detected (toll costs found)")
            subscores['cost_calculations'] = True
        elif cost_formulas >= 2:
            score += 12
            feedback_parts.append("⚠️ Some cost formulas found but toll costs unclear")
            subscores['cost_calculations'] = False
        else:
            feedback_parts.append("❌ No toll/cost calculations detected")
            subscores['cost_calculations'] = False
        
        # Criterion 4: Numerical reasonableness (15 points)
        # Extract calculated values from AVERAGE and STDEV formulas
        avg_values = [f['value'] for f in average_formulas if f.get('value') is not None]
        stdev_values = [f['value'] for f in stdev_formulas if f.get('value') is not None]
        
        reasonable_avgs = 0
        reasonable_stdevs = 0
        
        for val in avg_values:
            try:
                if 20 <= float(val) <= 60:  # Reasonable commute times
                    reasonable_avgs += 1
            except (ValueError, TypeError):
                pass
        
        for val in stdev_values:
            try:
                if 0 <= float(val) <= 15:  # Reasonable standard deviations
                    reasonable_stdevs += 1
            except (ValueError, TypeError):
                pass
        
        if reasonable_avgs >= 2 and reasonable_stdevs >= 2:
            score += 15
            feedback_parts.append("✅ Numerical results appear reasonable")
            subscores['numerical_reasonableness'] = True
        elif reasonable_avgs >= 1 or reasonable_stdevs >= 1:
            score += 8
            feedback_parts.append("⚠️ Some results reasonable, others may need review")
            subscores['numerical_reasonableness'] = False
        else:
            feedback_parts.append("❌ Results don't appear reasonable or are missing")
            subscores['numerical_reasonableness'] = False
        
        # Criterion 5: Summary organization (10 points)
        # Check for sufficient structure indicating summary analysis
        non_empty_rows = count_non_empty_rows(workbook, sheet_name)
        has_text_labels = False
        
        for row in rows:
            for cell in row:
                value = cell.get('value')
                if isinstance(value, str):
                    text_lower = value.lower()
                    if any(keyword in text_lower for keyword in 
                           ['route', 'average', 'cost', 'time', 'reliability', 'week', 
                            'highway', 'scenic', 'city', 'summary', 'recommendation']):
                        has_text_labels = True
                        break
        
        if non_empty_rows >= 15 and has_text_labels:
            score += 10
            feedback_parts.append("✅ Summary analysis structure detected")
            subscores['summary_organization'] = True
        elif non_empty_rows >= 12 or has_text_labels:
            score += 6
            feedback_parts.append("⚠️ Some organization present")
            subscores['summary_organization'] = False
        else:
            feedback_parts.append("❌ No clear summary structure")
            subscores['summary_organization'] = False
        
        # Criterion 6: Analysis depth (5 points bonus)
        # Check for variety of analysis techniques
        total_formulas = avg_count + stdev_count + cost_formulas
        
        if total_formulas >= 8:
            score += 5
            feedback_parts.append("✅ Comprehensive analysis (multiple formula types)")
        elif total_formulas >= 5:
            score += 3
            feedback_parts.append("⚠️ Adequate analysis depth")
        
        # Normalize score to 100
        final_score = min(100, score)
        passed = final_score >= 70
        
        # Add pass/fail message
        if passed and final_score >= 90:
            feedback_parts.append("🎉 Excellent commute analysis!")
        elif passed:
            feedback_parts.append("✅ Commute analysis completed successfully")
        else:
            feedback_parts.append("❌ Analysis incomplete or missing key components")
        
        feedback_message = "\n".join(feedback_parts)
        feedback_message += f"\n\nFinal Score: {final_score:.1f}%"
        
        # Log detailed results
        logger.info(f"Verification complete. Score: {final_score}%, Passed: {passed}")
        logger.info(f"Details: AVG={avg_count}, STDEV={stdev_count}, Costs={toll_calculation_found}")
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback_message,
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
        # Always cleanup temp directory
        if temp_dir:
            cleanup_verification_temp(temp_dir)
