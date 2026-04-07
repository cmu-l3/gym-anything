#!/usr/bin/env python3
"""
Verifier for remove_decommissioned_sensors task.

Criteria:
1. 'Status: Active' sensors (IDs 1-3) must be PRESERVED.
2. 'Status: Decommissioned' sensors (IDs 4-6) must be DELETED.
3. The GeoPackage file must have been modified during the task.
"""

import json
import os
import sqlite3
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sensor_cleanup(traj, env_info, task_info):
    """
    Verify that decommissioned sensors were removed and active ones kept.
    """
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 2. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("/sdcard/task_result.json", temp_json)
        with open(temp_json, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json):
            os.remove(temp_json)

    # 3. Retrieve GeoPackage
    if not result_data.get("gpkg_exists"):
        return {"passed": False, "score": 0, "feedback": "GeoPackage file not found. Task failed."}

    temp_gpkg = tempfile.NamedTemporaryFile(delete=False, suffix='.gpkg').name
    try:
        copy_from_env("/sdcard/result_world_survey.gpkg", temp_gpkg)
        
        # 4. Verify Database Content
        conn = sqlite3.connect(temp_gpkg)
        cursor = conn.cursor()
        
        # Count remaining active sensors (Should be 3)
        cursor.execute("SELECT count(*) FROM field_observations WHERE notes LIKE '%Status: Active%'")
        active_count = cursor.fetchone()[0]
        
        # Count remaining decommissioned sensors (Should be 0)
        cursor.execute("SELECT count(*) FROM field_observations WHERE notes LIKE '%Status: Decommissioned%'")
        decom_count = cursor.fetchone()[0]
        
        conn.close()
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Database verification failed: {e}"}
    finally:
        if os.path.exists(temp_gpkg):
            os.remove(temp_gpkg)

    # 5. Scoring Logic
    score = 0
    feedback_parts = []
    passed = False

    # Criterion 1: Active Preservation (40 pts)
    # Expecting exactly 3 active sensors
    if active_count == 3:
        score += 40
        feedback_parts.append("✅ Active sensors preserved (3/3).")
    elif active_count < 3:
        feedback_parts.append(f"❌ Critical: You deleted {3 - active_count} active sensor(s)!")
    else:
        # Should not happen unless agent added data
        feedback_parts.append(f"⚠️ Weird: Found {active_count} active sensors (expected 3).")

    # Criterion 2: Decommissioned Removal (60 pts)
    # Expecting 0 decommissioned sensors.
    # We started with 3.
    deleted_count = 3 - decom_count
    if deleted_count < 0: deleted_count = 0 # Safety
    
    points_per_deletion = 20
    deletion_score = deleted_count * points_per_deletion
    score += deletion_score
    
    if decom_count == 0:
        feedback_parts.append("✅ All decommissioned sensors removed.")
    else:
        feedback_parts.append(f"❌ Missed {decom_count} decommissioned sensor(s).")

    # Anti-Gaming Check
    file_modified = result_data.get("file_modified", False)
    if not file_modified:
        score = 0
        feedback_parts = ["❌ file not modified (did nothing)."]

    # Final Pass Determination
    # Must preserve ALL active (40 pts) AND delete ALL decommissioned (60 pts) -> 100 total
    if score >= 100:
        passed = True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }