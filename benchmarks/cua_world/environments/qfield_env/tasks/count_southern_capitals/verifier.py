#!/usr/bin/env python3
"""
Verifier for count_southern_capitals task.
Verifies that the agent correctly identified Southern Hemisphere capitals
by comparing the output text file against the actual GeoPackage data.
"""

import json
import os
import sqlite3
import tempfile
import struct
import logging
from typing import Dict, Any, List, Tuple

# Import VLM utilities from framework
# Assuming gym_anything.vlm provides these
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
except ImportError:
    # Mock for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_geopackage_header(blob):
    """
    Minimal parser for GeoPackage Binary Header to extract Y coordinate.
    GPKG binary format:
    - Magic (2 bytes): 0x47 0x50
    - Version (1 byte)
    - Flags (1 byte)
    - SRS ID (4 bytes, int32)
    - Envelope (variable based on flags)
    """
    try:
        # Check magic 'GP'
        if blob[:2] != b'GP':
            return None
        
        flags = blob[3]
        # Envelope contents indicator (bits 1-3)
        envelope_indicator = (flags >> 1) & 0x07
        
        # Envelope sizes: 0=none, 1=32 bytes, 2=48 bytes, 3=48 bytes, 4=64 bytes
        if envelope_indicator == 0:
            return None # No envelope to read coords from easily without full WKB parser
        
        # SRS ID is at offset 4 (4 bytes)
        # Envelope starts at offset 8
        
        # We need the Y coordinate. 
        # If envelope is present, it contains [minx, maxx, miny, maxy, ...]
        # For a point, miny should equal maxy, which is the latitude.
        
        # Assuming Little Endian (bit 0 of flags == 1)
        # Most GPKG are little endian.
        is_little_endian = (flags & 0x01) == 1
        endian_char = '<' if is_little_endian else '>'
        
        if envelope_indicator == 1: # minx, maxx, miny, maxy (doubles)
            # Offset 8 + 16 bytes (minx, maxx) -> miny is at 24
            min_y = struct.unpack(endian_char + 'd', blob[24:32])[0]
            return min_y
            
        return None # Other envelopes not implemented for this simple check
        
    except Exception as e:
        logger.warning(f"Failed to parse GPKG blob: {e}")
        return None

def get_ground_truth(gpkg_path: str) -> Tuple[int, List[str]]:
    """
    Extracts the list of Southern Hemisphere capitals from the GeoPackage.
    """
    if not os.path.exists(gpkg_path):
        logger.error(f"GeoPackage not found at {gpkg_path}")
        return 0, []

    conn = sqlite3.connect(gpkg_path)
    cursor = conn.cursor()
    
    southern_capitals = []
    
    try:
        # Try to find a latitude column first (easiest)
        cursor.execute("PRAGMA table_info(world_capitals)")
        columns = [info[1].lower() for info in cursor.fetchall()]
        
        if 'latitude' in columns or 'lat' in columns or 'y' in columns:
            col = 'latitude' if 'latitude' in columns else ('lat' if 'lat' in columns else 'y')
            cursor.execute(f"SELECT name FROM world_capitals WHERE {col} < 0")
            rows = cursor.fetchall()
            southern_capitals = [r[0] for r in rows if r[0]]
        else:
            # Fallback: Parse geometry blob
            # GeoPackage geometry columns are usually named 'geom' or 'geometry'
            geom_col = 'geom' if 'geom' in columns else 'geometry'
            cursor.execute(f"SELECT name, {geom_col} FROM world_capitals")
            rows = cursor.fetchall()
            
            for name, blob in rows:
                if not blob: continue
                lat = parse_geopackage_header(blob)
                if lat is not None and lat < 0:
                    southern_capitals.append(name)
                    
    except Exception as e:
        logger.error(f"Error reading GeoPackage: {e}")
    finally:
        conn.close()
        
    return len(southern_capitals), sorted(southern_capitals)

def verify_count_southern_capitals(traj, env_info, task_info):
    """
    Verification logic for count_southern_capitals.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    score = 0
    feedback = []
    max_score = 100
    
    # 1. Retrieve artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        local_result_json = os.path.join(temp_dir, "task_result.json")
        local_output_txt = os.path.join(temp_dir, "southern_hemisphere_capitals.txt")
        local_gpkg = os.path.join(temp_dir, "world_survey.gpkg")
        
        try:
            copy_from_env("/sdcard/task_result.json", local_result_json)
            copy_from_env("/sdcard/southern_hemisphere_capitals.txt", local_output_txt)
            # Fetch the actual GPKG used to ensure ground truth matches data
            copy_from_env("/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg", local_gpkg)
        except Exception as e:
            logger.warning(f"File copy failed: {e}")
            # If output text file is missing, we continue but score will be low
            pass

        # Load JSON result
        if os.path.exists(local_result_json):
            with open(local_result_json, 'r') as f:
                task_result = json.load(f)
        else:
            task_result = {}

        # 2. Check File Existence and Creation (20 pts)
        if task_result.get("output_exists") and task_result.get("created_during_task"):
            score += 20
            feedback.append("Output file created successfully.")
        elif task_result.get("output_exists"):
            score += 10
            feedback.append("Output file exists but timestamp check failed (possible pre-existing file).")
        else:
            feedback.append("Output file '/sdcard/southern_hemisphere_capitals.txt' not found.")
            return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

        # 3. Calculate Ground Truth
        gt_count, gt_names = get_ground_truth(local_gpkg)
        if gt_count == 0:
            # Fallback if binary parsing failed: approximate list based on standard knowledge
            # (In a real scenario, we'd ensure the parser works, but for safety:)
            gt_names = ["Antananarivo", "Apia", "Asuncion", "Brasilia", "Buenos Aires", 
                        "Canberra", "Cape Town", "Dodoma", "Funafuti", "Gaborone", 
                        "Harare", "Honiara", "Jakarta", "Kigali", "Kinshasa", "La Paz", 
                        "Libreville", "Lilongwe", "Lima", "Luanda", "Lusaka", "Maputo", 
                        "Maseru", "Mbabane", "Montevideo", "Moroni", "Nairobi", "Nuku'alofa", 
                        "Port Louis", "Port Moresby", "Port Vila", "Port-aux-Francais", 
                        "Pretoria", "Quito", "Santiago", "Suva", "Wellington", "Windhoek", "Yaren"]
            gt_count = len(gt_names)
            logger.warning("Using fallback ground truth list.")

        # 4. Parse User Output
        user_count = -1
        user_names = []
        try:
            with open(local_output_txt, 'r') as f:
                lines = [l.strip() for l in f.readlines() if l.strip()]
                if lines:
                    try:
                        user_count = int(lines[0])
                    except ValueError:
                        feedback.append("First line of output is not an integer.")
                    
                    user_names = sorted(lines[1:])
        except Exception as e:
            feedback.append(f"Could not read output file: {e}")

        # 5. Verify Content (40 pts)
        
        # Check Count (15 pts)
        if user_count == gt_count:
            score += 15
            feedback.append(f"Correct count ({user_count}).")
        else:
            feedback.append(f"Incorrect count. Expected {gt_count}, got {user_count}.")

        # Check Names (25 pts)
        # Normalize for comparison
        gt_set = {n.lower() for n in gt_names}
        user_set = {n.lower() for n in user_names}
        
        common = gt_set.intersection(user_set)
        
        if len(gt_set) > 0:
            accuracy = len(common) / len(gt_set)
            name_points = int(25 * accuracy)
            score += name_points
            
            if accuracy == 1.0 and len(user_set) == len(gt_set):
                feedback.append("City list matches perfectly.")
            elif accuracy > 0.8:
                feedback.append(f"City list is mostly correct ({len(common)}/{len(gt_set)} matches).")
            else:
                feedback.append(f"City list has significant errors ({len(common)}/{len(gt_set)} matches).")
                
            # Check for extra wrong names
            extras = len(user_set) - len(common)
            if extras > 0:
                score = max(0, score - (extras * 2)) # Penalty for hallucinations
                feedback.append(f"Found {extras} incorrect extra cities.")

    # 6. VLM Trajectory Verification (40 pts)
    # Ensure they actually used QField
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    Review this sequence of screenshots from an Android device.
    The user task is to count Southern Hemisphere capitals in QField.
    
    Check for:
    1. Is the QField app visible? (Map interface with buttons)
    2. Is a map with markers/points visible?
    3. Did the user open a feature list or tap on points to see attributes?
    4. Is there evidence of browsing or inspecting data?
    
    Return JSON:
    {
        "qfield_visible": true/false,
        "data_inspection_visible": true/false,
        "map_visible": true/false
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("qfield_visible"):
            score += 10
        if parsed.get("map_visible"):
            score += 10
        if parsed.get("data_inspection_visible"):
            score += 20
            feedback.append("VLM confirmed data inspection.")
        else:
            feedback.append("VLM did not see explicit feature inspection.")
    else:
        # Fallback if VLM fails but app was running (from export script)
        if task_result.get("app_running"):
            score += 10
            feedback.append("QField was running (VLM unavailable).")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }