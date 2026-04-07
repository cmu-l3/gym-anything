#!/usr/bin/env python3
"""
Verifier for dispatch_nearest_hub task.

Goal: Verify the agent identified "Panama City" as the nearest hub to (9.0, -79.5)
and updated its notes to "DISPATCHING TO PANAMA".
"""

import json
import sqlite3
import os
import math
import tempfile
import logging
from vlm_utils import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance in km between two lat/lon points."""
    R = 6371  # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2) * math.sin(dlat/2) + \
        math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * \
        math.sin(dlon/2) * math.sin(dlon/2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def verify_dispatch_hub(traj, env_info, task_info):
    """
    Verify the dispatch task using DB analysis and VLM trajectory check.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Task constants
    TARGET_LAT = 9.0
    TARGET_LON = -79.5
    CORRECT_CITY = "Panama City"
    EXPECTED_NOTE = "DISPATCHING TO PANAMA"
    
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. FILE RETRIEVAL & INTEGRITY
    # =========================================================
    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg')
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Retrieve the JSON result (for timestamps)
        try:
            copy_from_env("/sdcard/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result_meta = json.load(f)
        except Exception as e:
            logger.warning(f"Could not read task_result.json: {e}")
            result_meta = {}

        # Retrieve the GeoPackage (PRIMARY EVIDENCE)
        try:
            copy_from_env("/sdcard/output_world_survey.gpkg", temp_gpkg.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve GeoPackage file."}

        # Check Timestamps (Anti-Gaming)
        # Note: file_mod_time comes from Android (Linux epoch), start_time from setup script
        start_time = int(result_meta.get('start_time', 0))
        mod_time = int(result_meta.get('file_mod_time', 0))
        
        # We allow a small buffer or ignore if start_time is missing (robustness)
        if start_time > 0 and mod_time > start_time:
            score += 10
            feedback_parts.append("File modified during task.")
        elif start_time > 0:
            feedback_parts.append("WARNING: File not modified after start time.")
        
        # =========================================================
        # 2. DATABASE ANALYSIS
        # =========================================================
        conn = sqlite3.connect(temp_gpkg.name)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        # Check if Panama City was updated
        cursor.execute("SELECT name, notes FROM world_capitals WHERE name = ?", (CORRECT_CITY,))
        row = cursor.fetchone()
        
        updated_correctly = False
        if row:
            actual_note = (row['notes'] or "").strip()
            if EXPECTED_NOTE.lower() in actual_note.lower():
                score += 50
                updated_correctly = True
                feedback_parts.append(f"Correctly updated {CORRECT_CITY}.")
                # Exact match bonus
                if actual_note == EXPECTED_NOTE:
                    score += 10
            else:
                feedback_parts.append(f"{CORRECT_CITY} note is '{actual_note}', expected '{EXPECTED_NOTE}'.")
        else:
            feedback_parts.append(f"Could not find {CORRECT_CITY} in database.")
            
        # Check for collateral damage (Did they update wrong cities?)
        cursor.execute("SELECT name FROM world_capitals WHERE notes LIKE ? AND name != ?", ('%DISPATCHING%', CORRECT_CITY))
        wrong_rows = cursor.fetchall()
        
        if len(wrong_rows) == 0:
            score += 10
            feedback_parts.append("No other cities incorrectly updated.")
        else:
            wrong_names = [r['name'] for r in wrong_rows]
            feedback_parts.append(f"Incorrectly updated: {', '.join(wrong_names)}.")

        conn.close()

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_gpkg.name): os.unlink(temp_gpkg.name)
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)

    # =========================================================
    # 3. VLM TRAJECTORY VERIFICATION
    # =========================================================
    # We check if the agent actually navigated the map and used the edit form.
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Review these screenshots of a QField GIS task.
        1. Do you see a map view centered on Central America / Panama (isthmus visible)?
        2. Do you see the "Attribute Form" or "Feature Details" panel open?
        3. Do you see text being entered like "DISPATCHING"?
        
        Answer JSON: {"map_navigated": bool, "form_opened": bool, "text_entered": bool}
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        vlm_data = vlm_res.get('parsed', {}) if vlm_res.get('success') else {}
        
        if vlm_data.get('map_navigated'):
            score += 10
        if vlm_data.get('form_opened'):
            score += 10
            
    # =========================================================
    # FINAL SCORING
    # =========================================================
    passed = updated_correctly and score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }