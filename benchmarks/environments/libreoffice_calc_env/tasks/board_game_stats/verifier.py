#!/usr/bin/env python3
"""
Verifier for Board Game Stats task
Checks player statistics, formula usage, and win rate calculations
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since verification runs on the host machine
# USE Relative path to the utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_game_log_data(sheet_data, sheet_name):
    """
    Extract game log data from the spreadsheet.
    Returns dict with player names and their actual win counts.
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        # Find the Winner column (usually column C or index 2)
        winner_col_idx = None
        header_row = rows[0] if rows else []
        
        for idx, cell in enumerate(header_row):
            cell_val = cell.get('value') if isinstance(cell, dict) else cell
            if cell_val and 'winner' in str(cell_val).lower():
                winner_col_idx = idx
                break
        
        if winner_col_idx is None:
            # Assume column C (index 2) if header not found
            winner_col_idx = 2
        
        # Count wins per player
        win_counts = {}
        for row_idx in range(1, len(rows)):  # Skip header
            row = rows[row_idx]
            if winner_col_idx < len(row):
                winner_cell = row[winner_col_idx]
                winner = winner_cell.get('value') if isinstance(winner_cell, dict) else winner_cell
                
                if winner and isinstance(winner, str):
                    winner = winner.strip()
                    if winner:  # Non-empty
                        win_counts[winner] = win_counts.get(winner, 0) + 1
        
        logger.info(f"Extracted win counts from game log: {win_counts}")
        return win_counts
    
    except Exception as e:
        logger.error(f"Error extracting game log: {e}", exc_info=True)
        return {}


def find_player_stats_section(sheet_data, sheet_name):
    """
    Find the player statistics section in the spreadsheet.
    Returns dict with player stats and their locations.
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        # Look for player names and statistics
        # Common patterns: "Player", "Name", "Total Wins", "Win Rate", "Wins", "Games"
        stats_section = {
            'players': {},
            'found': False,
            'location': None
        }
        
        player_names = ['Alex', 'Blake', 'Casey', 'Drew', 'Ellis']
        
        # Scan through rows looking for player statistics
        for row_idx, row in enumerate(rows):
            for col_idx, cell in enumerate(row):
                cell_val = cell.get('value') if isinstance(cell, dict) else cell
                
                # Check if this cell contains a player name
                if cell_val in player_names:
                    # This might be the stats section
                    # Look for adjacent cells with numbers (wins, games, percentages)
                    player_name = cell_val
                    
                    # Check next few columns for statistics
                    wins = None
                    games = None
                    win_rate = None
                    win_rate_formula = None
                    
                    if col_idx + 1 < len(row):
                        next_cell = row[col_idx + 1]
                        next_val = next_cell.get('value') if isinstance(next_cell, dict) else next_cell
                        if isinstance(next_val, (int, float)):
                            wins = next_val
                    
                    if col_idx + 2 < len(row):
                        next_cell = row[col_idx + 2]
                        next_val = next_cell.get('value') if isinstance(next_cell, dict) else next_cell
                        if isinstance(next_val, (int, float)):
                            games = next_val
                    
                    if col_idx + 3 < len(row):
                        next_cell = row[col_idx + 3]
                        next_val = next_cell.get('value') if isinstance(next_cell, dict) else next_cell
                        next_formula = next_cell.get('formula') if isinstance(next_cell, dict) else None
                        if isinstance(next_val, (int, float)):
                            win_rate = next_val
                        if next_formula:
                            win_rate_formula = next_formula
                    
                    if wins is not None or games is not None or win_rate is not None:
                        stats_section['players'][player_name] = {
                            'wins': wins,
                            'games': games,
                            'win_rate': win_rate,
                            'win_rate_formula': win_rate_formula,
                            'location': (row_idx, col_idx)
                        }
                        stats_section['found'] = True
        
        logger.info(f"Found player stats section: {stats_section}")
        return stats_section
    
    except Exception as e:
        logger.error(f"Error finding stats section: {e}", exc_info=True)
        return {'players': {}, 'found': False}


def check_formula_usage(sheet_data, sheet_name):
    """
    Check if COUNTIF or similar formulas are used for counting wins.
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        formula_patterns = [
            r'COUNTIF',
            r'COUNTIFS',
            r'SUMPRODUCT',
            r'SUM.*IF'
        ]
        
        for row in rows:
            for cell in row:
                formula = cell.get('formula') if isinstance(cell, dict) else None
                if formula:
                    formula_upper = formula.upper()
                    for pattern in formula_patterns:
                        if re.search(pattern, formula_upper):
                            logger.info(f"Found counting formula: {formula}")
                            return True
        
        return False
    
    except Exception as e:
        logger.error(f"Error checking formulas: {e}", exc_info=True)
        return False


def verify_board_game_stats(traj, env_info, task_info):
    """
    Verify board game statistics task completion.
    
    Checks:
    1. Player statistics section exists with all players
    2. Formulas used correctly (COUNTIF for counting wins)
    3. Win rates calculated (percentage formula structure)
    4. Mathematical accuracy (calculated values match expected)
    5. Top player identifiable
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/board_game_stats.ods",
        "/home/ga/Documents/game_log.ods",
        "/home/ga/Documents/game_log.csv"
    ]
    
    success = False
    file_info = None
    
    for container_path in possible_paths:
        # Determine format from extension
        if container_path.endswith('.csv'):
            formats = ['csv', 'ods']
        else:
            formats = ['ods']
        
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path,
            formats
        )
        
        if success:
            logger.info(f"Successfully loaded file from: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load spreadsheet file: {error}"
        }
    
    try:
        sheet_data = file_info['sheet_data']
        sheet_names = list(sheet_data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        # Use first sheet (should contain game log and/or stats)
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # Extract actual win counts from game log
        actual_wins = extract_game_log_data(sheet_data, sheet_name)
        
        # Find player statistics section
        stats_section = find_player_stats_section(sheet_data, sheet_name)
        
        # Criterion 1: Player statistics section exists with all players
        expected_players = {'Alex', 'Blake', 'Casey', 'Drew', 'Ellis'}
        found_players = set(stats_section['players'].keys())
        
        if stats_section['found'] and len(found_players) >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Player statistics section found ({len(found_players)} players)")
        else:
            feedback_parts.append(f"❌ Player statistics section incomplete (found {len(found_players)}/5 players)")
        
        # Criterion 2: Formulas used correctly
        has_formulas = check_formula_usage(sheet_data, sheet_name)
        
        if has_formulas:
            criteria_passed += 1
            feedback_parts.append("✅ Counting formulas detected (COUNTIF or equivalent)")
        else:
            feedback_parts.append("⚠️ No COUNTIF formulas detected (may be manual counting)")
        
        # Criterion 3: Win rates calculated with formula
        win_rate_formulas_found = 0
        for player, stats in stats_section['players'].items():
            if stats.get('win_rate_formula'):
                win_rate_formulas_found += 1
                logger.info(f"{player} win rate formula: {stats['win_rate_formula']}")
        
        if win_rate_formulas_found >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Win rate formulas present ({win_rate_formulas_found} players)")
        else:
            # Check if win rates exist as values (even without formulas)
            win_rate_values_found = sum(1 for stats in stats_section['players'].values() 
                                       if stats.get('win_rate') is not None)
            if win_rate_values_found >= 3:
                criteria_passed += 0.5
                feedback_parts.append(f"⚠️ Win rates calculated but formulas not clearly detected")
            else:
                feedback_parts.append("❌ Win rate calculations missing or incomplete")
        
        # Criterion 4: Mathematical accuracy
        accuracy_errors = []
        accurate_players = 0
        
        for player, stats in stats_section['players'].items():
            if player in actual_wins:
                reported_wins = stats.get('wins')
                actual_win_count = actual_wins[player]
                
                if reported_wins is not None:
                    if abs(float(reported_wins) - float(actual_win_count)) <= 0.5:
                        accurate_players += 1
                    else:
                        accuracy_errors.append(
                            f"{player}: expected {actual_win_count} wins, got {reported_wins}"
                        )
                
                # Check win rate calculation if available
                if stats.get('wins') and stats.get('games') and stats.get('win_rate'):
                    expected_rate = (float(stats['wins']) / float(stats['games'])) * 100
                    actual_rate = float(stats['win_rate'])
                    
                    # Allow for percentage vs decimal representation
                    if abs(actual_rate - expected_rate) > 1.0:
                        # Check if it's decimal representation (0.xx instead of xx)
                        if abs(actual_rate * 100 - expected_rate) > 1.0:
                            accuracy_errors.append(
                                f"{player}: win rate calculation may be incorrect"
                            )
        
        if accurate_players >= 3 and len(accuracy_errors) == 0:
            criteria_passed += 1
            feedback_parts.append(f"✅ Mathematical accuracy verified ({accurate_players} players correct)")
        elif accurate_players >= 2:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Partial accuracy ({accurate_players} players correct)")
            if accuracy_errors:
                logger.warning(f"Accuracy errors: {accuracy_errors}")
        else:
            feedback_parts.append("❌ Mathematical accuracy issues detected")
            if accuracy_errors:
                feedback_parts.append(f"Errors: {'; '.join(accuracy_errors[:2])}")
        
        # Criterion 5: Top player identifiable
        # Check if we can identify who has the highest win rate
        if len(stats_section['players']) >= 3:
            player_rates = {}
            for player, stats in stats_section['players'].items():
                if stats.get('win_rate') is not None:
                    player_rates[player] = float(stats['win_rate'])
            
            if len(player_rates) >= 3:
                criteria_passed += 1
                top_player = max(player_rates, key=player_rates.get)
                feedback_parts.append(f"✅ Top player identifiable (highest: {top_player})")
            else:
                feedback_parts.append("❌ Cannot determine top player (insufficient win rate data)")
        else:
            feedback_parts.append("❌ Insufficient player data to identify top performer")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent statistical analysis!")
        elif passed:
            feedback_parts.insert(0, "✅ Task completed successfully")
        else:
            feedback_parts.insert(0, "❌ Task requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "stats_section_exists": len(found_players) >= 4,
                "formulas_used": has_formulas,
                "win_rates_calculated": win_rate_formulas_found >= 3,
                "mathematically_accurate": accurate_players >= 3,
                "top_player_identifiable": len(stats_section['players']) >= 3
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
