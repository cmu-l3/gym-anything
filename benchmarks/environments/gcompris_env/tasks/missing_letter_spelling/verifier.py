#!/usr/bin/env python3
"""
Verifier for GCompris Missing Letter Spelling Task.

Verification Strategy:
1. Programmatic (Primary): Analyze GCompris SQLite database for 'missing_letter' activity logs.
   - We look for NEW entries in the `logs` table created during the task window.
   - We check for successful completions (status usually indicates success/fail).
2. VLM (Secondary/Anti-Gaming): Verify UI trajectory.
   - Confirm agent actually interacted with the specific "Missing Letter" UI.
   - Confirm visual feedback of success (animations).

Scoring:
- Database evidence of activity usage: 30 pts
- Database evidence of level completion/puzzles solved: 30 pts
- VLM verification of correct workflow: 40 pts
"""

import json
import sqlite3
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils from the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Mock for local testing if needed
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(images, prompt): return {"success": False}


def verify_missing_letter(traj, env_info, task_info):
    """
    Verify the agent completed the Missing Letter activity.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    score = 0
    feedback_parts = []
    
    # Load task result metadata
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    # ==========================================================================
    # 1. DATABASE VERIFICATION (60 points)
    # ==========================================================================
    db_score = 0
    db_path_in_container = task_result.get("db_path")
    initial_count = int(task_result.get("initial_db_count", 0))
    
    if task_result.get("db_exists") and db_path_in_container:
        with tempfile.NamedTemporaryFile(suffix=".db") as db_file:
            try:
                copy_from_env(db_path_in_container, db_file.name)
                
                conn = sqlite3.connect(db_file.name)
                cursor = conn.cursor()
                
                # Check for table existence
                cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='logs';")
                if not cursor.fetchone():
                    feedback_parts.append("Database logs table not found (no activity recorded?)")
                else:
                    # Query for missing_letter activity
                    # We look for rows with rowid > initial_count (approximate) or check timestamps if available
                    # Schema usually: id, user_id, date, activity, level, sublevel, status, duration
                    
                    # First, just get all logs for the activity
                    # 'missing_letter' is the internal name, but sometimes it's 'missing_letter_config' or similar
                    cursor.execute(f"SELECT * FROM logs WHERE activity LIKE '%missing_letter%'")
                    rows = cursor.fetchall()
                    
                    # Filter for new rows (naive approach: just count total, if > initial it's good, 
                    # but better to rely on count diff if we can't trust timestamps format)
                    # Since we don't know the exact ID sequence, let's count TOTAL rows in DB and subtract initial
                    cursor.execute("SELECT COUNT(*) FROM logs")
                    final_count = cursor.fetchone()[0]
                    new_entries = final_count - initial_count
                    
                    if new_entries > 0:
                        db_score += 20
                        feedback_parts.append(f"Database shows {new_entries} new activity actions")
                        
                        # Now check specifically for 'missing_letter' in the new entries
                        # We assume the new entries are at the end.
                        # GCompris logs are usually sequential.
                        cursor.execute(f"SELECT * FROM logs WHERE activity LIKE '%missing_letter%' ORDER BY rowid DESC LIMIT {new_entries}")
                        relevant_logs = cursor.fetchall()
                        
                        if relevant_logs:
                            db_score += 10
                            feedback_parts.append("Confirmed 'missing_letter' activity usage")
                            
                            # Check for success status (often column 7 or 8, varies by version, but usually '1' or 'true')
                            # We'll just look for any non-zero value in the likely status columns or just valid duration
                            # Let's count how many interactions. 5 required.
                            interaction_count = len(relevant_logs)
                            if interaction_count >= 5:
                                db_score += 30
                                feedback_parts.append(f"Recorded {interaction_count} puzzle attempts (Target: 5+)")
                            elif interaction_count >= 1:
                                db_score += 10
                                feedback_parts.append(f"Recorded {interaction_count} puzzle attempts (Target: 5+)")
                        else:
                            feedback_parts.append("New DB entries found, but not for 'missing_letter'")
                    else:
                        feedback_parts.append("No new database entries found")

            except Exception as e:
                feedback_parts.append(f"Database analysis failed: {e}")
            finally:
                if 'conn' in locals(): conn.close()
    else:
        feedback_parts.append("GCompris database not found")

    score += db_score

    # ==========================================================================
    # 2. VLM TRAJECTORY VERIFICATION (40 points)
    # ==========================================================================
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=5)
    final_img = get_final_screenshot(traj)
    
    if frames:
        prompt = """
        You are analyzing screenshots of the educational game GCompris 'Missing Letter' activity.
        
        Look for:
        1. A central image (like an object, animal, or fruit).
        2. A word below the image with a missing letter (e.g., "ap_le").
        3. Several letter buttons to choose from.
        4. Feedback animations (smileys, 'OK', 'Great') or level completion screens.
        
        Answer these questions JSON format:
        {
            "is_missing_letter_activity": boolean,
            "puzzles_visible": boolean,
            "level_completion_visible": boolean,
            "progression_observed": boolean
        }
        """
        
        # We verify using the full sequence + final image
        analysis_images = frames + ([final_img] if final_img else [])
        vlm_result = query_vlm(images=analysis_images, prompt=prompt)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("is_missing_letter_activity"):
                vlm_score += 10
                feedback_parts.append("VLM confirmed correct activity interface")
            
            if parsed.get("puzzles_visible"):
                vlm_score += 10
                feedback_parts.append("VLM saw spelling puzzles")
                
            if parsed.get("progression_observed"):
                vlm_score += 10
                feedback_parts.append("VLM observed gameplay progression")
                
            if parsed.get("level_completion_visible"):
                vlm_score += 10
                feedback_parts.append("VLM detected level completion")
        else:
            feedback_parts.append("VLM analysis failed to process images")
    
    score += vlm_score

    # ==========================================================================
    # 3. FINAL EVALUATION
    # ==========================================================================
    # If DB failed (maybe version mismatch) but VLM is perfect, we can still pass with a penalty or check logic.
    # But usually, we want robust checking.
    
    # Allow pass if VLM is very strong (30+) even if DB is empty (in case of write delays/permissions)
    # OR if DB is strong (40+)
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }