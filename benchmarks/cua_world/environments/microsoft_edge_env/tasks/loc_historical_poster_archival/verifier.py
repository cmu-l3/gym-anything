#!/usr/bin/env python3
import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_loc_archival(traj, env_info, task_info):
    """
    Verifies the Library of Congress Historical Poster Archival task.
    
    Scoring Criteria:
    1. Directory Created (10 pts)
    2. Images Downloaded (30 pts) - 10 pts per valid JPEG > 50KB (max 3)
    3. Manifest Exists (10 pts)
    4. Manifest Valid JSON (15 pts)
    5. Data Completeness (15 pts) - Correct keys in manifest
    6. Integrity Check (10 pts) - Manifest filenames match actual files
    7. Source Verification (10 pts) - History shows LOC visits
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment interface error (copy_from_env missing)"}

    # Retrieve result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Directory Check
    if result.get("dir_exists"):
        score += 10
        feedback.append("Directory ~/Pictures/WPA_Travel created (+10).")
    else:
        feedback.append("Directory ~/Pictures/WPA_Travel NOT found.")

    # 2. Image Count
    valid_images = result.get("valid_images", [])
    image_count = len(valid_images)
    points_per_image = 10
    image_score = min(3, image_count) * points_per_image
    score += image_score
    if image_count >= 3:
        feedback.append(f"Found {image_count} valid JPEG images (+30).")
    else:
        feedback.append(f"Found {image_count}/3 valid JPEG images (+{image_score}).")

    # 3. Manifest Existence
    if result.get("manifest_exists"):
        score += 10
        feedback.append("Manifest file found (+10).")
    else:
        feedback.append("Manifest file missing.")

    # 4. Manifest Validity
    manifest_content = result.get("manifest_content", [])
    if result.get("manifest_valid_json") and isinstance(manifest_content, list):
        score += 15
        feedback.append("Manifest is valid JSON array (+15).")
    elif result.get("manifest_exists"):
        feedback.append("Manifest is invalid JSON or not a list.")

    # 5. Data Completeness (Keys)
    # Only check if manifest is valid and has entries
    if result.get("manifest_valid_json") and len(manifest_content) >= 3:
        if result.get("manifest_keys_check"):
            score += 15
            feedback.append("Manifest entries contain all required keys (+15).")
        else:
            feedback.append("Manifest entries missing required keys (title, year, url, filename).")
    elif len(manifest_content) < 3:
        feedback.append(f"Manifest has fewer than 3 entries ({len(manifest_content)}).")

    # 6. Integrity Check
    if result.get("files_in_manifest_exist") and len(manifest_content) > 0:
        score += 10
        feedback.append("Files referenced in manifest exist on disk (+10).")
    elif result.get("manifest_valid_json"):
         feedback.append("Filenames in manifest do not match files on disk.")

    # 7. Source Verification (History)
    if result.get("loc_visits_detected"):
        score += 10
        feedback.append("Library of Congress visits detected (+10).")
    else:
        feedback.append("No history of visiting loc.gov found.")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }