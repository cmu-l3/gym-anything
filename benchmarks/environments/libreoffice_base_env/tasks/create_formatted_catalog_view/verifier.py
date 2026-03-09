#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_formatted_catalog_view(traj, env_info, task_info):
    """
    Verifies that the agent created the 'FormattedTrackList' view with correct logic.
    
    Strategy:
    1. Parse the extracted HSQLDB script file for the CREATE VIEW statement.
    2. Check for required columns and formatting logic (division, concatenation).
    3. Use VLM to confirm the agent actually interacted with the UI if script parsing is ambiguous.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback_parts = []
    
    # --- Step 1: Load Result JSON ---
    result_json_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)

    # --- Step 2: Check ODB Modification ---
    if not result_data.get("odb_exists", False):
        return {"passed": False, "score": 0, "feedback": "Database file not found."}
        
    if result_data.get("odb_modified", False):
        score += 10
        feedback_parts.append("Database file saved.")
    else:
        feedback_parts.append("Database file NOT saved (timestamps unchanged).")

    # --- Step 3: Analyze SQL Script ---
    script_path = tempfile.mktemp(suffix=".sql")
    view_found = False
    logic_score = 0
    
    if result_data.get("script_extracted", False):
        try:
            copy_from_env("/tmp/database_script.sql", script_path)
            with open(script_path, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()
                
            # Search for CREATE VIEW statement
            # HSQLDB 1.8 syntax: CREATE SCHEMA PUBLIC ... CREATE VIEW "FormattedTrackList" AS SELECT ...
            # Regex to capture the view definition. Case insensitive for SQL keywords, specific for name.
            # We look for the view name quoted or unquoted.
            view_regex = re.compile(r'CREATE\s+VIEW\s+(?:PUBLIC\.)?"?FormattedTrackList"?\s+AS\s+(.*)', re.IGNORECASE)
            match = view_regex.search(script_content)
            
            if match:
                view_found = True
                view_def = match.group(1)
                score += 30
                feedback_parts.append("View 'FormattedTrackList' found in database schema.")
                
                # Analyze Columns logic
                # We expect to see 'Artist', 'Album', 'Track' (or Name), and 'Duration' aliases or columns
                lower_def = view_def.lower()
                
                required_cols = ["artist", "album", "duration"]
                cols_found = sum(1 for c in required_cols if c in lower_def)
                if cols_found == 3:
                    score += 10
                    feedback_parts.append("Required columns identified.")
                
                # Analyze Formatting Logic
                # Looking for:
                # 1. Division by 60000 (minutes)
                # 2. Modulo or Division by 1000 (seconds)
                # 3. Concatenation (||) or CONCAT
                # 4. Zero padding logic (CASE WHEN ... < 10 ... '0' ...)
                
                logic_checks = {
                    "minutes_calc": ["60000", "/60000", "/ 60000"],
                    "seconds_calc": ["1000", "/1000", "/ 1000"],
                    "concat": ["||", "concat"],
                    "colon": ["':'", "':'"],
                    "padding": ["case when", "if"] 
                }
                
                logic_hits = 0
                for check_name, patterns in logic_checks.items():
                    if any(p in lower_def for p in patterns):
                        logic_hits += 1
                
                if logic_hits >= 3:
                    score += 30
                    logic_score = 30
                    feedback_parts.append("Duration formatting logic appears correct.")
                elif logic_hits > 0:
                    score += 10
                    logic_score = 10
                    feedback_parts.append("Some formatting logic found, but incomplete.")
                else:
                    feedback_parts.append("Formatting logic missing or unrecognizable.")

            else:
                feedback_parts.append("View 'FormattedTrackList' NOT found in database script.")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing database script: {e}")
    else:
        feedback_parts.append("Could not extract database script from ODB file.")
    
    if os.path.exists(script_path):
        os.remove(script_path)

    # --- Step 4: VLM Verification (Trajectory) ---
    # Used to verify intent and workflow if script parsing was partial or to confirm UI interaction
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    if frames:
        images_to_check = frames
        if final_screenshot:
            images_to_check.append(final_screenshot)
            
        prompt = """
        Review this sequence of screenshots from LibreOffice Base.
        The user is supposed to:
        1. Open the SQL View or Query Design.
        2. Create a View named 'FormattedTrackList'.
        3. Enter SQL logic to format milliseconds into MM:SS (e.g., using 60000, ||, CASE statements).
        4. Save the view.

        Do you see evidence of:
        - The SQL editor window?
        - Code involving 'milliseconds', '60000', or concatenation '||'?
        - A saved view named 'FormattedTrackList' in the list?

        Return valid JSON:
        {
            "sql_editor_visible": true/false,
            "formatting_logic_visible": true/false,
            "view_saved": true/false
        }
        """
        
        vlm_res = query_vlm(images=images_to_check, prompt=prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            vlm_score = 0
            if parsed.get("sql_editor_visible"): vlm_score += 5
            if parsed.get("formatting_logic_visible"): vlm_score += 10
            if parsed.get("view_saved"): vlm_score += 5
            
            score += vlm_score
            feedback_parts.append(f"VLM verification added {vlm_score} points.")
            
            # Boost score if VLM confirms saving but script parsing failed (e.g. flush issue)
            if parsed.get("view_saved") and not view_found and result_data.get("odb_modified"):
                score += 20
                feedback_parts.append("VLM confirms view visible in UI (granting partial credit despite script miss).")

    # --- Final Scoring ---
    # Pass threshold: View found in script (approx 50 pts) + Logic correct (30 pts) = 80 pts
    # Or strict VLM confirmation.
    
    passed = score >= 75 and view_found and logic_score >= 10
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }