#!/usr/bin/env python3
"""
Verifier for tag_high_latitude_infra task.
Checks if specific high-latitude capital cities in the GeoPackage 
have been updated with the correct attribute text.
"""

import json
import sqlite3
import tempfile
import os
import shutil
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth data
# Cities > 55.0 N in the standard world_capitals dataset
NORTHERN_CAPITALS = {
    'Reykjavik',   # ~64 N
    'Helsinki',    # ~60 N
    'Oslo',        # ~59 N
    'Stockholm',   # ~59 N
    'Tallinn',     # ~59 N
    'Riga',        # ~56 N
    'Copenhagen',  # ~55.6 N
    'Moscow'       # ~55.7 N
}

# Target string
TARGET_TEXT = "Winter Protocol Active"

def verify_tag_high_latitude_infra(traj, env_info, task_info):
    """
    Verify that northern capitals have been tagged correctly in the GeoPackage.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Host copy function not available"}

    feedback_parts = []
    score = 0
    
    # Create temporary directory for analysis
    with tempfile.TemporaryDirectory() as temp_dir:
        local_result_json = os.path.join(temp_dir, "task_result.json")
        local_gpkg = os.path.join(temp_dir, "world_survey.gpkg")
        
        # 1. Retrieve Result JSON and GeoPackage
        try:
            copy_from_env("/sdcard/task_result.json", local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
            
            gpkg_path = result_data.get("gpkg_path")
            copy_from_env(gpkg_path, local_gpkg)
            
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve task data: {str(e)}"
            }

        # 2. Check File Modification
        if result_data.get("file_modified", False):
            score += 10
            feedback_parts.append("GeoPackage file modified.")
        else:
            feedback_parts.append("GeoPackage file NOT modified (timestamps unchanged).")
            # If file wasn't modified, they definitely didn't pass, but we continue check to give detailed feedback

        # 3. Analyze Database Content
        try:
            conn = sqlite3.connect(local_gpkg)
            cursor = conn.cursor()
            
            # Query all capitals
            # Note: Table name usually matches layer name in these datasets. 
            # If uncertain, we could query sqlite_master, but 'world_capitals' is standard here.
            cursor.execute("SELECT name, description FROM world_capitals")
            rows = cursor.fetchall()
            conn.close()
            
            correctly_tagged = 0
            incorrectly_tagged = 0
            missed_tags = 0
            total_northern = 0
            
            for name, description in rows:
                clean_name = name.strip()
                # Check description handling None
                desc_text = description.strip() if description else ""
                
                is_target_city = clean_name in NORTHERN_CAPITALS
                has_target_text = TARGET_TEXT.lower() in desc_text.lower()
                is_exact_match = TARGET_TEXT == desc_text
                
                if is_target_city:
                    total_northern += 1
                    if has_target_text:
                        if is_exact_match:
                            correctly_tagged += 1
                        else:
                            # Partial credit for typo or extra text? 
                            # Instructions said "exactly", but we can be lenient in scoring logic if needed.
                            # For now, strict on string presence, strict on points.
                            correctly_tagged += 0.8 # Minor penalty for extra whitespace/text
                            feedback_parts.append(f"City {clean_name} marked but text not exact match ('{desc_text}').")
                    else:
                        missed_tags += 1
                else:
                    if has_target_text:
                        incorrectly_tagged += 1
                        feedback_parts.append(f"Incorrectly marked southern city: {clean_name}")

            # Scoring Logic
            # Max 50 points for Coverage (Recall)
            if total_northern > 0:
                coverage_score = (correctly_tagged / total_northern) * 50
                score += coverage_score
            
            # Max 40 points for Precision (Penalty for false positives)
            # Deduct 10 points per false positive
            penalty = incorrectly_tagged * 10
            precision_score = max(0, 40 - penalty)
            score += precision_score
            
            feedback_parts.append(f"Correctly tagged: {int(correctly_tagged)}/{total_northern}")
            if incorrectly_tagged > 0:
                feedback_parts.append(f"False positives: {incorrectly_tagged}")
                
        except sqlite3.Error as e:
            return {
                "passed": False,
                "score": score,
                "feedback": f"Database analysis failed (corrupt file?): {str(e)}"
            }

    # Final Pass Determination
    # Threshold: Need score >= 90 (allows basically no errors)
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback_parts)
    }