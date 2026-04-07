#!/usr/bin/env python3
"""Verifier for migrate_logbook_sqlite task.

Checks that the SQLite database was properly formatted (not just renamed), 
contains Subsurface data, and the Subsurface.conf DefaultFilename was updated.
Also utilizes VLM on trajectory frames to ensure dialog interactions.
"""

import os
import json
import sqlite3
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_logbook_sqlite(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_sqlite_path = metadata.get('expected_sqlite_path', '/home/ga/Documents/dive_data.sqlite')
    expected_conf_path = metadata.get('expected_conf_path', '/home/ga/.config/Subsurface/Subsurface.conf')

    score = 0
    feedback_parts = []

    # 1. Read export JSON
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        result_meta = {"output_exists": False, "file_created_during_task": False}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Check SQLite File Existence & Creation Time (10 pts)
    output_exists = result_meta.get('output_exists', False)
    file_created = result_meta.get('file_created_during_task', False)

    if output_exists:
        if file_created:
            score += 10
            feedback_parts.append("File exists and was created during task")
        else:
            feedback_parts.append("File exists but timestamp precedes task start (Anti-gaming flag)")
    else:
        feedback_parts.append("dive_data.sqlite not found")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # 3. SQLite Binary & Schema Verification (30 pts format + 20 pts data)
    tmp_sqlite = tempfile.NamedTemporaryFile(delete=False, suffix='.sqlite')
    tmp_sqlite.close()
    
    valid_sqlite = False
    data_migrated = False
    try:
        copy_from_env(expected_sqlite_path, tmp_sqlite.name)
        
        # Connect to SQLite
        conn = sqlite3.connect(tmp_sqlite.name)
        cursor = conn.cursor()
        
        # Check if it's a valid SQLite DB (fails if it's just a renamed XML file)
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = [row[0] for row in cursor.fetchall()]
        
        if tables:
            valid_sqlite = True
            score += 30
            feedback_parts.append("Valid SQLite binary format confirmed")
            
            # Subsurface creates specific tables like 'dives', 'cylinders'
            if 'dives' in tables or 'dive_computers' in tables:
                cursor.execute("SELECT count(*) FROM dives;")
                dive_count = cursor.fetchone()[0]
                if dive_count > 0:
                    data_migrated = True
                    score += 20
                    feedback_parts.append(f"Data migration successful ({dive_count} dives found)")
                else:
                    feedback_parts.append("SQLite database is valid but contains no dive data")
            else:
                feedback_parts.append("Database is valid SQLite but missing Subsurface schema")
        
        conn.close()
    except sqlite3.DatabaseError:
        feedback_parts.append("CRITICAL: File is NOT a database. It may be a renamed XML file.")
    except Exception as e:
        feedback_parts.append(f"SQLite verification error: {str(e)}")
    finally:
        if os.path.exists(tmp_sqlite.name):
            os.unlink(tmp_sqlite.name)

    # 4. Preferences Update Verification (20 pts)
    tmp_conf = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
    tmp_conf.close()
    
    config_updated = False
    try:
        copy_from_env(expected_conf_path, tmp_conf.name)
        
        # Parse Subsurface.conf directly to avoid Qt/configparser quirks
        with open(tmp_conf.name, 'r') as f:
            for line in f:
                if 'DefaultFilename' in line:
                    val = line.split('=', 1)[1].strip()
                    if val == expected_sqlite_path:
                        config_updated = True
                        break
                        
        if config_updated:
            score += 20
            feedback_parts.append("Preferences updated successfully")
        else:
            feedback_parts.append("DefaultFilename preference does not point to the new SQLite file")
    except Exception as e:
        feedback_parts.append(f"Preferences check error: {str(e)}")
    finally:
        if os.path.exists(tmp_conf.name):
            os.unlink(tmp_conf.name)

    # 5. VLM Trajectory Verification (20 pts)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            prompt = """Analyze this sequence of screenshots from an agent automating the Subsurface dive log application.
            Did the agent accomplish BOTH of the following:
            1. Opened the "Save As" file dialog, selected SQLite format, and saved the file?
            2. Opened the Subsurface "Preferences" dialog and modified the 'Default filename' path?
            
            Respond in JSON:
            {
                "opened_save_as": true/false,
                "opened_preferences": true/false
            }
            """
            vlm_result = query_vlm(images=images, prompt=prompt)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("opened_save_as"):
                    vlm_score += 10
                if parsed.get("opened_preferences"):
                    vlm_score += 10
                
                score += vlm_score
                feedback_parts.append(f"VLM trajectory verification: +{vlm_score} pts")
            else:
                feedback_parts.append("VLM verification failed to process")
                # Grant points if programmatic was perfect and VLM simply errored
                if valid_sqlite and data_migrated and config_updated:
                    score += 20
    except ImportError:
        # If VLM is not available in the testing environment, grant points if programmatic passes
        logger.warning("VLM module not found, relying purely on programmatic verification.")
        if valid_sqlite and data_migrated and config_updated:
            score += 20

    # Determine passing status
    passed = score >= 80 and valid_sqlite and config_updated

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }