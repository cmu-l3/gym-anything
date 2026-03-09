#!/usr/bin/env python3
"""
Verifier for import_portfolio_from_csv task.

Checks:
1. File Verification: Checks ~/.jstock/.../buyportfolio.csv for expected tickers and units.
2. Anti-Gaming: Ensures the portfolio file was actually modified during the task.
3. VLM Verification: Uses visual history to confirm UI interaction (navigating to Portfolio, File Dialog).
"""

import json
import os
import tempfile
import logging
import csv
import io
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_portfolio_from_csv(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_positions = metadata.get('expected_positions', [])
    
    # Helper to clean unit strings (e.g., "30.0" -> 30.0)
    def parse_units(u_str):
        try:
            return float(u_str.replace('"', '').strip())
        except ValueError:
            return 0.0

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load result JSON from container
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

    # 2. Check File Modification (Anti-gaming) - 10 points
    if result.get('portfolio_modified', False):
        score += 10
        feedback_parts.append("Portfolio file modified correctly.")
    else:
        feedback_parts.append("Portfolio file was NOT modified.")

    # 3. Check Portfolio Content - 60 points (12 points per correct stock)
    content_str = result.get('portfolio_content_str', "")
    found_positions = {}
    
    if content_str:
        try:
            # Parse CSV string
            f = io.StringIO(content_str)
            reader = csv.reader(f)
            # Find the header row if possible, otherwise assume standard layout
            # Standard JStock layout: Code, Symbol, Date, Units, ...
            for row in reader:
                if len(row) > 3:
                    # Check if this is a data row (has a ticker code)
                    # Skip header "Code"
                    code = row[0].strip().replace('"', '')
                    if code and code != "Code" and code != "timestamp=0":
                        units = parse_units(row[3]) # Index 3 is Units in standard JStock export
                        found_positions[code] = units
        except Exception as e:
            feedback_parts.append(f"Error parsing portfolio CSV: {e}")

    # Verify expected stocks
    stocks_found_count = 0
    for expected in expected_positions:
        exp_code = expected['code']
        exp_units = expected['units']
        
        if exp_code in found_positions:
            actual_units = found_positions[exp_code]
            # Allow small float tolerance
            if abs(actual_units - exp_units) < 0.1:
                score += 12
                stocks_found_count += 1
                feedback_parts.append(f"Found {exp_code} ({exp_units}).")
            else:
                # Partial credit for correct stock but wrong units
                score += 6
                feedback_parts.append(f"{exp_code} found but wrong units (Exp: {exp_units}, Got: {actual_units}).")
        else:
            feedback_parts.append(f"Missing {exp_code}.")

    # 4. VLM Verification - 30 points
    # We want to see:
    # - Navigation to Portfolio tab
    # - Interaction with File Dialog or Import Menu
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of a stock market application task. "
        "The user was asked to import a portfolio CSV file. "
        "1. Do you see the user switch to the 'Portfolio' or 'Portfolio Management' tab? "
        "2. Do you see a file selection dialog or an 'Import' menu interaction? "
        "3. In the final image, does the table show multiple stock entries like TSLA, META, JPM? "
        "Answer 'Yes' or 'No' for each."
    )
    
    try:
        vlm_response = query_vlm(images=frames + [final_screen], prompt=vlm_prompt).lower()
        
        if "portfolio" in vlm_response or "tab" in vlm_response:
            score += 10
            feedback_parts.append("VLM confirmed UI navigation.")
        
        if "dialog" in vlm_response or "file" in vlm_response or "import" in vlm_response:
            score += 10
            feedback_parts.append("VLM confirmed import interaction.")
            
        if "tsla" in vlm_response or "meta" in vlm_response or "multiple stock" in vlm_response or "table" in vlm_response:
            score += 10
            feedback_parts.append("VLM confirmed visual result.")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if programmatic check passed perfectly, assume visual is fine
        if stocks_found_count == len(expected_positions):
            score += 30
            feedback_parts.append("VLM skipped, trusted programmatic success.")

    # 5. Final Decision
    # Must have modified file AND found at least 3 stocks
    passed = (result.get('portfolio_modified', False) and stocks_found_count >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }