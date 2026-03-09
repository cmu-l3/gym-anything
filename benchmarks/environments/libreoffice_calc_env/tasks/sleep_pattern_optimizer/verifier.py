#!/usr/bin/env python3
"""
Verifier for Sleep Pattern Optimizer task.
Checks for time arithmetic, conditional logic, conditional formatting,
statistical correlation formulas, and optimal bedtime analysis.
"""

import sys
import os
import logging
import re
from typing import Dict, List, Tuple, Any

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    get_sheet_names,
    check_conditional_formatting,
    cleanup_verification_temp,
    open_spreadsheet
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_formula_patterns_in_sheet(sheet_data: List[List[Dict]], patterns: List[str]) -> List[Tuple[int, int, str]]:
    """
    Search for formula patterns in a sheet.
    
    Args:
        sheet_data: Sheet data (list of rows, each row is list of cells)
        patterns: List of regex patterns to search for
        
    Returns:
        List of tuples (row, col, formula) where pattern matched
    """
    matches = []
    for row_idx, row in enumerate(sheet_data):
        for col_idx, cell in enumerate(row):
            if isinstance(cell, dict):
                formula = cell.get('formula', '')
                if formula:
                    for pattern in patterns:
                        if re.search(pattern, formula, re.IGNORECASE):
                            matches.append((row_idx, col_idx, formula))
                            break
    return matches


def check_time_arithmetic_formulas(sheet_data: List[List[Dict]]) -> Tuple[bool, str]:
    """
    Check for time arithmetic formulas (sleep duration calculation).
    Look for patterns like: IF(...<..., ...+1-..., ...-...)*24
    """
    patterns = [
        r'IF.*<.*\+.*-.*\*\s*24',  # Midnight crossover: IF(wake<bed, wake+1-bed, wake-bed)*24
        r'\(.*-.*\)\s*\*\s*24',     # Simple multiplication: (wake-bed)*24
        r'MOD\(.*-.*,\s*1\)\s*\*\s*24',  # MOD-based: MOD(wake-bed, 1)*24
        r'IF.*<.*24.*-',            # Alternative IF with 24 hour handling
    ]
    
    matches = find_formula_patterns_in_sheet(sheet_data, patterns)
    
    if matches:
        example_formula = matches[0][2]
        return True, f"Sleep duration formula found: {example_formula}"
    
    return False, "No time arithmetic formula found for sleep duration"


def check_quality_categorization_formulas(sheet_data: List[List[Dict]]) -> Tuple[bool, str]:
    """
    Check for IF formulas that categorize quality scores.
    Look for patterns with quality tiers: Excellent, Good, Fair, Poor
    """
    patterns = [
        r'IF.*[<>]=?\s*[5-9].*(?:Excellent|Good|Fair|Poor)',  # IF with quality thresholds
        r'IFS?\(',  # IFS function (multiple conditions)
        r'IF.*IF.*(?:Excellent|Good|Fair|Poor)',  # Nested IFs with quality labels
    ]
    
    matches = find_formula_patterns_in_sheet(sheet_data, patterns)
    
    if matches:
        example_formula = matches[0][2]
        return True, f"Quality categorization formula found: {example_formula}"
    
    # Alternative: check for any IF formulas with text outputs
    text_if_patterns = [
        r'IF.*"[A-Za-z]+".*"[A-Za-z]+"',  # IF with text outputs
    ]
    
    matches = find_formula_patterns_in_sheet(sheet_data, text_if_patterns)
    if matches:
        return True, f"Conditional categorization formula found: {matches[0][2]}"
    
    return False, "No quality categorization formula found"


def check_averageif_formulas(sheet_data: List[List[Dict]]) -> Tuple[bool, List[str]]:
    """
    Check for AVERAGEIF formulas analyzing factor correlations.
    """
    patterns = [
        r'AVERAGEIF',
        r'AVERAGEIFS',
        r'SUMIF.*COUNTIF',  # Manual average calculation
    ]
    
    matches = find_formula_patterns_in_sheet(sheet_data, patterns)
    
    if matches:
        formulas = [m[2] for m in matches[:3]]  # Return up to 3 examples
        return True, formulas
    
    return False, []


def check_optimal_bedtime_analysis(sheet_data: List[List[Dict]]) -> Tuple[bool, str]:
    """
    Check for formulas analyzing bedtime vs quality.
    Look for AVERAGEIF with time-based conditions.
    """
    patterns = [
        r'AVERAGEIF.*["><=].*2[0-3]:[0-5][0-9]',  # AVERAGEIF with time condition (e.g., ">22:00")
        r'AVERAGEIF.*["><=].*[0-9]+:[0-9]+',       # Any time-based AVERAGEIF
        r'IF.*TIME\(',                              # Time function usage
    ]
    
    matches = find_formula_patterns_in_sheet(sheet_data, patterns)
    
    if matches:
        return True, f"Bedtime analysis formula found: {matches[0][2]}"
    
    # If specific time analysis not found, check if ANY bedtime-related averaging exists
    # This could be manual analysis
    general_avg_matches = find_formula_patterns_in_sheet(sheet_data, [r'AVERAGE'])
    if len(general_avg_matches) >= 2:  # Multiple average calculations suggest analysis
        return True, "Multiple average calculations found (manual bedtime analysis)"
    
    return False, "No optimal bedtime analysis found"


