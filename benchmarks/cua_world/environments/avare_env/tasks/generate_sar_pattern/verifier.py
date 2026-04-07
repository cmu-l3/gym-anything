#!/usr/bin/env python3
"""
Verifier for generate_sar_pattern task.

Verifies:
1. Active flight plan contains specific SAR waypoints (Programmatic)
2. Map displays the search pattern (Visual/VLM)
"""

import sqlite3
import json
import os
import tempfile
import logging
import math
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_sar_pattern(traj, env_info, task_info):
    """
    Verify the agent generated a Parallel Track search pattern anchored at OAK.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    db_path_export = metadata.get('db_path_export', '/sdcard/tasks/generate_sar_pattern/plans.db')
    
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. DATABASE VERIFICATION (60 points)
    # =========================================================
    temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
    temp_db.close() # Close so we can write to it
    
    try:
        copy_from_env(db_path_export, temp_db.name)
        
        conn = sqlite3.connect(temp_db.name)
        cursor = conn.cursor()
        
        # Check if 'plan' table exists
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='plan';")
        if not cursor.fetchone():
            feedback_parts.append("Flight plan database is empty or uninitialized.")
            db_score = 0
        else:
            # Get all waypoints
            # Schema typically: _id, Destination, Type, Lat, Lon, ...
            cursor.execute("SELECT * FROM plan")
            cols = [description[0] for description in cursor.description]
            rows = cursor.fetchall()
            
            # Helper to get col value
            def get_val(row, col_name):
                if col_name in cols:
                    return row[cols.index(col_name)]
                return None

            waypoint_count = len(rows)
            logger.info(f"Found {waypoint_count} waypoints in plan.")

            if waypoint_count == 0:
                feedback_parts.append("Flight plan is empty.")
                db_score = 0
            else:
                # Criteria 1: Waypoint Count (20 pts)
                # A 6-leg parallel pattern needs Start + 6 legs + turns. Should be >= 6 points.
                if waypoint_count >= 6:
                    score += 20
                    feedback_parts.append(f"Plan has sufficient waypoints ({waypoint_count}).")
                else:
                    feedback_parts.append(f"Plan has too few waypoints ({waypoint_count} < 6).")

                # Criteria 2: Anchor Point (20 pts)
                # First point should be OAK (approx 37.72, -122.22)
                first_pt = rows[0]
                lat = get_val(first_pt, 'Lat')
                lon = get_val(first_pt, 'Lon')
                name = get_val(first_pt, 'Destination') or get_val(first_pt, 'Name') or ""
                
                # Check Name or Coordinates
                is_oak_name = "OAK" in str(name).upper()
                is_oak_loc = False
                if lat and lon:
                    # Tolerance 0.05 degrees (~3nm)
                    if abs(lat - 37.72) < 0.05 and abs(lon - (-122.22)) < 0.05:
                        is_oak_loc = True
                
                if is_oak_name or is_oak_loc:
                    score += 20
                    feedback_parts.append("Anchor point OAK confirmed.")
                else:
                    feedback_parts.append(f"Anchor point mismatch (Found: {name} at {lat}, {lon}).")

                # Criteria 3: Pattern Geometry/Dimensions (20 pts)
                # Pattern goes North (360) for 10 NM.
                # 10 NM is approx 0.166 degrees latitude.
                # Max Lat should be roughly Start_Lat + 0.16.
                # Spacing 1NM * 6 legs = 6 NM width (~0.1 degrees lon).
                
                lats = [get_val(r, 'Lat') for r in rows if get_val(r, 'Lat')]
                if lats:
                    min_lat, max_lat = min(lats), max(lats)
                    lat_span = max_lat - min_lat
                    
                    # Expected span ~0.16 degrees (10nm)
                    # Allow range 0.10 to 0.25
                    if 0.10 <= lat_span <= 0.25:
                        score += 20
                        feedback_parts.append(f"Pattern length correct (~{lat_span*60:.1f} NM).")
                    else:
                        feedback_parts.append(f"Pattern length incorrect (Span: {lat_span*60:.1f} NM, expected ~10).")
                else:
                    feedback_parts.append("Could not read latitude data.")

    except Exception as e:
        feedback_parts.append(f"Database analysis failed: {str(e)}")
        logger.error(f"DB Error: {e}")
    finally:
        if os.path.exists(temp_db.name):
            os.unlink(temp_db.name)

    # =========================================================
    # 2. VLM VISUAL VERIFICATION (40 points)
    # =========================================================
    # We look for a ladder/zigzag pattern on the map
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images_to_check = frames + ([final_screen] if final_screen else [])
    
    if not images_to_check:
        feedback_parts.append("No screenshots available for VLM.")
    else:
        # We focus on the latest valid frame
        target_image = images_to_check[-1]
        
        prompt = """
        Analyze this screenshot from an aviation GPS app.
        1. Do you see a flight plan path drawn on the map? (Lines connecting waypoints)
        2. Does the path look like a "Parallel Search Pattern"? It should look like a ladder or a rectangular zig-zag back and forth.
        3. Does the text "OAK" or "Oakland" appear near the start of the pattern?
        
        Answer JSON: {"has_path": bool, "is_ladder_pattern": bool, "anchor_visible": bool}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, image=target_image)
            
            if vlm_res['success']:
                analysis = vlm_res.get('parsed', {})
                
                if analysis.get('has_path', False):
                    score += 10
                    feedback_parts.append("VLM: Path visible on map.")
                
                if analysis.get('is_ladder_pattern', False):
                    score += 20
                    feedback_parts.append("VLM: Ladder search pattern identified.")
                
                if analysis.get('anchor_visible', False):
                    score += 10
                    feedback_parts.append("VLM: Anchor OAK visible.")
            else:
                feedback_parts.append("VLM analysis failed.")
                
        except Exception as e:
            logger.error(f"VLM Error: {e}")
            feedback_parts.append("VLM error.")

    # =========================================================
    # FINAL SCORE
    # =========================================================
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }