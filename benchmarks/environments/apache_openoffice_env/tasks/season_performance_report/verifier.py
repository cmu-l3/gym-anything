#!/usr/bin/env python3
"""
Verifier for season_performance_report task.
Verifies ODT document structure, content, and formatting features.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_season_performance_report(traj, env_info, task_info):
    """
    Verify the mid-season baseball report task.
    
    Scoring Criteria (100 pts total):
    1. File Existence & Size (5 pts) - Gatekeeper
    2. Table of Contents (20 pts)
    3. Document Structure (Headings) (20 pts)
    4. Data Tables (20 pts)
    5. Content Accuracy (Players/Stats) (20 pts)
    6. Page Numbers (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence (Gatekeeper)
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Output file 'ValleyCats_MidSeason_2024.odt' not found."
        }
    
    file_size = result.get("file_size", 0)
    if file_size < 5000: # < 5KB is likely empty or just a title
        return {
            "passed": False,
            "score": 0,
            "feedback": f"FAIL: File exists but is too small ({file_size} bytes). Expected substantial content."
        }
    
    score += 5
    feedback.append("File exists and has content (5/5)")

    # 2. Table of Contents
    if result.get("has_toc", False):
        score += 20
        feedback.append("Table of Contents found (20/20)")
    else:
        feedback.append("Table of Contents missing (0/20)")

    # 3. Structure (Headings)
    h1 = result.get("heading1_count", 0)
    h2 = result.get("heading2_count", 0)
    
    # Criteria: At least 5 H1 and 6 H2
    h1_score = min(10, h1 * 2) # Cap at 10
    h2_score = min(10, h2 * 2) # Cap at 10 -- strict: needs ~5 to get full points
    
    if h1 >= 5: h1_score = 10
    if h2 >= 6: h2_score = 10
    
    structure_score = h1_score + h2_score
    score += structure_score
    feedback.append(f"Structure: {h1} Heading 1s, {h2} Heading 2s ({structure_score}/20)")

    # 4. Data Tables
    # Criteria: At least 2 tables (Batting + Pitching)
    table_count = result.get("table_count", 0)
    if table_count >= 2:
        score += 20
        feedback.append(f"Tables found: {table_count} (20/20)")
    elif table_count == 1:
        score += 10
        feedback.append("Only 1 table found (10/20)")
    else:
        feedback.append("No data tables found (0/20)")

    # 5. Content Accuracy
    # Check for player names and specific stats in the text
    found_players = result.get("player_names_found", [])
    found_stats = result.get("stat_values_found", [])
    
    # Need at least 3 players mentioned and 2 stats
    player_pts = min(10, len(found_players) * 3.4) # 3 players gets ~10 pts
    if len(found_players) >= 3: player_pts = 10
    
    stat_pts = min(10, len(found_stats) * 5) # 2 stats gets 10 pts
    
    content_score = int(player_pts + stat_pts)
    score += content_score
    feedback.append(f"Content: {len(found_players)} players, {len(found_stats)} stats found ({content_score}/20)")

    # 6. Page Numbers
    if result.get("has_page_numbers", False):
        score += 15
        feedback.append("Page numbers found (15/15)")
    else:
        feedback.append("Page numbers missing (0/15)")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }