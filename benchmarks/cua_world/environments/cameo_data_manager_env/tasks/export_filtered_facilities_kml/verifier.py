#!/usr/bin/env python3
"""
Verifier for export_filtered_facilities_kml task.

Verifies:
1. KML file exists and was created during the task.
2. KML contains the 2 target facilities (Riverview).
3. KML does NOT contain the distractor facility (Hilltop) -> Proves filtering.
4. KML contains correct geospatial coordinates.
"""

import json
import os
import sys
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_filtered_facilities_kml(traj, env_info, task_info):
    """
    Verify the KML export task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_path', r"C:\Users\Docker\Desktop\riverview_facilities.kml")
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/workspace/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Check file existence and timing
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "KML output file not found on Desktop."}
        
    score += 10
    feedback_parts.append("File exists")
    
    if result_data.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("WARNING: File timestamp predates task start")
        
    # 2. Get the Actual KML Content
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    kml_content = ""
    try:
        # Convert Windows path to something copy_from_env handles if needed, 
        # but usually it takes the absolute path inside the guest.
        copy_from_env(expected_path, temp_kml.name)
        with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
            kml_content = f.read()
    except Exception as e:
        feedback_parts.append(f"Failed to copy KML content: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
            
    # 3. Analyze Content
    # KML parsing can be tricky with namespaces, so we'll do robust string checking first
    # then XML parsing if possible.
    
    targets = metadata.get('target_facilities', [])
    distractor = metadata.get('distractor_facility', "")
    
    # Check Targets
    targets_found = 0
    for t in targets:
        if t in kml_content:
            targets_found += 1
            score += 20
            feedback_parts.append(f"Found target: {t}")
        else:
            feedback_parts.append(f"MISSING target: {t}")
            
    # Check Distractor (Filtering Verification)
    if distractor in kml_content:
        feedback_parts.append(f"FAILED: Distractor '{distractor}' found in export (Filtering failed)")
    else:
        score += 30
        feedback_parts.append(f"Distractor correctly excluded")
        
    # Check Coordinates
    # Look for lat/long strings roughly in the content
    # Riverview Water: 29.7001, -95.3001
    coords_found = 0
    if "29.7001" in kml_content and "-95.3001" in kml_content:
        coords_found += 1
    if "29.7002" in kml_content and "-95.3002" in kml_content:
        coords_found += 1
        
    if coords_found == 2:
        score += 10
        feedback_parts.append("Coordinates verified")
    elif coords_found == 1:
        score += 5
        feedback_parts.append("Partial coordinates found")
    else:
        feedback_parts.append("Coordinates not found in KML")

    # Final logic
    passed = score >= 90  # Strict pass: Must have filtering correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }