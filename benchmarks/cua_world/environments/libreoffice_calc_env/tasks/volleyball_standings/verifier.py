#!/usr/bin/env python3
"""
Verifier for Volleyball Standings task.

Checks:
1. Points formulas present and correct
2. Win% formulas present and correct
3. Data sorted correctly by points (primary) and win% (secondary)
4. Data integrity maintained
"""

import sys
import os
import logging
import re
from typing import Dict, List, Tuple, Any, Optional

# Add utils to path (relative path for host execution)
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


def normalize_formula(formula: Optional[str]) -> str:
    """Normalize formula for comparison (remove spaces, uppercase)"""
    if not formula:
        return ""
    return formula.replace(' ', '').upper()


def check_points_formula(formula: Optional[str], row_num: int) -> bool:
    """
    Check if formula calculates points correctly.
    Valid patterns: =B*3+C, =(B*3)+C, =(B*3)+(C*1), =3*B+C, etc.
    """
    if not formula:
        return False
    
    norm = normalize_formula(formula)
    
    # Expected patterns for row_num (e.g., row 2)
    patterns = [
        rf'=B{row_num}\*3\+C{row_num}',           # =B2*3+C2
        rf'=\(B{row_num}\*3\)\+C{row_num}',       # =(B2*3)+C2
        rf'=\(B{row_num}\*3\)\+\(C{row_num}\*1\)',  # =(B2*3)+(C2*1)
        rf'=\(B{row_num}\*3\)\+\(C{row_num}\)',   # =(B2*3)+(C2)
        rf'=3\*B{row_num}\+C{row_num}',           # =3*B2+C2
        rf'=\(3\*B{row_num}\)\+C{row_num}',       # =(3*B2)+C2
        rf'=B{row_num}\*3\+C{row_num}\*1',        # =B2*3+C2*1
    ]
    
    for pattern in patterns:
        if re.search(pattern, norm):
            return True
    
    return False


def check_winpct_formula(formula: Optional[str], row_num: int) -> bool:
    """
    Check if formula calculates win percentage correctly.
    Valid patterns: =B/(B+C), =B2/(B2+C2), etc.
    """
    if not formula:
        return False
    
    norm = normalize_formula(formula)
    
    # Expected patterns
    patterns = [
        rf'=B{row_num}/\(B{row_num}\+C{row_num}\)',  # =B2/(B2+C2)
        rf'=B{row_num}/\(C{row_num}\+B{row_num}\)',  # =B2/(C2+B2) - also valid
    ]
    
    for pattern in patterns:
        if re.search(pattern, norm):
            return True
    
    return False


def extract_team_data(workbook: Dict[str, Any], sheet_name: str) -> List[Dict[str, Any]]:
    """
    Extract team data from spreadsheet.
    Returns list of dicts with team info.
    """
    teams = []
    
    # Rows 2-9 should contain team data (row 1 is header)
    for row_idx in range(2, 10):  # 2 through 9 inclusive
        team_name = get_cell_value(workbook, sheet_name, f'A{row_idx}')
        wins = get_cell_value(workbook, sheet_name, f'B{row_idx}')
        losses = get_cell_value(workbook, sheet_name, f'C{row_idx}')
        points = get_cell_value(workbook, sheet_name, f'D{row_idx}')
        win_pct = get_cell_value(workbook, sheet_name, f'E{row_idx}')
        
        points_formula = get_cell_formula(workbook, sheet_name, f'D{row_idx}')
        win_pct_formula = get_cell_formula(workbook, sheet_name, f'E{row_idx}')
        
        # Skip empty rows
        if not team_name:
            continue
        
        teams.append({
            'row': row_idx,
            'team': str(team_name).strip() if team_name else '',
            'wins': int(wins) if isinstance(wins, (int, float)) else 0,
            'losses': int(losses) if isinstance(losses, (int, float)) else 0,
            'points': float(points) if isinstance(points, (int, float)) else 0,
            'win_pct': float(win_pct) if isinstance(win_pct, (int, float)) else 0,
            'points_formula': points_formula,
            'win_pct_formula': win_pct_formula
        })
    
    return teams


def verify_sort_order(teams: List[Dict[str, Any]]) -> Tuple[bool, str]:
    """
    Verify teams are sorted by points DESC, then win_pct DESC.
    """
    for i in range(len(teams) - 1):
        current = teams[i]
        next_team = teams[i + 1]
        
        # Primary criterion: Points (higher is better)
        if current['points'] < next_team['points']:
            return False, f"Sort error: {current['team']} ({current['points']} pts) ranked above {next_team['team']} ({next_team['points']} pts)"
        
        # Secondary criterion: Win% (higher is better) when points are equal
        if abs(current['points'] - next_team['points']) < 0.01:  # Points are equal (within tolerance)
            if current['win_pct'] < next_team['win_pct'] - 0.001:  # Small tolerance for floating point
                return False, f"Tiebreaker error: {current['team']} (win% {current['win_pct']:.3f}) ranked above {next_team['team']} (win% {next_team['win_pct']:.3f}) despite equal points"
    
    return True, "Sort order correct"


def verify_volleyball_standings(traj, env_info, task_info):
    """
    Main verification function for volleyball standings task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file paths (ODS preferred, CSV fallback)
    temp_dir = None
    success = False
    workbook = None
    
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/volleyball_standings_final.ods'),
        ('ods', '/home/ga/Documents/volleyball_standings.ods'),
        ('csv', '/home/ga/Documents/volleyball_standings.csv')
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load standings file: {error}"
        }
    
    try:
        # Get sheet name
        sheet_names = get_sheet_names(workbook)
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        logger.info(f"Using sheet: {sheet_name}")
        
        # Extract team data
        teams = extract_team_data(workbook, sheet_name)
        
        if len(teams) < 8:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Expected 8 teams, found {len(teams)}"
            }
        
        # Criteria tracking
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        # Criterion 1: Points formulas present
        points_formula_count = sum(1 for t in teams if t['points_formula'])
        if points_formula_count >= 8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Points formulas present ({points_formula_count}/8)")
        else:
            feedback_parts.append(f"❌ Missing points formulas ({points_formula_count}/8)")
        
        # Criterion 2: Points calculations correct
        points_correct_count = 0
        for team in teams:
            expected_points = (team['wins'] * 3) + team['losses']
            if abs(team['points'] - expected_points) < 0.01:
                points_correct_count += 1
            else:
                logger.warning(f"{team['team']}: Points mismatch (got {team['points']}, expected {expected_points})")
        
        if points_correct_count >= 8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Points calculations correct ({points_correct_count}/8)")
        else:
            feedback_parts.append(f"❌ Points calculation errors ({points_correct_count}/8 correct)")
        
        # Criterion 3: Win% formulas present
        winpct_formula_count = sum(1 for t in teams if t['win_pct_formula'])
        if winpct_formula_count >= 8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Win% formulas present ({winpct_formula_count}/8)")
        else:
            feedback_parts.append(f"❌ Missing win% formulas ({winpct_formula_count}/8)")
        
        # Criterion 4: Win% calculations correct
        winpct_correct_count = 0
        for team in teams:
            total_games = team['wins'] + team['losses']
            if total_games > 0:
                expected_pct = team['wins'] / total_games
                if abs(team['win_pct'] - expected_pct) < 0.001:
                    winpct_correct_count += 1
                else:
                    logger.warning(f"{team['team']}: Win% mismatch (got {team['win_pct']:.3f}, expected {expected_pct:.3f})")
        
        if winpct_correct_count >= 8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Win% calculations correct ({winpct_correct_count}/8)")
        else:
            feedback_parts.append(f"❌ Win% calculation errors ({winpct_correct_count}/8 correct)")
        
        # Criterion 5: Formulas are actual formulas (not hardcoded)
        actual_formulas_count = 0
        for team in teams:
            # Check if formulas follow expected patterns
            points_formula_valid = check_points_formula(team['points_formula'], team['row'])
            winpct_formula_valid = check_winpct_formula(team['win_pct_formula'], team['row'])
            
            if points_formula_valid and winpct_formula_valid:
                actual_formulas_count += 1
        
        if actual_formulas_count >= 6:  # At least 6/8 teams with proper formulas
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas properly structured ({actual_formulas_count}/8)")
        else:
            feedback_parts.append(f"⚠️ Some formulas may be hardcoded or incorrect structure ({actual_formulas_count}/8)")
        
        # Criterion 6: Primary sort correct (by points descending)
        sort_valid, sort_msg = verify_sort_order(teams)
        if sort_valid:
            criteria_passed += 1
            feedback_parts.append("✅ Sort order correct (points DESC, win% DESC)")
        else:
            feedback_parts.append(f"❌ {sort_msg}")
        
        # Criterion 7: Data integrity (team records aligned)
        # Check that wins/losses make sense with points and win%
        integrity_issues = 0
        for team in teams:
            expected_points = (team['wins'] * 3) + team['losses']
            total_games = team['wins'] + team['losses']
            
            if total_games > 0:
                expected_pct = team['wins'] / total_games
                
                # Check if calculated values match the team's record
                if abs(team['points'] - expected_points) > 0.01 or abs(team['win_pct'] - expected_pct) > 0.001:
                    integrity_issues += 1
        
        if integrity_issues == 0:
            criteria_passed += 1
            feedback_parts.append("✅ Data integrity maintained")
        else:
            feedback_parts.append(f"❌ Data integrity issues ({integrity_issues} teams)")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold is 70% (5/7 criteria)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🏐 Excellent work! Standings calculated and sorted correctly!")
        elif passed:
            feedback_parts.append("✅ Standings task completed")
        else:
            feedback_parts.append("❌ Standings task requirements not met")
        
        feedback = " | ".join(feedback_parts)
        
        # Log team standings for debugging
        logger.info("Final standings order:")
        for i, team in enumerate(teams, 1):
            logger.info(f"  {i}. {team['team']}: {team['points']} pts, {team['win_pct']:.3f} win%")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "points_formulas_present": points_formula_count >= 8,
                "points_calculations_correct": points_correct_count >= 8,
                "winpct_formulas_present": winpct_formula_count >= 8,
                "winpct_calculations_correct": winpct_correct_count >= 8,
                "formulas_structured_correctly": actual_formulas_count >= 6,
                "sort_order_correct": sort_valid,
                "data_integrity_maintained": integrity_issues == 0
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
        cleanup_verification_temp(temp_dir)
