#!/usr/bin/env python3
import json
import os
import sqlite3
import tempfile
import logging
import shutil
import glob
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_crop_monitoring(traj, env_info, task_info):
    """
    Verifies that 3 crop monitoring logs were created with correct details.
    
    Strategy:
    1. Primary: Inspect exported SQLite database for log entries.
       - Checks for count (3)
       - Checks for specific text in 'notes' or 'data' columns.
    2. Secondary: VLM inspection of the final screen and trajectory.
       - Confirms 3 items in list.
       - confirms workflow progression.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []
    
    # Setup temporary directory for analysis
    temp_dir = tempfile.mkdtemp()
    try:
        # =========================================================
        # PART 1: Database Verification (40 points)
        # =========================================================
        # Copy the exported task data from Android /sdcard/task_export
        # copy_from_env expects a single file usually, so we might need to copy specific DBs
        # Since we don't know the exact DB name, we'll try to find the likely candidate.
        # Note: 'copy_from_env' usually copies a file or dir to local.
        
        db_valid = False
        logs_found = []
        
        # Try to copy the databases directory
        local_db_dir = os.path.join(temp_dir, "databases")
        try:
            # We assume export_result.sh created a directory structure
            # We'll try to copy the specific known WebSQL/SQLite file locations
            # Common Cordova locations:
            # - databases/file__0/1
            # - databases/WebSQL.db
            # - databases/*.db
            
            # Since copy_from_env signature varies, we'll try to list/copy
            # If we can't recursively copy, we might fail here. 
            # Assuming standard container cp capability:
            copy_from_env("/sdcard/task_export/databases", local_db_dir)
            
            # Find any SQLite files
            db_files = glob.glob(os.path.join(local_db_dir, "**", "*"), recursive=True)
            candidate_dbs = [f for f in db_files if os.path.isfile(f) and not f.endswith('-journal')]
            
            logger.info(f"Found candidate DBs: {candidate_dbs}")
            
            for db_file in candidate_dbs:
                try:
                    conn = sqlite3.connect(db_file)
                    cursor = conn.cursor()
                    
                    # Introspect tables to find logs
                    # FarmOS Field Kit often stores logs in a 'documents' or 'logs' table
                    # or a key-value store table
                    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
                    tables = [row[0] for row in cursor.fetchall()]
                    
                    # Search all text columns in all tables for our keywords
                    for table in tables:
                        try:
                            # Dump table content
                            cursor.execute(f"SELECT * FROM {table}")
                            rows = cursor.fetchall()
                            for row in rows:
                                row_str = str(row).lower()
                                if "corn" in row_str or "stage" in row_str:
                                    logs_found.append(row_str)
                        except:
                            pass
                    conn.close()
                except Exception as e:
                    logger.warning(f"Failed to read DB {db_file}: {e}")

            if len(logs_found) > 0:
                db_valid = True
                
        except Exception as e:
            logger.warning(f"Database extraction failed: {e}")
            feedback.append("Could not verify internal database state (system restriction).")

        # Score DB findings
        if db_valid:
            unique_logs = len(logs_found)
            # Filter for our specific weeks
            week1 = any("v3 stage" in log for log in logs_found)
            week2 = any("v6 stage" in log for log in logs_found)
            week3 = any("v9 stage" in log for log in logs_found)
            
            if week1: score += 10
            if week2: score += 10
            if week3: score += 10
            if unique_logs >= 3: 
                score += 10
                feedback.append("Database confirmed 3 distinct corn monitoring logs.")
            else:
                feedback.append(f"Database showed {unique_logs} logs, expected 3.")
        else:
            # Fallback scoring if DB is inaccessible
            feedback.append("Skipping database scoring, relying on VLM.")

        # =========================================================
        # PART 2: VLM Verification (60 points + Fallback)
        # =========================================================
        
        # Get screenshots
        final_ss_path = os.path.join(temp_dir, "final.png")
        try:
            copy_from_env("/sdcard/task_export/final_screenshot.png", final_ss_path)
        except:
            final_ss_path = None

        if final_ss_path and os.path.exists(final_ss_path):
            
            # 1. Final State Check
            prompt = """
            Analyze this screenshot of the farmOS Field Kit app.
            
            I am looking for a list of 3 specific logs:
            1. A log dated May 19 (or Week 1)
            2. A log dated May 26 (or Week 2)
            3. A log dated June 2 (or Week 3)
            
            The logs should be 'Observation' type.
            
            Questions:
            1. How many log entries are visible in the list?
            2. Can you see dates corresponding to May/June 2025?
            3. Do the entries look like 'Observation' logs (icon or text)?
            
            Return JSON:
            {
                "log_count": <number>,
                "dates_visible": <bool>,
                "observation_type_visible": <bool>,
                "confidence": "high/medium/low"
            }
            """
            
            vlm_res = query_vlm(prompt=prompt, image=final_ss_path)
            parsed = vlm_res.get('parsed', {})
            
            vlm_count = parsed.get('log_count', 0)
            if isinstance(vlm_count, str): vlm_count = 0
            
            if vlm_count >= 3:
                score += 25
                feedback.append("VLM confirms 3 logs visible.")
            elif vlm_count > 0:
                score += 10
                feedback.append(f"VLM sees {vlm_count} logs (expected 3).")
                
            if parsed.get('dates_visible'):
                score += 15
                feedback.append("VLM confirms visible dates.")
                
            if parsed.get('observation_type_visible'):
                score += 10
                feedback.append("VLM confirms Observation type.")

            # 2. Trajectory Check (Did they actually type the notes?)
            # Sample frames to see if they entered the detailed text
            frames = sample_trajectory_frames(traj, n=8)
            traj_prompt = """
            Look at these screenshots of a user using farmOS.
            
            Did the user:
            1. Enter text about "V3 stage" or "32,000 plants"?
            2. Enter text about "V6 stage" or "flea beetle"?
            3. Enter text about "V9 stage" or "tassel"?
            4. Enter numeric quantities like 12, 24, or 38?
            
            Return JSON:
            {
                "entered_week1_notes": <bool>,
                "entered_week2_notes": <bool>,
                "entered_week3_notes": <bool>,
                "entered_quantities": <bool>
            }
            """
            
            traj_res = query_vlm(prompt=traj_prompt, images=frames)
            t_parsed = traj_res.get('parsed', {})
            
            # If DB verification failed/was skipped, these points become critical
            # Adjust scoring weights dynamically if needed, but for now strict addition
            
            if not db_valid:
                # Boost VLM points if DB unavailable
                multiplier = 2.0
            else:
                multiplier = 1.0
                
            if t_parsed.get('entered_week1_notes'): score += (5 * multiplier)
            if t_parsed.get('entered_week2_notes'): score += (5 * multiplier)
            if t_parsed.get('entered_week3_notes'): score += (5 * multiplier)
            if t_parsed.get('entered_quantities'): score += (5 * multiplier)

    except Exception as e:
        logger.error(f"Verification error: {e}")
        feedback.append(f"Verification process error: {str(e)}")
    finally:
        shutil.rmtree(temp_dir)

    # Cap score at 100
    score = min(100, score)
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }