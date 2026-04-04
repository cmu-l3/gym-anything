#!/usr/bin/env python3
"""
Verifier for organize_watchlists_by_sector task.
Verifies that the agent correctly created new watchlists and redistributed stocks.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_watchlists(traj, env_info, task_info):
    """
    Verify the watchlist organization task.
    
    Expected Final State:
    - "Semiconductors": Contains [NVDA]
    - "Software & Cloud": Contains [MSFT, GOOGL]
    - "My Watchlist": Contains [AAPL, AMZN] (Originals removed)
    
    Anti-gaming:
    - Files must be modified/created after task start.
    - Stocks should not be duplicated across lists.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    watchlists = result.get('watchlists', {})
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Create "Semiconductors" Watchlist (10 pts) ---
    semicon_data = watchlists.get('Semiconductors', {})
    if semicon_data.get('exists') and semicon_data.get('modified_during_task'):
        score += 10
        feedback_parts.append("Created 'Semiconductors' watchlist.")
    else:
        feedback_parts.append("'Semiconductors' watchlist not created or not saved.")

    # --- Criterion 2: Create "Software & Cloud" Watchlist (10 pts) ---
    soft_data = watchlists.get('Software & Cloud', {})
    if soft_data.get('exists') and soft_data.get('modified_during_task'):
        score += 10
        feedback_parts.append("Created 'Software & Cloud' watchlist.")
    else:
        feedback_parts.append("'Software & Cloud' watchlist not created or not saved.")

    # Get stock lists for content verification
    # Normalize to set for easier comparison
    semicon_stocks = set(semicon_data.get('stocks', []))
    soft_stocks = set(soft_data.get('stocks', []))
    my_stocks = set(watchlists.get('My Watchlist', {}).get('stocks', []))

    # --- Criterion 3: Correct content in "Semiconductors" (15 pts) ---
    if 'NVDA' in semicon_stocks:
        score += 15
        feedback_parts.append("NVDA correctly moved to Semiconductors.")
    else:
        feedback_parts.append("NVDA missing from Semiconductors.")

    # --- Criterion 4: Correct content in "Software & Cloud" (30 pts) ---
    soft_points = 0
    if 'MSFT' in soft_stocks:
        soft_points += 15
    if 'GOOGL' in soft_stocks:
        soft_points += 15
    score += soft_points
    if soft_points == 30:
        feedback_parts.append("MSFT and GOOGL correctly moved to Software & Cloud.")
    elif soft_points > 0:
        feedback_parts.append("Partial success moving stocks to Software & Cloud.")
    else:
        feedback_parts.append("MSFT and GOOGL missing from Software & Cloud.")

    # --- Criterion 5: Cleanup "My Watchlist" (20 pts) ---
    # Should NOT contain moved stocks
    cleanup_points = 0
    forbidden = {'NVDA', 'MSFT', 'GOOGL'}
    remaining_forbidden = my_stocks.intersection(forbidden)
    
    if not remaining_forbidden:
        cleanup_points += 10
        feedback_parts.append("Moved stocks correctly removed from My Watchlist.")
    else:
        feedback_parts.append(f"My Watchlist still contains: {', '.join(remaining_forbidden)}.")

    # Should KEEP original stocks
    required_kept = {'AAPL', 'AMZN'}
    missing_kept = required_kept - my_stocks
    
    if not missing_kept:
        cleanup_points += 10
        feedback_parts.append("AAPL and AMZN correctly retained in My Watchlist.")
    else:
        feedback_parts.append(f"Accidentally removed: {', '.join(missing_kept)} from My Watchlist.")
    
    score += cleanup_points

    # --- Criterion 6: No Duplicates (10 pts) ---
    # Check intersection between all pairs
    all_sets = [semicon_stocks, soft_stocks, my_stocks]
    has_dupes = False
    
    if semicon_stocks.intersection(soft_stocks): has_dupes = True
    if semicon_stocks.intersection(my_stocks): has_dupes = True
    if soft_stocks.intersection(my_stocks): has_dupes = True
    
    if not has_dupes and score > 20: # Only award if some lists actually exist
        score += 10
        feedback_parts.append("No duplicate stocks across watchlists.")
    elif has_dupes:
        feedback_parts.append("Found duplicate stocks across watchlists.")

    # --- Criterion 7: App Running (5 pts) ---
    if result.get('app_running', False):
        score += 5
        feedback_parts.append("JStock left running.")

    # Final result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }