#!/usr/bin/env python3
"""
Verifier for Chili Cook-Off Score Normalizer task
Checks normalization, missing data handling, rankings, and prize distribution
"""

import sys
import os
import logging
from typing import Dict, Any, Tuple, List, Optional

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_contestant_data(workbook: Dict, sheet_name: str, row: int) -> Dict[str, Any]:
    """Extract contestant data from a specific row"""
    return {
        'name': get_cell_value(workbook, sheet_name, f'A{row}'),
        'judge1_raw': get_cell_value(workbook, sheet_name, f'B{row}'),
        'judge2_raw': get_cell_value(workbook, sheet_name, f'C{row}'),
        'judge3_raw': get_cell_value(workbook, sheet_name, f'D{row}'),
        'judge4_raw': get_cell_value(workbook, sheet_name, f'E{row}'),
    }


def find_normalized_columns(workbook: Dict, sheet_name: str) -> Optional[Dict[str, str]]:
    """
    Find normalized score columns in the spreadsheet.
    Returns dict mapping judge names to column letters, or None if not found.
    """
    # Look for normalized scores in columns F onwards
    # Common patterns: "Normalized", "Norm", "Judge X (1-10)", etc.
    
    # Try to find by scanning headers or just assume standard layout
    # Assuming normalized scores start at column F
    return {
        'judge1_norm_col': 'F',
        'judge2_norm_col': 'G', 
        'judge3_norm_col': 'H',
        'judge4_norm_col': 'I',
        'average_col': 'J',
        'rank_col': 'K',
        'prize_col': 'L'
    }


def verify_normalization(workbook: Dict, sheet_name: str, start_row: int = 2, end_row: int = 9) -> Tuple[bool, List[str]]:
    """
    Verify that 1-5 scale scores are correctly converted to 1-10 scale.
    Judge 1 and 2: should remain unchanged
    Judge 3 and 4: should be multiplied by 2
    """
    feedback = []
    all_correct = True
    errors_found = 0
    
    cols = find_normalized_columns(workbook, sheet_name)
    if not cols:
        return False, ["❌ Could not find normalized score columns"]
    
    for row in range(start_row, end_row + 1):
        # Check Judge 3 normalization (column D to H: should be *2)
        judge3_raw = get_cell_value(workbook, sheet_name, f'D{row}')
        judge3_norm = get_cell_value(workbook, sheet_name, f'H{row}')
        
        if judge3_raw is not None and judge3_raw != '' and judge3_raw != 'N/A':
            expected = float(judge3_raw) * 2
            if judge3_norm is not None:
                try:
                    actual = float(judge3_norm)
                    if abs(actual - expected) > 0.1:
                        all_correct = False
                        errors_found += 1
                        if errors_found <= 2:  # Limit feedback spam
                            feedback.append(f"❌ Row {row} Judge3: expected {expected}, got {actual}")
                except (ValueError, TypeError):
                    all_correct = False
                    errors_found += 1
        
        # Check Judge 4 normalization (column E to I: should be *2)
        judge4_raw = get_cell_value(workbook, sheet_name, f'E{row}')
        judge4_norm = get_cell_value(workbook, sheet_name, f'I{row}')
        
        if judge4_raw is not None and judge4_raw != '' and judge4_raw != 'N/A':
            expected = float(judge4_raw) * 2
            if judge4_norm is not None:
                try:
                    actual = float(judge4_norm)
                    if abs(actual - expected) > 0.1:
                        all_correct = False
                        errors_found += 1
                        if errors_found <= 2:
                            feedback.append(f"❌ Row {row} Judge4: expected {expected}, got {actual}")
                except (ValueError, TypeError):
                    all_correct = False
                    errors_found += 1
    
    if all_correct:
        feedback.append("✅ All 1-5 scores correctly normalized to 1-10 scale")
    elif errors_found > 2:
        feedback.append(f"❌ Normalization errors found in {errors_found} cells")
    
    return all_correct, feedback


def verify_missing_data_handling(workbook: Dict, sheet_name: str) -> Tuple[bool, List[str]]:
    """
    Verify that missing data is handled correctly.
    - Row 4 (Three Bean): Judge2 is missing, average should be from 3 judges
    - Row 9 (Sweet & Savory): Judge4 is missing, average should be from 3 judges
    """
    feedback = []
    correct_count = 0
    
    # Three Bean (row 4): Judge1=9, Judge2=missing, Judge3=5*2=10, Judge4=5*2=10
    # Expected average: (9 + 10 + 10) / 3 = 9.67
    three_bean_avg = get_cell_value(workbook, sheet_name, 'J4')
    if three_bean_avg is not None:
        try:
            avg_val = float(three_bean_avg)
            expected = 9.67
            if abs(avg_val - expected) < 0.2:  # Allow some tolerance
                correct_count += 1
                feedback.append(f"✅ Three Bean average correct: {avg_val:.2f}")
            else:
                feedback.append(f"❌ Three Bean average incorrect: expected ~{expected:.2f}, got {avg_val:.2f}")
        except (ValueError, TypeError):
            feedback.append(f"❌ Three Bean average not numeric: {three_bean_avg}")
    else:
        feedback.append("❌ Three Bean average missing")
    
    # Sweet & Savory (row 9): Judge1=7, Judge2=8, Judge3=3*2=6, Judge4=missing
    # Expected average: (7 + 8 + 6) / 3 = 7.0
    sweet_savory_avg = get_cell_value(workbook, sheet_name, 'J9')
    if sweet_savory_avg is not None:
        try:
            avg_val = float(sweet_savory_avg)
            expected = 7.0
            if abs(avg_val - expected) < 0.2:
                correct_count += 1
                feedback.append(f"✅ Sweet & Savory average correct: {avg_val:.2f}")
            else:
                feedback.append(f"❌ Sweet & Savory average incorrect: expected ~{expected:.2f}, got {avg_val:.2f}")
        except (ValueError, TypeError):
            feedback.append(f"❌ Sweet & Savory average not numeric: {sweet_savory_avg}")
    else:
        feedback.append("❌ Sweet & Savory average missing")
    
    return correct_count >= 2, feedback


def verify_rankings(workbook: Dict, sheet_name: str) -> Tuple[bool, List[str]]:
    """
    Verify that contestants are correctly ranked by average score.
    Expected rankings (approximate):
    1. Cincinnati Style: 9.75
    2. Three Bean: 9.67
    3. Spicy Red: 8.75
    4. Green Chile: 7.75
    5. Smoky Blues: 7.25
    6. Sweet & Savory: 7.0
    7. Texas Heat: 6.75
    8. White Chili: 5.25
    """
    feedback = []
    rankings_data = []
    
    for row in range(2, 10):  # 8 contestants
        name = get_cell_value(workbook, sheet_name, f'A{row}')
        avg_score = get_cell_value(workbook, sheet_name, f'J{row}')
        rank = get_cell_value(workbook, sheet_name, f'K{row}')
        
        if name and avg_score is not None and rank is not None:
            try:
                rankings_data.append({
                    'name': name,
                    'avg': float(avg_score),
                    'rank': int(rank),
                    'row': row
                })
            except (ValueError, TypeError):
                feedback.append(f"❌ Invalid data in row {row}")
    
    if len(rankings_data) < 8:
        feedback.append(f"❌ Missing ranking data (found {len(rankings_data)}/8)")
        return False, feedback
    
    # Sort by average score (descending) to get expected rankings
    sorted_by_avg = sorted(rankings_data, key=lambda x: x['avg'], reverse=True)
    
    # Check if assigned ranks match expected ranks
    rank_errors = 0
    for expected_rank, contestant in enumerate(sorted_by_avg, start=1):
        if contestant['rank'] != expected_rank:
            rank_errors += 1
            if rank_errors <= 2:
                feedback.append(f"❌ {contestant['name']}: expected rank {expected_rank}, got {contestant['rank']}")
    
    if rank_errors == 0:
        feedback.append("✅ All rankings correct")
        # Verify top 3
        feedback.append(f"   1st: {sorted_by_avg[0]['name']} ({sorted_by_avg[0]['avg']:.2f})")
        feedback.append(f"   2nd: {sorted_by_avg[1]['name']} ({sorted_by_avg[1]['avg']:.2f})")
        feedback.append(f"   3rd: {sorted_by_avg[2]['name']} ({sorted_by_avg[2]['avg']:.2f})")
        return True, feedback
    else:
        feedback.append(f"❌ {rank_errors} ranking errors found")
        return False, feedback


def verify_prize_distribution(workbook: Dict, sheet_name: str) -> Tuple[bool, List[str]]:
    """
    Verify prize amounts:
    - Rank 1: $250
    - Rank 2: $150
    - Rank 3: $100
    - Ranks 4-8: $0
    - Total should equal $500
    """
    feedback = []
    prize_data = {}
    total_prizes = 0
    
    for row in range(2, 10):
        rank = get_cell_value(workbook, sheet_name, f'K{row}')
        prize = get_cell_value(workbook, sheet_name, f'L{row}')
        
        if rank is not None and prize is not None:
            try:
                rank_val = int(rank)
                prize_val = float(prize)
                prize_data[rank_val] = prize_val
                total_prizes += prize_val
            except (ValueError, TypeError):
                feedback.append(f"❌ Invalid prize/rank data in row {row}")
    
    # Check individual prizes
    expected_prizes = {1: 250, 2: 150, 3: 100, 4: 0, 5: 0, 6: 0, 7: 0, 8: 0}
    errors = 0
    
    for rank, expected in expected_prizes.items():
        if rank in prize_data:
            actual = prize_data[rank]
            if abs(actual - expected) > 0.01:
                errors += 1
                feedback.append(f"❌ Rank {rank}: expected ${expected}, got ${actual}")
        else:
            errors += 1
            feedback.append(f"❌ Missing prize for rank {rank}")
    
    # Check total
    if abs(total_prizes - 500) > 0.01:
        errors += 1
        feedback.append(f"❌ Total prizes: expected $500, got ${total_prizes}")
    
    if errors == 0:
        feedback.append("✅ Prize distribution correct ($250/$150/$100, total=$500)")
        return True, feedback
    else:
        return False, feedback


def check_formulas_used(workbook: Dict, sheet_name: str) -> Tuple[bool, List[str]]:
    """Check that formulas are used (not hardcoded values)"""
    feedback = []
    formula_count = 0
    
    # Check a few cells for formulas
    check_cells = ['J2', 'K2', 'L2', 'H2', 'I2']  # Average, Rank, Prize, Normalized scores
    
    for cell in check_cells:
        formula = get_cell_formula(workbook, sheet_name, cell)
        if formula:
            formula_count += 1
    
    if formula_count >= 3:
        feedback.append(f"✅ Formulas detected ({formula_count}/{len(check_cells)} cells)")
        return True, feedback
    else:
        feedback.append(f"❌ Insufficient formulas detected ({formula_count}/{len(check_cells)} cells)")
        return False, feedback


def check_no_errors(workbook: Dict, sheet_name: str) -> Tuple[bool, List[str]]:
    """Check for calculation errors in key columns"""
    feedback = []
    error_count = 0
    
    # Check for error values in columns J, K, L (average, rank, prize)
    for row in range(2, 10):
        for col in ['J', 'K', 'L']:
            value = get_cell_value(workbook, sheet_name, f'{col}{row}')
            if isinstance(value, str) and ('#' in str(value) or 'ERR' in str(value).upper()):
                error_count += 1
                feedback.append(f"❌ Error in cell {col}{row}: {value}")
    
    if error_count == 0:
        feedback.append("✅ No calculation errors detected")
        return True, feedback
    else:
        feedback.append(f"❌ {error_count} calculation errors found")
        return False, feedback


def verify_chili_cookoff_scorer(traj, env_info, task_info):
    """
    Main verification function for Chili Cook-Off Score Normalizer task.
    
    Checks:
    1. Normalization correct (1-5 to 1-10 scale)
    2. Missing data handled properly
    3. Rankings accurate
    4. Prizes correct
    5. Formulas used
    6. No calculation errors
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    temp_dir = None
    success = False
    
    for path in ['/home/ga/Documents/chili_cookoff_result.ods',
                 '/home/ga/Documents/chili_scores_raw.ods',
                 '/home/ga/Documents/chili_scores_raw.csv']:
        file_format = 'ods' if path.endswith('.ods') else 'csv'
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path, copy_from_env, file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {path}")
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
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = sheet_names[0]
        logger.info(f"Verifying sheet: {sheet_name}")
        
        # Run all verification checks
        criteria_passed = 0
        total_criteria = 6
        all_feedback = []
        
        # 1. Normalization
        norm_ok, norm_feedback = verify_normalization(workbook, sheet_name)
        all_feedback.extend(norm_feedback)
        if norm_ok:
            criteria_passed += 1
        
        # 2. Missing data handling
        missing_ok, missing_feedback = verify_missing_data_handling(workbook, sheet_name)
        all_feedback.extend(missing_feedback)
        if missing_ok:
            criteria_passed += 1
        
        # 3. Rankings
        rank_ok, rank_feedback = verify_rankings(workbook, sheet_name)
        all_feedback.extend(rank_feedback)
        if rank_ok:
            criteria_passed += 1
        
        # 4. Prize distribution
        prize_ok, prize_feedback = verify_prize_distribution(workbook, sheet_name)
        all_feedback.extend(prize_feedback)
        if prize_ok:
            criteria_passed += 1
        
        # 5. Formulas used
        formula_ok, formula_feedback = check_formulas_used(workbook, sheet_name)
        all_feedback.extend(formula_feedback)
        if formula_ok:
            criteria_passed += 1
        
        # 6. No errors
        no_errors_ok, error_feedback = check_no_errors(workbook, sheet_name)
        all_feedback.extend(error_feedback)
        if no_errors_ok:
            criteria_passed += 1
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 70% (4/6 criteria)
        
        # Summary feedback
        if passed and score >= 90:
            all_feedback.insert(0, "🎉 Excellent work! All scoring and calculations correct!")
        elif passed:
            all_feedback.insert(0, f"✅ Task completed ({criteria_passed}/{total_criteria} criteria)")
        else:
            all_feedback.insert(0, f"❌ Task incomplete ({criteria_passed}/{total_criteria} criteria)")
        
        feedback = " | ".join(all_feedback[:20])  # Limit feedback length
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "normalization_correct": norm_ok,
                "missing_data_handled": missing_ok,
                "rankings_accurate": rank_ok,
                "prizes_correct": prize_ok,
                "formulas_used": formula_ok,
                "no_errors": no_errors_ok
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
