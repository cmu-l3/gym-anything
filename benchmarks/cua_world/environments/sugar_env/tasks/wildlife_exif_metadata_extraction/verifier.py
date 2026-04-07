#!/usr/bin/env python3
"""Verifier for wildlife_exif_metadata_extraction task.

Verifies that:
1. An automation script (.sh or .py) was created.
2. The output CSV file exists and contains the correct header.
3. The CSV contains 3 rows of data.
4. The EXIF camera models map correctly to the filenames.
5. The date/time strings were successfully extracted.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wildlife_exif_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/exif_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Automation script created (Anti-gaming check) (10 pts)
    script_exists = result.get('script_exists', False)
    script_size = result.get('script_size', 0)
    
    if script_exists and script_size > 20:
        score += 10
        feedback.append("Automation script found")
    else:
        feedback.append("FAIL: No valid extract_exif.sh/py automation script found")
        # Early exit: the agent must write a script, not just hardcode a text file
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: CSV File Exists (10 pts)
    csv_exists = result.get('csv_exists', False)
    if csv_exists:
        score += 10
        feedback.append("photo_metadata.csv generated")
    else:
        feedback.append("FAIL: photo_metadata.csv not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 3: Exact Header Match (10 pts)
    header = result.get('header', [])
    expected_header = "Filename,Camera_Model,Date_Taken"
    actual_header_str = ",".join(header)
    
    if actual_header_str.lower() == expected_header.lower():
        score += 10
        feedback.append("Header matches exactly")
    elif len(header) >= 3:
        score += 5
        feedback.append(f"Header roughly matches: {actual_header_str}")
    else:
        feedback.append("Header missing or incorrect")

    # Criterion 4: Row count matches expected files (10 pts)
    rows = result.get('rows', [])
    if len(rows) == 3:
        score += 10
        feedback.append("Contains exactly 3 data rows")
    elif len(rows) > 0:
        score += 5
        feedback.append(f"Contains {len(rows)} data rows (expected 3)")
    else:
        feedback.append("CSV contains no data rows")

    # Assess individual rows robustly (ignoring strict column order in case they messed up the header mapping)
    redpanda_cam = False
    monarch_cam = False
    seaturtle_cam = False
    dates_found = 0

    for row in rows:
        row_str = " ".join(row).lower()
        
        # Check Date formatting (typical EXIF format uses ':' or '-' alongside numbers)
        if ':' in row_str or '-' in row_str:
            dates_found += 1

        if 'redpanda' in row_str:
            if 'canon' in row_str:
                redpanda_cam = True
        elif 'monarch' in row_str:
            if 'nikon' in row_str:
                monarch_cam = True
        elif 'seaturtle' in row_str:
            if 'canon' in row_str:
                seaturtle_cam = True

    # Criterion 5, 6, 7: Camera Models mapped correctly (15 pts each)
    if redpanda_cam:
        score += 15
        feedback.append("RedPanda mapped to Canon")
    if monarch_cam:
        score += 15
        feedback.append("Monarch mapped to Nikon")
    if seaturtle_cam:
        score += 15
        feedback.append("SeaTurtle mapped to Canon")

    # Criterion 8: Dates correctly extracted (15 pts)
    if dates_found >= 3:
        score += 15
        feedback.append("Timestamps extracted successfully")
    elif dates_found > 0:
        score += 5
        feedback.append("Partial timestamps extracted")

    # Pass condition: Score >= 70, script exists, and at least 2 cameras correctly mapped
    passed = score >= 70 and script_exists and (sum([redpanda_cam, monarch_cam, seaturtle_cam]) >= 2)

    if passed:
        feedback.append("SUCCESS: EXIF extraction automated correctly")
    else:
        feedback.append(f"FAILED: Score {score}/100")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "script_exists": script_exists,
            "csv_exists": csv_exists,
            "header_correct": actual_header_str.lower() == expected_header.lower(),
            "cameras_mapped": sum([redpanda_cam, monarch_cam, seaturtle_cam])
        }
    }