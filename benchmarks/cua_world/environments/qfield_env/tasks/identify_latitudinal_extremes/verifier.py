#!/usr/bin/env python3
"""
Verifier for identify_latitudinal_extremes task.

Logic:
1. Pull the resulting GeoPackage from the environment.
2. Open it with SQLite (standard library).
3. Compute GROUND TRUTH from the `world_capitals` table (robust to dataset updates).
4. Identify the NEW observation added by the agent in `field_observations`.
5. Parse the `notes` field for "North: X, South: Y, Span: Z".
6. Compare agent values with ground truth.
7. Verify VLM trajectory for map exploration.
"""

import sqlite3
import re
import json
import os
import tempfile
import logging
import math
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_latitudinal_extremes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Setup temporary files
    temp_dir = tempfile.mkdtemp()
    local_gpkg = os.path.join(temp_dir, "result.gpkg")
    local_json = os.path.join(temp_dir, "result.json")
    
    score = 0
    feedback = []
    
    try:
        # 1. Retrieve files
        try:
            copy_from_env("/sdcard/task_result.json", local_json)
            with open(local_json, 'r') as f:
                result_meta = json.load(f)
            
            if not result_meta.get("gpkg_exists"):
                return {"passed": False, "score": 0, "feedback": "GeoPackage file not found in environment."}
                
            copy_from_env("/sdcard/task_result.gpkg", local_gpkg)
            
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task artifacts: {str(e)}"}

        # 2. Connect to GeoPackage (SQLite)
        try:
            conn = sqlite3.connect(local_gpkg)
            cursor = conn.cursor()
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to open GeoPackage: {str(e)}"}

        # 3. Calculate Ground Truth dynamically
        # We query the capitals table to find the actual extremes
        try:
            # Table names are usually standard, but let's check
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='world_capitals';")
            if not cursor.fetchone():
                return {"passed": False, "score": 0, "feedback": "Integrity check failed: 'world_capitals' table missing."}

            # Get Northernmost
            # Assuming 'y' or 'lat' column exists, or we parse geometry. 
            # In OGC GeoPackages, geometry is binary blob, but usually there are attribute columns too.
            # We'll check for 'latitude' or 'lat' column.
            cursor.execute("PRAGMA table_info(world_capitals)")
            columns = [info[1].lower() for info in cursor.fetchall()]
            
            lat_col = 'latitude' if 'latitude' in columns else 'lat' if 'lat' in columns else None
            name_col = 'name' if 'name' in columns else 'city_name'
            
            if not lat_col:
                # If no direct lat column, we can't easily compute GT without parsing WKB geometry (complex).
                # Fallback: assuming the dataset has standard columns as per task desc.
                # Task desc says: "attributes including name... latitude"
                return {"passed": False, "score": 0, "feedback": "Dataset error: Latitude column not found in capitals."}

            cursor.execute(f"SELECT {name_col}, {lat_col} FROM world_capitals ORDER BY {lat_col} DESC LIMIT 1")
            north_city, north_lat = cursor.fetchone()
            
            cursor.execute(f"SELECT {name_col}, {lat_col} FROM world_capitals ORDER BY {lat_col} ASC LIMIT 1")
            south_city, south_lat = cursor.fetchone()
            
            true_span = round(north_lat - south_lat)
            
            logger.info(f"Ground Truth: North={north_city}({north_lat}), South={south_city}({south_lat}), Span={true_span}")
            
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error computing ground truth: {str(e)}"}

        # 4. Analyze Agent's Observation
        try:
            # Find the new observation. We look for the feature with the highest FID (latest added).
            # The 'field_observations' table should exist.
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='field_observations';")
            if not cursor.fetchone():
                return {"passed": False, "score": 0, "feedback": "'field_observations' layer missing."}

            # Get the latest entry
            cursor.execute("SELECT notes, geometry FROM field_observations ORDER BY fid DESC LIMIT 1")
            row = cursor.fetchone()
            
            if not row:
                return {"passed": False, "score": 0, "feedback": "No observations found in the layer."}
            
            agent_notes, agent_geom_blob = row
            
            if not agent_notes:
                return {"passed": False, "score": 0, "feedback": "Created observation has empty notes."}
            
            # 5. Score Content
            score += 10 # Created an observation
            feedback.append("Observation created.")
            
            # Parse notes using regex
            # Expected: "North: Reykjavik, South: Wellington, Span: 105"
            pattern = re.compile(r"North:\s*([^,]+),\s*South:\s*([^,]+),\s*Span:\s*(\d+)", re.IGNORECASE)
            match = pattern.search(agent_notes)
            
            if match:
                score += 5 # Correct format
                agent_north = match.group(1).strip()
                agent_south = match.group(2).strip()
                agent_span = int(match.group(3))
                
                # Check North City
                if agent_north.lower() in north_city.lower() or north_city.lower() in agent_north.lower():
                    score += 25
                    feedback.append(f"Correct northernmost city ({north_city}).")
                else:
                    feedback.append(f"Incorrect northernmost city. Expected {north_city}, got {agent_north}.")
                
                # Check South City
                if agent_south.lower() in south_city.lower() or south_city.lower() in agent_south.lower():
                    score += 25
                    feedback.append(f"Correct southernmost city ({south_city}).")
                else:
                    feedback.append(f"Incorrect southernmost city. Expected {south_city}, got {agent_south}.")
                    
                # Check Span (allow +/- 3 degrees tolerance for rounding diffs)
                if abs(agent_span - true_span) <= 3:
                    score += 15
                    feedback.append(f"Latitudinal span accurate ({agent_span}).")
                else:
                    feedback.append(f"Span value incorrect. Expected ~{true_span}, got {agent_span}.")
            else:
                feedback.append("Notes format incorrect. Expected 'North: [City], South: [City], Span: [Num]'.")

        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Error analyzing observation: {str(e)}"}
        finally:
            conn.close()

        # 6. VLM Trajectory Verification
        # Check if agent actually explored the map (High North / Low South)
        vlm_frames = sample_trajectory_frames(traj, n=8)
        
        vlm_prompt = f"""
        You are verifying a GIS task where the user must find the northernmost and southernmost cities on a world map.
        
        Review these screenshots of the QField mobile app.
        Look for evidence of:
        1. **Global Exploration**: Does the user pan to the far North (Arctic/Scandinavia/Greenland) AND far South (New Zealand/Australia/Southern Cone)?
        2. **Feature Identification**: Do you see the user tapping on features or viewing attribute panels (info windows)?
        3. **Data Entry**: Do you see the user filling out a form with "North" or "South" text?
        
        Return JSON:
        {{
            "explored_north": boolean,
            "explored_south": boolean,
            "viewed_attributes": boolean,
            "form_entry_visible": boolean,
            "reasoning": "string"
        }}
        """
        
        vlm_result = query_vlm(images=vlm_frames, prompt=vlm_prompt)
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("explored_north", False):
                score += 8
            if parsed.get("explored_south", False):
                score += 7
            if parsed.get("viewed_attributes", False):
                score += 3
            if parsed.get("form_entry_visible", False):
                score += 2
                
            if not parsed.get("explored_north") or not parsed.get("explored_south"):
                feedback.append("VLM: Map exploration incomplete (must visit both N and S extremes).")
        else:
            # Fallback if VLM fails: give partial credit if data was correct
            if score >= 60:
                score += 10 # Assume valid if answer was right
                feedback.append("VLM check skipped, awarding partial credit based on correct answer.")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir)

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }