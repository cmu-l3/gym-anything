#!/usr/bin/env python3
"""
Verifier for Judge Score Normalization task.

Checks:
1. Z-score normalization formulas are mathematically correct
2. Rankings are based on normalized scores, not raw scores
3. All data (8 pies × 4 judges) was processed
4. Rankings differ from naive averaging (proves normalization worked)
5. Top 3 winners are identified
"""

import sys
import os
import logging
import numpy as np

# Use relative path to utils folder (runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Original judge scores for reference
ORIGINAL_SCORES = {
    'Apple Classic': [7, 5, 8, 9],
    'Cherry Bomb': [9, 6, 9, 10],
    'Pecan Dream': [6, 4, 7, 9],
    'Pumpkin Spice': [8, 5, 8, 10],
    'Blueberry Bliss': [7, 5, 7, 9],
    'Lemon Meringue': [9, 6, 9, 10],
    'Chocolate Silk': [8, 5, 8, 9],
    'Key Lime Tart': [6, 4, 6, 9]
}


def extract_raw_scores(sheet_data, sheet_name):
    """
    Extract raw judge scores from the spreadsheet.
    
    Returns:
        dict: {pie_name: [judge1, judge2, judge3, judge4]}
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        scores = {}
        
        # Expect header in row 0, data starts row 1
        for row_idx in range(1, min(len(rows), 10)):  # Check first 10 rows
            if row_idx >= len(rows):
                break
                
            row = rows[row_idx]
            if len(row) < 5:  # Need at least 5 columns (name + 4 judges)
                continue
            
            # Get pie name
            pie_name_cell = row[0]
            pie_name = pie_name_cell.get('value') if isinstance(pie_name_cell, dict) else pie_name_cell
            
            if not pie_name or not isinstance(pie_name, str):
                continue
            
            # Get judge scores
            judge_scores = []
            for col_idx in range(1, 5):  # Columns 1-4 (judges)
                if col_idx >= len(row):
                    break
                cell = row[col_idx]
                value = cell.get('value') if isinstance(cell, dict) else cell
                
                # Convert to numeric
                try:
                    score = float(value) if value is not None else None
                    judge_scores.append(score)
                except (ValueError, TypeError):
                    judge_scores.append(None)
            
            if len(judge_scores) == 4 and all(s is not None for s in judge_scores):
                scores[pie_name.strip()] = judge_scores
        
        return scores
    
    except Exception as e:
        logger.error(f"Error extracting raw scores: {e}", exc_info=True)
        return {}


def find_normalized_scores(sheet_data, sheet_name):
    """
    Find normalized z-scores in the spreadsheet.
    Looks for columns with values in typical z-score range (-3 to +3).
    
    Returns:
        dict: {pie_name: [z1, z2, z3, z4]} or None if not found
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        # Look for z-scores in various locations
        # Check columns 5-20 for z-score-like patterns
        for start_col in range(5, min(20, len(rows[0]) if rows else 10)):
            candidate_scores = {}
            
            for row_idx in range(1, min(len(rows), 10)):
                if row_idx >= len(rows):
                    break
                
                row = rows[row_idx]
                if len(row) <= start_col:
                    continue
                
                # Get pie name from column 0
                pie_name_cell = row[0]
                pie_name = pie_name_cell.get('value') if isinstance(pie_name_cell, dict) else pie_name_cell
                
                if not pie_name or not isinstance(pie_name, str):
                    continue
                
                # Get potential z-scores
                z_scores = []
                for col_offset in range(4):  # 4 judges
                    col_idx = start_col + col_offset
                    if col_idx >= len(row):
                        break
                    
                    cell = row[col_idx]
                    value = cell.get('value') if isinstance(cell, dict) else cell
                    
                    try:
                        z_score = float(value) if value is not None else None
                        z_scores.append(z_score)
                    except (ValueError, TypeError):
                        z_scores.append(None)
                
                if len(z_scores) == 4 and all(z is not None for z in z_scores):
                    # Check if these look like z-scores (roughly -3 to +3 range)
                    if all(-3 < z < 3 for z in z_scores):
                        candidate_scores[pie_name.strip()] = z_scores
            
            # If we found scores for most pies, this is likely the normalized section
            if len(candidate_scores) >= 6:  # At least 6 out of 8 pies
                return candidate_scores
        
        return None
    
    except Exception as e:
        logger.error(f"Error finding normalized scores: {e}", exc_info=True)
        return None


def calculate_expected_zscores(raw_scores):
    """
    Calculate what the z-scores should be.
    
    Returns:
        dict: {pie_name: [z1, z2, z3, z4]}
    """
    # Organize scores by judge
    judge_scores = [[], [], [], []]
    
    for pie_name, scores in raw_scores.items():
        for j in range(4):
            judge_scores[j].append(scores[j])
    
    # Calculate mean and std for each judge
    judge_stats = []
    for j in range(4):
        scores_array = np.array(judge_scores[j])
        mean = np.mean(scores_array)
        std = np.std(scores_array, ddof=1)  # Sample std
        judge_stats.append((mean, std))
    
    # Calculate z-scores
    expected = {}
    for pie_name, scores in raw_scores.items():
        z_scores = []
        for j in range(4):
            mean, std = judge_stats[j]
            if std > 0:
                z = (scores[j] - mean) / std
            else:
                z = 0.0
            z_scores.append(z)
        expected[pie_name] = z_scores
    
    return expected


def verify_zscore_accuracy(actual_zscores, expected_zscores, tolerance=0.15):
    """
    Verify that z-scores match expected values.
    
    Returns:
        (bool, str): (success, feedback)
    """
    if not actual_zscores or not expected_zscores:
        return False, "Z-scores not found"
    
    matches = 0
    total = 0
    mismatches = []
    
    for pie_name in expected_zscores:
        if pie_name not in actual_zscores:
            continue
        
        expected = expected_zscores[pie_name]
        actual = actual_zscores[pie_name]
        
        for j in range(4):
            total += 1
            if abs(actual[j] - expected[j]) <= tolerance:
                matches += 1
            else:
                if len(mismatches) < 3:
                    mismatches.append(f"{pie_name} Judge{j+1}: expected {expected[j]:.3f}, got {actual[j]:.3f}")
    
    if total == 0:
        return False, "No z-scores to verify"
    
    accuracy = matches / total
    
    if accuracy >= 0.85:  # 85% of z-scores correct
        return True, f"Z-scores accurate ({matches}/{total} correct)"
    else:
        feedback = f"Z-scores inaccurate ({matches}/{total} correct)"
        if mismatches:
            feedback += f". Examples: {'; '.join(mismatches)}"
        return False, feedback


def find_rankings(sheet_data, sheet_name):
    """
    Find final rankings in the spreadsheet.
    
    Returns:
        dict: {pie_name: rank} or None
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        rankings = {}
        
        # Look for a column with values 1-8 (ranks)
        for col_idx in range(len(rows[0]) if rows else 0):
            candidate_ranks = {}
            
            for row_idx in range(1, min(len(rows), 10)):
                if row_idx >= len(rows):
                    break
                
                row = rows[row_idx]
                if col_idx >= len(row):
                    continue
                
                # Get pie name
                pie_name_cell = row[0]
                pie_name = pie_name_cell.get('value') if isinstance(pie_name_cell, dict) else pie_name_cell
                
                if not pie_name or not isinstance(pie_name, str):
                    continue
                
                # Get potential rank
                cell = row[col_idx]
                value = cell.get('value') if isinstance(cell, dict) else cell
                
                try:
                    rank = int(value) if value is not None else None
                    if rank and 1 <= rank <= 10:  # Valid rank range
                        candidate_ranks[pie_name.strip()] = rank
                except (ValueError, TypeError):
                    continue
            
            # If we found ranks for most pies
            if len(candidate_ranks) >= 6:
                # Verify ranks are reasonable (1-8 range)
                rank_values = list(candidate_ranks.values())
                if min(rank_values) == 1 and max(rank_values) <= 10:
                    return candidate_ranks
        
        return None
    
    except Exception as e:
        logger.error(f"Error finding rankings: {e}", exc_info=True)
        return None


def calculate_expected_rankings(raw_scores):
    """
    Calculate expected rankings based on z-score normalization.
    
    Returns:
        dict: {pie_name: rank}
    """
    # Calculate z-scores
    zscores = calculate_expected_zscores(raw_scores)
    
    # Calculate average z-score for each pie
    avg_zscores = {}
    for pie_name, scores in zscores.items():
        avg_zscores[pie_name] = np.mean(scores)
    
    # Rank by average z-score (higher is better)
    sorted_pies = sorted(avg_zscores.items(), key=lambda x: x[1], reverse=True)
    
    rankings = {}
    for rank, (pie_name, _) in enumerate(sorted_pies, start=1):
        rankings[pie_name] = rank
    
    return rankings


def calculate_naive_rankings(raw_scores):
    """
    Calculate naive rankings (simple average of raw scores).
    
    Returns:
        dict: {pie_name: rank}
    """
    avg_scores = {}
    for pie_name, scores in raw_scores.items():
        avg_scores[pie_name] = np.mean(scores)
    
    sorted_pies = sorted(avg_scores.items(), key=lambda x: x[1], reverse=True)
    
    rankings = {}
    for rank, (pie_name, _) in enumerate(sorted_pies, start=1):
        rankings[pie_name] = rank
    
    return rankings


def verify_score_normalization(traj, env_info, task_info):
    """
    Main verifier function for judge score normalization task.
    
    Checks:
    1. Z-scores calculated correctly
    2. Rankings based on normalized scores
    3. All data processed
    4. Rankings differ from naive approach
    5. Top 3 identified
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file paths
    file_paths = [
        ("/home/ga/Documents/normalized_scores.ods", 'ods'),
        ("/home/ga/Documents/pie_competition.ods", 'ods'),
        ("/home/ga/Documents/pie_competition.csv", 'csv'),
    ]
    
    success = False
    file_info = None
    
    for container_path, fmt in file_paths:
        logger.info(f"Trying to load: {container_path}")
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            container_path,
            [fmt]
        )
        if success:
            logger.info(f"Successfully loaded: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load spreadsheet: {error}"
        }
    
    try:
        sheet_data = file_info['sheet_data']
        sheet_name = list(sheet_data['sheets'].keys())[0]
        
        criteria_met = 0
        total_criteria = 5
        feedback_parts = []
        
        # Extract raw scores
        raw_scores = extract_raw_scores(sheet_data, sheet_name)
        
        if len(raw_scores) < 6:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not find raw score data (found {len(raw_scores)} pies, need 8)"
            }
        
        logger.info(f"Found {len(raw_scores)} pie scores")
        
        # Criterion 1: Z-scores calculated correctly
        actual_zscores = find_normalized_scores(sheet_data, sheet_name)
        expected_zscores = calculate_expected_zscores(raw_scores)
        
        zscore_correct, zscore_feedback = verify_zscore_accuracy(actual_zscores, expected_zscores)
        
        if zscore_correct:
            criteria_met += 1
            feedback_parts.append(f"✅ {zscore_feedback}")
        else:
            if actual_zscores:
                feedback_parts.append(f"❌ {zscore_feedback}")
            else:
                feedback_parts.append("❌ No z-score normalization found")
        
        # Criterion 2: Rankings based on normalized scores
        actual_rankings = find_rankings(sheet_data, sheet_name)
        expected_rankings = calculate_expected_rankings(raw_scores)
        
        if actual_rankings and len(actual_rankings) >= 6:
            # Check if rankings match expected (allow some flexibility for ties)
            rank_matches = 0
            for pie_name, expected_rank in expected_rankings.items():
                if pie_name in actual_rankings:
                    actual_rank = actual_rankings[pie_name]
                    # Allow ±1 difference (ties might be handled differently)
                    if abs(actual_rank - expected_rank) <= 1:
                        rank_matches += 1
            
            rank_accuracy = rank_matches / len(expected_rankings)
            
            if rank_accuracy >= 0.75:  # 75% of rankings correct
                criteria_met += 1
                feedback_parts.append(f"✅ Rankings based on normalized scores ({rank_matches}/{len(expected_rankings)} correct)")
            else:
                feedback_parts.append(f"❌ Rankings incorrect ({rank_matches}/{len(expected_rankings)} correct)")
        else:
            feedback_parts.append("❌ No rankings found")
        
        # Criterion 3: All data processed
        if len(raw_scores) >= 8 and (not actual_zscores or len(actual_zscores) >= 6):
            criteria_met += 1
            feedback_parts.append("✅ All data processed (8 pies × 4 judges)")
        else:
            feedback_parts.append(f"❌ Incomplete data processing (found {len(actual_zscores or {})} normalized pies)")
        
        # Criterion 4: Rankings differ from naive approach
        naive_rankings = calculate_naive_rankings(raw_scores)
        
        if actual_rankings:
            differences = 0
            for pie_name in naive_rankings:
                if pie_name in actual_rankings:
                    if naive_rankings[pie_name] != actual_rankings[pie_name]:
                        differences += 1
            
            if differences >= 2:  # At least 2 pies ranked differently
                criteria_met += 1
                feedback_parts.append(f"✅ Rankings differ from naive averaging ({differences} changes)")
            else:
                feedback_parts.append("⚠️ Rankings similar to naive averaging (normalization may not have worked)")
        
        # Criterion 5: Top 3 identified
        top_3 = []
        if actual_rankings:
            top_3 = [name for name, rank in actual_rankings.items() if rank <= 3]
            if len(top_3) >= 3:
                criteria_met += 1
                feedback_parts.append(f"✅ Top 3 winners identified")
            else:
                feedback_parts.append("⚠️ Top 3 winners not clearly identified")
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent statistical normalization!")
        elif passed:
            feedback_parts.append("✅ Score normalization completed")
        else:
            feedback_parts.append("❌ Normalization requirements not met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "zscore_correct": zscore_correct,
                "rankings_correct": actual_rankings is not None and len(actual_rankings) >= 6,
                "all_data_processed": len(raw_scores) >= 8,
                "differs_from_naive": actual_rankings is not None,
                "top3_identified": len(top_3) >= 3 if actual_rankings else False
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
        cleanup_verification_temp(file_info.get('temp_dir'))
