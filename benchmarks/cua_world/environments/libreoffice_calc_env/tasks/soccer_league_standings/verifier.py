#!/usr/bin/env python3
"""
Verifier for Soccer League Standings task.
Checks standings calculation, sorting, and ranking logic.
"""

import sys
import os
import logging
from typing import Dict, List, Tuple, Any

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_verification_environment,
    cleanup_verification_environment,
    get_cell_value,
    parse_ods_file
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_teams_from_matches(match_sheet_data: List[List[Dict]]) -> set:
    """Extract unique team names from match results."""
    teams = set()
    # Skip header row
    for row in match_sheet_data[1:]:
        if len(row) >= 5:
            home_team = row[1].get('value') if isinstance(row[1], dict) else row[1]
            away_team = row[4].get('value') if isinstance(row[4], dict) else row[4]
            if home_team and isinstance(home_team, str) and home_team.strip():
                teams.add(home_team.strip())
            if away_team and isinstance(away_team, str) and away_team.strip():
                teams.add(away_team.strip())
    return teams


def calculate_expected_stats(match_sheet_data: List[List[Dict]]) -> Dict[str, Dict[str, int]]:
    """
    Calculate expected statistics for each team from match results.
    Returns dict: {team_name: {W, D, L, GF, GA, GD, Pts}}
    """
    stats = {}
    
    # Initialize stats for all teams
    teams = extract_teams_from_matches(match_sheet_data)
    for team in teams:
        stats[team] = {
            'W': 0, 'D': 0, 'L': 0,
            'GF': 0, 'GA': 0, 'GD': 0, 'Pts': 0, 'P': 0
        }
    
    # Process each match (skip header)
    for row in match_sheet_data[1:]:
        if len(row) < 5:
            continue
        
        home_team = row[1].get('value') if isinstance(row[1], dict) else row[1]
        home_goals = row[2].get('value') if isinstance(row[2], dict) else row[2]
        away_goals = row[3].get('value') if isinstance(row[3], dict) else row[3]
        away_team = row[4].get('value') if isinstance(row[4], dict) else row[4]
        
        # Skip empty rows
        if not home_team or not away_team:
            continue
            
        home_team = str(home_team).strip()
        away_team = str(away_team).strip()
        
        try:
            home_goals = int(float(home_goals)) if home_goals else 0
            away_goals = int(float(away_goals)) if away_goals else 0
        except (ValueError, TypeError):
            continue
        
        if home_team not in stats or away_team not in stats:
            continue
        
        # Update matches played
        stats[home_team]['P'] += 1
        stats[away_team]['P'] += 1
        
        # Update goals
        stats[home_team]['GF'] += home_goals
        stats[home_team]['GA'] += away_goals
        stats[away_team]['GF'] += away_goals
        stats[away_team]['GA'] += home_goals
        
        # Update results
        if home_goals > away_goals:
            stats[home_team]['W'] += 1
            stats[away_team]['L'] += 1
        elif home_goals < away_goals:
            stats[away_team]['W'] += 1
            stats[home_team]['L'] += 1
        else:
            stats[home_team]['D'] += 1
            stats[away_team]['D'] += 1
    
    # Calculate GD and Points
    for team in stats:
        stats[team]['GD'] = stats[team]['GF'] - stats[team]['GA']
        stats[team]['Pts'] = stats[team]['W'] * 3 + stats[team]['D'] * 1
    
    return stats


def parse_standings_table(standings_sheet_data: List[List[Dict]]) -> List[Dict[str, Any]]:
    """
    Parse standings table from sheet data.
    Returns list of dicts with team standings.
    """
    standings = []
    
    # Skip header row, process data rows
    for i, row in enumerate(standings_sheet_data[1:], start=2):
        if len(row) < 10:
            continue
        
        # Extract team name (column B, index 1)
        team_name = row[1].get('value') if isinstance(row[1], dict) else row[1]
        if not team_name or not isinstance(team_name, str) or not team_name.strip():
            continue
        
        team_name = str(team_name).strip()
        
        # Extract statistics
        def get_numeric_value(cell, default=0):
            if isinstance(cell, dict):
                val = cell.get('value')
            else:
                val = cell
            try:
                return int(float(val)) if val is not None else default
            except (ValueError, TypeError):
                return default
        
        position = get_numeric_value(row[0], None)  # Column A
        played = get_numeric_value(row[2])      # Column C
        wins = get_numeric_value(row[3])        # Column D
        draws = get_numeric_value(row[4])       # Column E
        losses = get_numeric_value(row[5])      # Column F
        gf = get_numeric_value(row[6])          # Column G
        ga = get_numeric_value(row[7])          # Column H
        gd = get_numeric_value(row[8])          # Column I
        pts = get_numeric_value(row[9])         # Column J
        
        standings.append({
            'row': i,
            'position': position,
            'team': team_name,
            'P': played,
            'W': wins,
            'D': draws,
            'L': losses,
            'GF': gf,
            'GA': ga,
            'GD': gd,
            'Pts': pts
        })
    
    return standings


def verify_all_teams_present(standings: List[Dict], expected_teams: set) -> Tuple[bool, str]:
    """Check that all teams are present exactly once."""
    standings_teams = [s['team'] for s in standings]
    standings_set = set(standings_teams)
    
    # Check for missing teams
    missing = expected_teams - standings_set
    if missing:
        return False, f"Missing teams: {', '.join(missing)}"
    
    # Check for duplicates
    if len(standings_teams) != len(standings_set):
        duplicates = [t for t in standings_set if standings_teams.count(t) > 1]
        return False, f"Duplicate teams: {', '.join(duplicates)}"
    
    # Check for extra teams
    extra = standings_set - expected_teams
    if extra:
        return False, f"Extra teams not in matches: {', '.join(extra)}"
    
    return True, ""


def verify_points_calculation(standings: List[Dict]) -> Tuple[bool, List[str]]:
    """Verify that points = wins*3 + draws*1 for all teams."""
    errors = []
    for team_data in standings:
        expected_pts = team_data['W'] * 3 + team_data['D'] * 1
        actual_pts = team_data['Pts']
        if expected_pts != actual_pts:
            errors.append(f"{team_data['team']}: expected {expected_pts} pts, got {actual_pts}")
    
    return len(errors) == 0, errors


def verify_goal_difference(standings: List[Dict]) -> Tuple[bool, List[str]]:
    """Verify that GD = GF - GA for all teams."""
    errors = []
    for team_data in standings:
        expected_gd = team_data['GF'] - team_data['GA']
        actual_gd = team_data['GD']
        if expected_gd != actual_gd:
            errors.append(f"{team_data['team']}: expected GD={expected_gd}, got {actual_gd}")
    
    return len(errors) == 0, errors


def verify_primary_sort(standings: List[Dict]) -> Tuple[bool, str]:
    """Verify teams are sorted by points (descending)."""
    for i in range(len(standings) - 1):
        current_pts = standings[i]['Pts']
        next_pts = standings[i + 1]['Pts']
        if current_pts < next_pts:
            return False, f"Sort error: {standings[i]['team']} ({current_pts} pts) ranked above {standings[i+1]['team']} ({next_pts} pts)"
    return True, ""


def verify_tiebreaker_sort(standings: List[Dict]) -> Tuple[bool, str]:
    """Verify that teams tied on points are sorted by GD (descending)."""
    for i in range(len(standings) - 1):
        current = standings[i]
        next_team = standings[i + 1]
        
        # If points are equal, check GD tiebreaker
        if current['Pts'] == next_team['Pts']:
            if current['GD'] < next_team['GD']:
                return False, f"Tiebreaker error: {current['team']} (GD={current['GD']}) ranked above {next_team['team']} (GD={next_team['GD']}) despite equal points ({current['Pts']})"
    
    return True, ""


def verify_position_column(standings: List[Dict]) -> Tuple[bool, str]:
    """Verify position column is numbered 1, 2, 3, ... N."""
    for i, team_data in enumerate(standings, start=1):
        if team_data['position'] != i:
            return False, f"Position error: {team_data['team']} has position {team_data['position']}, expected {i}"
    return True, ""


def verify_soccer_standings(traj, env_info, task_info):
    """
    Main verification function for soccer league standings task.
    
    Checks:
    1. All teams present (no duplicates, all included)
    2. Points calculation correct (W*3 + D*1)
    3. Goal difference correct (GF - GA)
    4. Primary sort (by points descending)
    5. Tiebreaker sort (by GD when points equal)
    6. Position column (1, 2, 3, ...)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Setup verification environment
    container_path = "/home/ga/Documents/league_standings.ods"
    success, result = setup_verification_environment(
        copy_from_env,
        container_path,
        expected_formats=['ods', 'xlsx']
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet: {result.get('error', 'Unknown error')}"
        }
    
    data = result['data']
    temp_dir = result['temp_dir']
    
    try:
        # Get sheets
        sheets = data.get('sheets', {})
        
        # Find match results sheet
        match_sheet_name = None
        for name in ['Match Results', 'Matches', 'Match_Results', 'Sheet1']:
            if name in sheets:
                match_sheet_name = name
                break
        
        if not match_sheet_name:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not find 'Match Results' sheet"
            }
        
        # Find standings sheet
        standings_sheet_name = None
        for name in ['Standings', 'League Table', 'Table', 'Sheet2']:
            if name in sheets:
                standings_sheet_name = name
                break
        
        if not standings_sheet_name:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not find 'Standings' sheet"
            }
        
        # Extract data
        match_sheet_data = sheets[match_sheet_name]
        standings_sheet_data = sheets[standings_sheet_name]
        
        # Get expected teams from matches
        expected_teams = extract_teams_from_matches(match_sheet_data)
        if not expected_teams:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No teams found in match results"
            }
        
        # Parse standings table
        standings = parse_standings_table(standings_sheet_data)
        if not standings:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No data found in standings table"
            }
        
        # Verification checks
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: All teams present
        teams_ok, teams_error = verify_all_teams_present(standings, expected_teams)
        if teams_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ All {len(expected_teams)} teams included")
        else:
            feedback_parts.append(f"❌ Team list issue: {teams_error}")
        
        # Criterion 2: Points calculation
        points_ok, points_errors = verify_points_calculation(standings)
        if points_ok:
            criteria_passed += 1
            feedback_parts.append("✅ Points calculated correctly (W*3 + D*1)")
        else:
            feedback_parts.append(f"❌ Points calculation errors: {points_errors[0]}")
        
        # Criterion 3: Goal difference
        gd_ok, gd_errors = verify_goal_difference(standings)
        if gd_ok:
            criteria_passed += 1
            feedback_parts.append("✅ Goal difference correct (GF - GA)")
        else:
            feedback_parts.append(f"❌ Goal difference errors: {gd_errors[0]}")
        
        # Criterion 4: Primary sort
        sort_ok, sort_error = verify_primary_sort(standings)
        if sort_ok:
            criteria_passed += 1
            feedback_parts.append("✅ Teams sorted by points (descending)")
        else:
            feedback_parts.append(f"❌ {sort_error}")
        
        # Criterion 5: Tiebreaker sort
        tiebreak_ok, tiebreak_error = verify_tiebreaker_sort(standings)
        if tiebreak_ok:
            criteria_passed += 1
            feedback_parts.append("✅ Tiebreakers resolved by goal difference")
        else:
            feedback_parts.append(f"❌ {tiebreak_error}")
        
        # Criterion 6: Position column
        position_ok, position_error = verify_position_column(standings)
        if position_ok:
            criteria_passed += 1
            feedback_parts.append("✅ Position column numbered correctly")
        else:
            feedback_parts.append(f"❌ {position_error}")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Need 4/6 criteria (70%)
        
        # Add champion info if standings are good
        if criteria_passed >= 4 and standings:
            champion = standings[0]['team']
            champion_pts = standings[0]['Pts']
            feedback_parts.append(f"🏆 Champion: {champion} ({champion_pts} pts)")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "all_teams_present": teams_ok,
                "points_correct": points_ok,
                "goal_difference_correct": gd_ok,
                "primary_sort_valid": sort_ok,
                "tiebreaker_sort_valid": tiebreak_ok,
                "position_column_accurate": position_ok
            },
            "criteria_passed": criteria_passed,
            "criteria_total": total_criteria
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        cleanup_verification_environment(temp_dir)