def check_data_complexity(sheet_data: List[List[Dict]]) -> int:
    """
    Count total number of formulas to assess overall complexity.
    """
    formula_count = 0
    for row in sheet_data:
        for cell in row:
            if isinstance(cell, dict) and cell.get('formula'):
                formula_count += 1
    return formula_count


def verify_sleep_pattern_optimizer(traj, env_info, task_info):
    """
    Verify sleep pattern optimizer task completion.
    
    Checks:
    1. Sleep duration formula (time arithmetic with midnight handling)
    2. Quality categorization formula (IF statements)
    3. Conditional formatting present
    4. Factor correlation formulas (AVERAGEIF for caffeine, screen time, exercise)
    5. Optimal bedtime analysis
    6. Overall data complexity
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file paths
    paths_to_try = [
        ("/home/ga/Documents/sleep_analysis.ods", "ods"),
        ("/home/ga/Documents/sleep_log.ods", "ods"),
        ("/home/ga/Documents/sleep_log.csv", "csv"),
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
            "feedback": f"Failed to load spreadsheet: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = workbook['sheets'][sheet_name]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Sleep Duration Formula
        has_duration, duration_msg = check_time_arithmetic_formulas(sheet_data)
        if has_duration:
            criteria_passed += 1
            feedback_parts.append(f"✅ {duration_msg}")
            subscores['sleep_duration_formula'] = True
        else:
            feedback_parts.append(f"❌ {duration_msg}")
            subscores['sleep_duration_formula'] = False
        
        # Criterion 2: Quality Categorization
        has_categories, category_msg = check_quality_categorization_formulas(sheet_data)
        if has_categories:
            criteria_passed += 1
            feedback_parts.append(f"✅ {category_msg}")
            subscores['quality_categorization'] = True
        else:
            feedback_parts.append(f"❌ {category_msg}")
            subscores['quality_categorization'] = False
        
        # Criterion 3: Conditional Formatting
        # Try to check conditional formatting (may not work with all parsers)
        try:
            has_formatting = check_conditional_formatting(workbook, sheet_name, "D:D")
            if has_formatting:
                criteria_passed += 1
                feedback_parts.append("✅ Conditional formatting detected")
                subscores['conditional_formatting'] = True
            else:
                # Give partial credit if we can't reliably detect it
                feedback_parts.append("⚠️ Conditional formatting not detected (may be present)")
                subscores['conditional_formatting'] = False
        except Exception as e:
            logger.warning(f"Could not check conditional formatting: {e}")
            feedback_parts.append("⚠️ Conditional formatting check unavailable")
            subscores['conditional_formatting'] = False
        
        # Criterion 4: Factor Correlation (AVERAGEIF formulas)
        has_averageif, averageif_formulas = check_averageif_formulas(sheet_data)
        if has_averageif:
            criteria_passed += 1
            feedback_parts.append(f"✅ Statistical correlation formulas found ({len(averageif_formulas)} AVERAGEIF)")
            subscores['factor_correlation'] = True
        else:
            feedback_parts.append("❌ No AVERAGEIF formulas for factor correlation")
            subscores['factor_correlation'] = False
        
        # Criterion 5: Optimal Bedtime Analysis
        has_bedtime, bedtime_msg = check_optimal_bedtime_analysis(sheet_data)
        if has_bedtime:
            criteria_passed += 1
            feedback_parts.append(f"✅ {bedtime_msg}")
            subscores['optimal_bedtime_analysis'] = True
        else:
            feedback_parts.append(f"❌ {bedtime_msg}")
            subscores['optimal_bedtime_analysis'] = False
        
        # Criterion 6: Overall Complexity Check
        formula_count = check_data_complexity(sheet_data)
        if formula_count >= 10:  # Expect at least 10 formulas for thorough analysis
            criteria_passed += 1
            feedback_parts.append(f"✅ Sufficient formula complexity ({formula_count} formulas)")
            subscores['data_complexity'] = True
        else:
            feedback_parts.append(f"⚠️ Limited formula usage ({formula_count} formulas, expected 10+)")
            subscores['data_complexity'] = False
            # Give partial credit
            if formula_count >= 5:
                criteria_passed += 0.5
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 70%
        
        # Add summary feedback
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent sleep pattern analysis!")
        elif passed:
            feedback_parts.append("✅ Sleep pattern analysis completed")
        else:
            feedback_parts.append("❌ Analysis incomplete - missing key formulas")
        
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
        # Clean up temporary directory
        if temp_dir:
            cleanup_verification_temp(temp_dir)
