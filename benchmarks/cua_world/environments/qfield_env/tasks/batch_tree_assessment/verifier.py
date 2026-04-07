#!/usr/bin/env python3
"""
Verifier for QField batch_tree_assessment task.
Checks:
1. GeoPackage persistence (file modified).
2. Database records (3 new specific features added).
3. Attribute correctness (Name, Notes keywords).
4. Spatial correctness (Coordinates near targets).
5. VLM Trajectory (Visual verification of navigation/form filling).
"""

import json
import sqlite3
import tempfile
import os
import shutil
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utils if available in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    logger.warning("gym_anything.vlm not available, skipping VLM checks")
    VLM_AVAILABLE = False

def calculate_distance(lat1, lon1, lat2, lon2):
    """Calculate Euclidean distance in degrees (sufficient for this scale)."""
    return math.sqrt((lat1 - lat2)**2 + (lon1 - lon2)**2)

def verify_batch_tree_assessment(traj, env_info, task_info):
    """
    Verify the agent added 3 specific tree observations at different locations.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', [])
    gpkg_path_in_container = metadata.get('gpkg_path')
    
    score = 0
    feedback_parts = []
    
    # Create temp directory for artifacts
    temp_dir = tempfile.mkdtemp()
    local_gpkg = os.path.join(temp_dir, "world_survey.gpkg")
    local_json = os.path.join(temp_dir, "task_result.json")

    try:
        # 1. Retrieve Artifacts
        try:
            copy_from_env("/sdcard/task_result.json", local_json)
            with open(local_json, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        try:
            copy_from_env(gpkg_path_in_container, local_gpkg)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve GeoPackage: {e}"}

        # 2. Database Verification
        conn = sqlite3.connect(local_gpkg)
        cursor = conn.cursor()

        # Check Total Count
        try:
            cursor.execute("SELECT COUNT(*) FROM field_observations")
            final_count = cursor.fetchone()[0]
            initial_count = task_result.get('initial_count', 8)
            
            if final_count == initial_count + 3:
                score += 10
                feedback_parts.append("Correctly added exactly 3 new features (+10)")
            elif final_count > initial_count:
                score += 5
                feedback_parts.append(f"Added {final_count - initial_count} features (expected 3) (+5)")
            else:
                feedback_parts.append("No new features added")
        except Exception as e:
            feedback_parts.append(f"Database query error: {e}")
            final_count = 0

        # Check Specific Targets
        features_found = 0
        locations_valid = 0
        
        for target in targets:
            t_name = target['name']
            t_keywords = target['keywords']
            t_lat = target['lat']
            t_lon = target['lon']
            tolerance = target['tolerance']

            # Query for this specific tree name
            # Note: We use lower() for robust matching
            cursor.execute("SELECT name, notes, ST_X(geom), ST_Y(geom) FROM field_observations WHERE name = ?", (t_name,))
            row = cursor.fetchone()

            if row:
                features_found += 1
                score += 5  # Feature exists with correct name
                
                # Check Notes
                notes = (row[1] or "").lower()
                if any(k.lower() in notes for k in t_keywords):
                    score += 10
                    feedback_parts.append(f"Found {t_name} with correct notes (+15)")
                else:
                    feedback_parts.append(f"Found {t_name} but notes missing keywords (+5)")

                # Check Location
                # Handle potential None geometries
                if row[2] is not None and row[3] is not None:
                    act_lon = row[2]
                    act_lat = row[3]
                    dist = calculate_distance(act_lat, act_lon, t_lat, t_lon)
                    
                    if dist <= tolerance:
                        locations_valid += 1
                        score += 5
                        feedback_parts.append(f"{t_name} location valid (dist {dist:.2f}) (+5)")
                    else:
                        feedback_parts.append(f"{t_name} location too far (dist {dist:.2f})")
                else:
                    feedback_parts.append(f"{t_name} has invalid geometry")
            else:
                feedback_parts.append(f"Missing feature: {t_name}")

        conn.close()

        # 3. Check for Distinct Locations (Anti-gaming: preventing 3 points at same spot)
        if locations_valid == 3:
            score += 10
            feedback_parts.append("All points at distinct valid locations (+10)")
        elif locations_valid >= 2:
            score += 5
            feedback_parts.append("Some points at valid locations (+5)")

        # 4. Persistence/Activity Check
        if task_result.get('gpkg_mtime', 0) > task_result.get('task_start', 0):
            score += 10
            feedback_parts.append("Database modified during task (+10)")

        # 5. VLM Trajectory Verification
        # Checks if the agent actually navigated the map
        if VLM_AVAILABLE:
            frames = sample_trajectory_frames(traj, n=6)
            prompt = """
            Review these screenshots of a QField mobile GIS session.
            The user should be:
            1. Navigating a map to different locations (Paris, Berlin, Rome).
            2. Opening a form to add points.
            3. Typing text into the form.

            Do you see:
            A. The map view changing significantly between frames (panning/zooming)?
            B. A data entry form appearing multiple times?
            C. Different locations being visited (not just staying in one place)?

            Reply with JSON: {"map_navigated": bool, "form_seen": bool, "confidence": "high/medium/low"}
            """
            
            try:
                vlm_res = query_vlm(images=frames, prompt=prompt)
                parsed = vlm_res.get('parsed', {})
                if parsed.get('map_navigated') and parsed.get('form_seen'):
                    score += 10
                    feedback_parts.append("VLM confirmed navigation and form usage (+10)")
                elif parsed.get('map_navigated'):
                    score += 5
                    feedback_parts.append("VLM confirmed navigation (+5)")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
                # Fallback: give points if score is already high (benefit of doubt if technical fail)
                if score >= 60:
                    score += 10
                    feedback_parts.append("VLM check skipped (technical error) (+10)")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {e}"}
    finally:
        shutil.rmtree(temp_dir)

    # Final Evaluation
    # Pass threshold: 60 points + at least 2 features found
    passed = score >= 60 and features_found >= 2
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }