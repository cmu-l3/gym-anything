#!/usr/bin/env python3
"""
Verifier for restore_missing_iso_codes task.

Checks:
1. `world_capitals` table has `iso_code` column.
2. Tokyo == 'JP'
3. Canberra == 'AU'
4. Brasilia == 'BR'
5. Data integrity (other records not corrupted).
6. File modification timestamp check.
"""

import json
import sqlite3
import os
import shutil
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_missing_iso_codes(traj, env_info, task_info):
    """
    Verify that the agent correctly updated the ISO codes in the GeoPackage.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Scoring weights
    SCORE_TOKYO = 30
    SCORE_CANBERRA = 30
    SCORE_BRASILIA = 30
    SCORE_INTEGRITY = 10
    
    score = 0
    feedback_parts = []
    
    # Create temp directory for artifacts
    temp_dir = tempfile.mkdtemp()
    try:
        # 1. Retrieve Result JSON
        local_result_json = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result metadata: {e}"}

        # 2. Check timestamp/modification
        if not result_data.get("file_modified_during_task", False):
            feedback_parts.append("WARNING: GeoPackage file was not modified during the task window.")
            # We don't fail immediately, but it's suspicious.
        else:
            feedback_parts.append("File modification detected.")

        # 3. Retrieve the GeoPackage
        remote_gpkg_path = result_data.get("gpkg_path")
        local_gpkg_path = os.path.join(temp_dir, "world_survey.gpkg")
        
        try:
            copy_from_env(remote_gpkg_path, local_gpkg_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve GeoPackage: {e}"}

        # 4. Inspect Data with SQLite
        try:
            conn = sqlite3.connect(local_gpkg_path)
            cursor = conn.cursor()
            
            # Helper to get code for city
            def get_code(city_name):
                cursor.execute("SELECT iso_code FROM world_capitals WHERE name = ?", (city_name,))
                row = cursor.fetchone()
                return row[0] if row else None

            # Check Tokyo
            tokyo_code = get_code("Tokyo")
            if tokyo_code == "JP":
                score += SCORE_TOKYO
                feedback_parts.append("Tokyo: Correct (JP).")
            else:
                feedback_parts.append(f"Tokyo: Incorrect (Found '{tokyo_code}', expected 'JP').")

            # Check Canberra
            canberra_code = get_code("Canberra")
            if canberra_code == "AU":
                score += SCORE_CANBERRA
                feedback_parts.append("Canberra: Correct (AU).")
            else:
                feedback_parts.append(f"Canberra: Incorrect (Found '{canberra_code}', expected 'AU').")

            # Check Brasilia
            brasilia_code = get_code("Brasilia")
            if brasilia_code == "BR":
                score += SCORE_BRASILIA
                feedback_parts.append("Brasilia: Correct (BR).")
            else:
                feedback_parts.append(f"Brasilia: Incorrect (Found '{brasilia_code}', expected 'BR').")

            # Integrity Check (Paris should still be FR)
            paris_code = get_code("Paris")
            if paris_code == "FR":
                score += SCORE_INTEGRITY
                feedback_parts.append("Data Integrity: Preserved.")
            else:
                feedback_parts.append(f"Data Integrity: Warning - Paris changed to '{paris_code}'.")

            conn.close()

        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"SQLite Verification Failed: {e}"}

    finally:
        shutil.rmtree(temp_dir)

    # Final decision
    passed = (score >= 90) # Requires all 3 cities correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }