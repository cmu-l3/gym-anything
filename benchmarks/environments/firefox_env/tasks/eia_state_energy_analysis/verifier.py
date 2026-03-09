#!/usr/bin/env python3
"""
Verifier for EIA State Energy Analysis Task.

Scoring Breakdown (100 points total):
1. Browser State (40 points):
   - "Grid Analysis" bookmark folder exists (10 pts)
   - Contains >= 3 EIA bookmarks (10 pts)
   - History shows visits to TX, CA, and WV state pages (20 pts)
   
2. JSON Output File (60 points):
   - File exists and is valid JSON (15 pts)
   - Structure contains Texas, California, West_Virginia keys (5 pts)
   - Data Logic (40 pts):
     - Production values roughly correct (TX >> CA)
     - Price logic correct (CA > TX/WV)
     - Rank logic correct (TX #1)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_eia_state_energy_analysis(traj, env_info, task_info):
    """Verify EIA task completion using exported browser state and user file."""
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Retrieve Task Result (Browser State)
    browser_state = {}
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            browser_state = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read browser state: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}

    # 2. Retrieve User Output File
    user_data = {}
    user_file_valid = False
    try:
        if browser_state.get("file_exists") and browser_state.get("file_fresh"):
            temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            # The output file path in the container
            copy_from_env("/home/ga/Documents/energy_comparison.json", temp_output.name)
            with open(temp_output.name, 'r') as f:
                user_data = json.load(f)
            user_file_valid = True
            os.unlink(temp_output.name)
    except Exception as e:
        logger.warning(f"Failed to read user output file: {e}")
        # Not fatal, just scores 0 for file section

    # --- SCORING ---
    score = 0
    feedback = []

    # SECTION 1: Browser State (40 pts)
    
    # Bookmarks
    if browser_state.get("grid_folder_exists"):
        score += 10
        feedback.append("Bookmark folder 'Grid Analysis' found (+10)")
        
        bm_count = browser_state.get("bookmark_count", 0)
        if bm_count >= 3:
            score += 10
            feedback.append(f"Found {bm_count} EIA bookmarks in folder (+10)")
        elif bm_count > 0:
            score += 5
            feedback.append(f"Found {bm_count} EIA bookmarks (needs 3) (+5)")
        else:
            feedback.append("No EIA bookmarks found in 'Grid Analysis' folder (+0)")
    else:
        feedback.append("Bookmark folder 'Grid Analysis' NOT found (+0)")

    # History
    visited_tx = browser_state.get("visited_tx", False)
    visited_ca = browser_state.get("visited_ca", False)
    visited_wv = browser_state.get("visited_wv", False)
    
    states_visited = sum([visited_tx, visited_ca, visited_wv])
    if states_visited == 3:
        score += 20
        feedback.append("History shows visits to all 3 target states (+20)")
    else:
        pts = states_visited * 5
        score += pts
        feedback.append(f"History shows visits to {states_visited}/3 target states (+{pts})")

    # SECTION 2: JSON Output (60 pts)

    if user_file_valid:
        score += 15
        feedback.append("Output JSON exists and is valid (+15)")
        
        # Normalize keys (case-insensitive)
        data_norm = {k.lower(): v for k, v in user_data.items()}
        
        # Check keys
        if all(k in data_norm for k in ["texas", "california", "west_virginia"]):
            score += 5
            feedback.append("JSON contains all required state keys (+5)")
            
            # Logic Checks (40 pts total)
            
            # Helper to safely get numbers
            def get_val(state, key):
                try:
                    return float(data_norm[state].get(key, 0))
                except (ValueError, TypeError):
                    return 0

            # 1. Production Logic (15 pts)
            # TX is massive (usually > 20,000 trillion Btu). CA/WV are much smaller.
            tx_prod = get_val("texas", "total_production_trillion_btu")
            ca_prod = get_val("california", "total_production_trillion_btu")
            wv_prod = get_val("west_virginia", "total_production_trillion_btu")
            
            if tx_prod > 15000 and tx_prod > ca_prod and tx_prod > wv_prod:
                score += 15
                feedback.append(f"Production data logical (TX {tx_prod} >> CA/WV) (+15)")
            else:
                feedback.append(f"Production data suspect (TX: {tx_prod}, CA: {ca_prod}) (+0)")

            # 2. Price Logic (15 pts)
            # CA is expensive (>20 cents), TX/WV cheaper (<20 cents usually)
            tx_price = get_val("texas", "residential_price_cents")
            ca_price = get_val("california", "residential_price_cents")
            wv_price = get_val("west_virginia", "residential_price_cents")
            
            if ca_price > 20 and ca_price > tx_price:
                score += 15
                feedback.append(f"Price data logical (CA {ca_price} > TX {tx_price}) (+15)")
            else:
                feedback.append(f"Price data suspect (CA: {ca_price}, TX: {tx_price}) (+0)")

            # 3. Rank Logic (10 pts)
            # TX is #1 usually.
            tx_rank = get_val("texas", "generation_rank")
            
            if 0 < tx_rank <= 2:
                score += 10
                feedback.append(f"Rank data logical (TX Rank: {tx_rank}) (+10)")
            else:
                feedback.append(f"Rank data suspect (TX Rank: {tx_rank}) (+0)")

        else:
            feedback.append("JSON missing one or more required state keys (Texas, California, West_Virginia)")
    else:
        feedback.append("Output JSON not found or invalid (+0)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }