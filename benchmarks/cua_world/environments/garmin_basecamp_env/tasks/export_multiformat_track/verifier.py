#!/usr/bin/env python3
"""
Verifier for export_multiformat_track task.

Verification Strategy:
1. Validates KML file exists, was created during task, and has correct XML structure (no GPX mixup).
2. Validates CSV file exists, was created during task, is plain text (no XML), and has >50 rows.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_multiformat_track(traj, env_info, task_info):
    """
    Verifies that BaseCamp track data was correctly exported into both KML and CSV formats.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    kml_exists = result.get('kml_exists', False)
    kml_fresh = result.get('kml_fresh', False)
    kml_content = result.get('kml_content', "") or ""
    
    csv_exists = result.get('csv_exists', False)
    csv_fresh = result.get('csv_fresh', False)
    csv_content = result.get('csv_content', "") or ""
    
    # -----------------------------------------------------
    # 1. KML Verification (50 points total)
    # -----------------------------------------------------
    kml_valid = False
    if kml_exists and kml_fresh:
        score += 10
        feedback_parts.append("KML file created successfully")
        
        content_lower = kml_content.lower()
        if "<kml" in content_lower and ("<linestring" in content_lower or "<coordinates>" in content_lower):
            if "<gpx" not in content_lower:
                score += 40
                kml_valid = True
                feedback_parts.append("KML format is valid")
            else:
                feedback_parts.append("KML contains GPX tags (incorrect 'Save as type' selection)")
        else:
            feedback_parts.append("KML missing spatial data tags")
    elif kml_exists:
        feedback_parts.append("KML exists but is stale (not created during task)")
    else:
        feedback_parts.append("KML file not found")
        
    # -----------------------------------------------------
    # 2. CSV Verification (50 points total)
    # -----------------------------------------------------
    csv_valid = False
    if csv_exists and csv_fresh:
        score += 10
        feedback_parts.append("CSV file created successfully")
        
        content_lower = csv_content.lower()
        if "<gpx" not in content_lower and "<kml" not in content_lower:
            if "," in csv_content:
                score += 10
                
                # Check line count to distinguish between trackpoints vs list summary
                lines = [line for line in csv_content.strip().split('\n') if line.strip()]
                if len(lines) > 50:
                    score += 30
                    csv_valid = True
                    feedback_parts.append(f"CSV format valid and contains {len(lines)} rows (track points)")
                else:
                    feedback_parts.append(f"CSV incomplete: only {len(lines)} rows found. Agent exported list summary instead of track points.")
            else:
                feedback_parts.append("CSV missing comma delimiters")
        else:
            feedback_parts.append("CSV contains XML tags (incorrect 'Save as type' selection)")
    elif csv_exists:
        feedback_parts.append("CSV exists but is stale (not created during task)")
    else:
        feedback_parts.append("CSV file not found")

    # Determine final pass/fail
    passed = kml_valid and csv_valid and score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }