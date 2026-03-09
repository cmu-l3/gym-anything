#!/usr/bin/env python3
"""
Verifier for Fantasy Football Lineup Optimizer task.

Checks:
1. Projected points calculated correctly for all players
2. Lineup status column exists with START/BENCH labels
3. Position constraints satisfied (1 QB, 2 RB, 2 WR, 1 TE, 1 FLEX)
4. Optimization quality (within 5% of greedy optimal)
"""

import sys
import os
import logging
from typing import Dict, List, Tuple, Optional

# Use relative path to utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def calculate_fantasy_points(stats: Dict[str, float]) -> float:
    """
    Calculate fantasy points using standard PPR scoring.
    
    Args:
        stats: Dictionary with keys:
            - rush_yards, rec_yards, receptions
            - rush_tds, rec_tds
            - pass_yards, pass_tds
    
    Returns:
        Total projected fantasy points
    """
    points = (
        stats.get('rush_yards', 0) * 0.1 +
        stats.get('rec_yards', 0) * 0.1 +
        stats.get('receptions', 0) * 1.0 +
        stats.get('rush_tds', 0) * 6.0 +
        stats.get('rec_tds', 0) * 6.0 +
        stats.get('pass_yards', 0) * 0.04 +
        stats.get('pass_tds', 0) * 4.0
    )
    return round(points, 1)


def parse_player_data(workbook: Dict, sheet_name: str) -> List[Dict]:
    """
    Parse player data from spreadsheet.
    
    Returns:
        List of player dictionaries with stats and calculated info
    """
    sheet_data = workbook['sheets'][sheet_name]
    
    # Find column indices from header row
    header_row = sheet_data[0] if sheet_data else []
    
    def get_col_idx(col_name: str) -> Optional[int]:
        for i, cell in enumerate(header_row):
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value and col_name.lower() in str(cell_value).lower():
                return i
        return None
    
    col_map = {
        'name': get_col_idx('player name'),
        'position': get_col_idx('position'),
        'rush_yds': get_col_idx('rush yds'),
        'rec_yds': get_col_idx('rec yds'),
        'receptions': get_col_idx('receptions'),
        'rush_tds': get_col_idx('rush tds'),
        'rec_tds': get_col_idx('rec tds'),
        'pass_yds': get_col_idx('pass yds'),
        'pass_tds': get_col_idx('pass tds'),
        'proj_points': get_col_idx('projected points'),
        'lineup_status': get_col_idx('lineup status')
    }
    
    # Parse player rows (skip header)
    players = []
    for row_idx, row in enumerate(sheet_data[1:], start=2):
        if not row or len(row) < 3:
            continue
        
        # Get player name and position
        name_val = row[col_map['name']].get('value') if isinstance(row[col_map['name']], dict) else row[col_map['name']] if col_map['name'] is not None else None
        pos_val = row[col_map['position']].get('value') if isinstance(row[col_map['position']], dict) else row[col_map['position']] if col_map['position'] is not None else None
        
        if not name_val or not pos_val:
            continue
        
        # Parse statistics
        def get_float_val(col_key: str) -> float:
            if col_map[col_key] is None or col_map[col_key] >= len(row):
                return 0.0
            cell = row[col_map[col_key]]
            val = cell.get('value') if isinstance(cell, dict) else cell
            try:
                return float(val) if val else 0.0
            except (ValueError, TypeError):
                return 0.0
        
        stats = {
            'rush_yards': get_float_val('rush_yds'),
            'rec_yards': get_float_val('rec_yds'),
            'receptions': get_float_val('receptions'),
            'rush_tds': get_float_val('rush_tds'),
            'rec_tds': get_float_val('rec_tds'),
            'pass_yards': get_float_val('pass_yds'),
            'pass_tds': get_float_val('pass_tds')
        }
        
        # Calculate expected points
        expected_points = calculate_fantasy_points(stats)
        
        # Get agent's calculated points
        agent_points = None
        if col_map['proj_points'] is not None and col_map['proj_points'] < len(row):
            cell = row[col_map['proj_points']]
            val = cell.get('value') if isinstance(cell, dict) else cell
            try:
                agent_points = float(val) if val else None
            except (ValueError, TypeError):
                agent_points = None
        
        # Get lineup status
        lineup_status = None
        if col_map['lineup_status'] is not None and col_map['lineup_status'] < len(row):
            cell = row[col_map['lineup_status']]
            val = cell.get('value') if isinstance(cell, dict) else cell
            lineup_status = str(val).strip().upper() if val else None
        
        player = {
            'row': row_idx,
            'name': str(name_val).strip(),
            'position': str(pos_val).strip().upper(),
            'stats': stats,
            'expected_points': expected_points,
            'agent_points': agent_points,
            'lineup_status': lineup_status
        }
        
        players.append(player)
    
    return players


def generate_optimal_lineup(players: List[Dict]) -> Tuple[List[Dict], float]:
    """
    Generate optimal lineup using greedy algorithm.
    
    Returns:
        Tuple of (optimal_starters_list, total_points)
    """
    # Sort players by expected points (descending)
    sorted_players = sorted(players, key=lambda p: p['expected_points'], reverse=True)
    
    lineup = []
    position_counts = {'QB': 0, 'RB': 0, 'WR': 0, 'TE': 0}
    position_requirements = {'QB': 1, 'RB': 2, 'WR': 2, 'TE': 1}
    
    # Fill required positions first
    for player in sorted_players:
        pos = player['position']
        if pos in position_counts and position_counts[pos] < position_requirements[pos]:
            lineup.append(player)
            position_counts[pos] += 1
    
    # Fill FLEX position (best remaining RB/WR/TE)
    for player in sorted_players:
        if player not in lineup and player['position'] in ['RB', 'WR', 'TE']:
            lineup.append(player)
            break
    
    total_points = sum(p['expected_points'] for p in lineup)
    return lineup, total_points


def verify_fantasy_lineup(traj, env_info, task_info):
    """
    Verify fantasy football lineup optimization task.
    
    Checks:
    1. Projected points calculated correctly
    2. Lineup status assigned to all players
    3. Position constraints satisfied
    4. Optimization quality (within 5% of optimal)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    success = False
    temp_dir = None
    workbook = None
    
    for file_path, file_format in [
        ('/home/ga/Documents/fantasy_lineup.ods', 'ods'),
        ('/home/ga/Documents/roster_week7.ods', 'ods'),
        ('/home/ga/Documents/roster_week7.csv', 'csv')
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            file_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded: {file_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet: {error}"
        }
    
    try:
        # Get sheet data
        sheet_names = get_sheet_names(workbook)
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = sheet_names[0]
        
        # Parse player data
        players = parse_player_data(workbook, sheet_name)
        
        if len(players) < 10:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Insufficient player data found (got {len(players)} players, expected 15+)"
            }
        
        # Verification criteria
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Projected points calculated correctly
        calc_correct_count = 0
        calc_total = 0
        missing_calc = 0
        
        for player in players:
            calc_total += 1
            if player['agent_points'] is None:
                missing_calc += 1
                continue
            
            # Allow 0.5 point tolerance for rounding
            if abs(player['agent_points'] - player['expected_points']) <= 0.5:
                calc_correct_count += 1
            else:
                logger.debug(
                    f"Points mismatch for {player['name']}: "
                    f"expected {player['expected_points']}, got {player['agent_points']}"
                )
        
        calc_accuracy = calc_correct_count / calc_total if calc_total > 0 else 0
        subscores['calculation_accuracy'] = calc_accuracy
        
        if missing_calc > 0:
            feedback_parts.append(
                f"❌ Projected Points column missing or incomplete ({missing_calc}/{calc_total} players)"
            )
        elif calc_accuracy >= 0.9:
            criteria_passed += 1
            feedback_parts.append(
                f"✅ Calculations correct ({calc_correct_count}/{calc_total} players accurate)"
            )
        else:
            feedback_parts.append(
                f"⚠️ Calculation errors ({calc_correct_count}/{calc_total} accurate, need 90%+)"
            )
        
        # Criterion 2: Lineup status assigned
        status_count = sum(1 for p in players if p['lineup_status'] in ['START', 'BENCH'])
        status_complete = status_count == len(players)
        subscores['status_complete'] = status_complete
        
        if status_complete:
            criteria_passed += 1
            feedback_parts.append(f"✅ Lineup status assigned to all {len(players)} players")
        else:
            feedback_parts.append(
                f"❌ Lineup status incomplete ({status_count}/{len(players)} players labeled)"
            )
        
        # Criterion 3: Position constraints satisfied
        starters = [p for p in players if p['lineup_status'] == 'START']
        starter_count = len(starters)
        
        position_counts = {'QB': 0, 'RB': 0, 'WR': 0, 'TE': 0}
        for player in starters:
            if player['position'] in position_counts:
                position_counts[player['position']] += 1
        
        constraints_met = (
            starter_count == 7 and
            position_counts['QB'] == 1 and
            position_counts['RB'] >= 2 and
            position_counts['WR'] >= 2 and
            position_counts['TE'] >= 1 and
            sum(position_counts.values()) == 7
        )
        
        subscores['constraints_satisfied'] = constraints_met
        
        if constraints_met:
            criteria_passed += 1
            feedback_parts.append(
                f"✅ Constraints satisfied: {position_counts['QB']} QB, "
                f"{position_counts['RB']} RB, {position_counts['WR']} WR, "
                f"{position_counts['TE']} TE, 1 FLEX (total: {starter_count})"
            )
        else:
            feedback_parts.append(
                f"❌ Constraint violation: {starter_count} starters "
                f"(QB:{position_counts['QB']}, RB:{position_counts['RB']}, "
                f"WR:{position_counts['WR']}, TE:{position_counts['TE']})"
            )
        
        # Criterion 4: Optimization quality
        if constraints_met and calc_accuracy > 0.5:
            # Generate optimal lineup
            optimal_lineup, optimal_points = generate_optimal_lineup(players)
            
            # Calculate agent's total points
            agent_total = sum(
                p['expected_points'] for p in starters
            )
            
            # Check if within 5% of optimal
            if optimal_points > 0:
                optimality_ratio = agent_total / optimal_points
                subscores['optimality_ratio'] = optimality_ratio
                
                if optimality_ratio >= 0.95:
                    criteria_passed += 1
                    feedback_parts.append(
                        f"✅ Lineup optimized: {agent_total:.1f} pts "
                        f"(optimal: {optimal_points:.1f}, {optimality_ratio*100:.1f}%)"
                    )
                else:
                    feedback_parts.append(
                        f"⚠️ Suboptimal lineup: {agent_total:.1f} pts "
                        f"(optimal: {optimal_points:.1f}, {optimality_ratio*100:.1f}%)"
                    )
                    # Give partial credit if reasonably close
                    if optimality_ratio >= 0.85:
                        criteria_passed += 0.5
            else:
                feedback_parts.append("⚠️ Could not calculate optimal lineup")
        else:
            feedback_parts.append("⚠️ Cannot assess optimization (constraints violated or calculations missing)")
            subscores['optimality_ratio'] = 0.0
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 85  # Need 85% to pass (strict threshold)
        
        if passed:
            feedback_parts.append("🎉 Fantasy lineup optimized successfully!")
        else:
            feedback_parts.append("❌ Task requirements not fully met")
        
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
        cleanup_verification_temp(temp_dir)
