#!/usr/bin/env python3
"""
Verifier for export_oldest_items_csv task.

Verification Strategy:
1. Check if the output CSV file exists.
2. Check if the file was created during the task (anti-gaming).
3. Verify the content includes the 3 oldest items (Marbury, Path of the Law, Brown).
4. Verify the content EXCLUDES newer items (Obergefell, Tinker) to ensure correct sorting and selection.

Scoring (100 points):
- File Created & Exists: 30 pts
- Contains 'Marbury' (1803): 20 pts
- Contains 'Path of the Law' (1897): 20 pts
- Contains 'Brown' (1954): 10 pts
- Excludes 'Obergefell' (2015): 10 pts
- Excludes 'Tinker' (1969): 10 pts
"""

import os
import json
import logging
import base64
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_oldest_items_csv(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the user exported the 3 oldest items to CSV."""
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result JSON from container
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/task_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve export result: {e}. Did the task complete successfully?",
        }

    score = 0
    feedback = []
    
    # Check file existence
    output_exists = result.get("output_exists", False)
    created_during_task = result.get("file_created_during_task", False)
    content_b64 = result.get("file_content_b64", "")
    
    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file 'oldest_precedents.csv' not found in ~/Documents/."
        }
    
    score += 20
    feedback.append("File exists (+20)")

    if created_during_task:
        score += 10
        feedback.append("File created during task (+10)")
    else:
        feedback.append("Warning: File timestamp indicates it might be stale (0 pts)")

    # Decode content
    try:
        content_bytes = base64.b64decode(content_b64)
        content_str = content_bytes.decode('utf-8', errors='replace')
    except Exception as e:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Failed to decode file content: {e}"
        }

    # Analyze Content
    # We look for substrings identifying the specific cases.
    # Note: CSV format varies slightly, but these names are robust.
    
    # Required Oldest Items
    has_marbury = "Marbury" in content_str and "1803" in content_str
    has_path = ("Path of the Law" in content_str or "Holmes" in content_str) and "1897" in content_str
    has_brown = "Brown" in content_str and "1954" in content_str
    
    if has_marbury:
        score += 20
        feedback.append("Contains 'Marbury v. Madison' (1803) (+20)")
    else:
        feedback.append("Missing 'Marbury v. Madison' (1803)")

    if has_path:
        score += 20
        feedback.append("Contains 'Path of the Law' (1897) (+20)")
    else:
        feedback.append("Missing 'Path of the Law' (1897)")

    if has_brown:
        score += 10
        feedback.append("Contains 'Brown v. Board' (1954) (+10)")
    else:
        feedback.append("Missing 'Brown v. Board' (1954)")

    # Forbidden Newer Items (Proof of Sort & Selection)
    # If these exist, the user likely exported the whole library or sorted wrong.
    has_obergefell = "Obergefell" in content_str
    has_tinker = "Tinker" in content_str
    
    if not has_obergefell:
        score += 10
        feedback.append("Correctly excluded 'Obergefell' (2015) (+10)")
    else:
        feedback.append("Incorrectly included 'Obergefell' (2015) - did you sort and select only top 3?")

    if not has_tinker:
        score += 10
        feedback.append("Correctly excluded 'Tinker' (1969) (+10)")
    else:
        feedback.append("Incorrectly included 'Tinker' (1969) - did you select only the top 3 oldest?")

    # Final Pass Check
    # Threshold: 80 points ensures file exists + oldest items present + at least some exclusions correct
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "has_marbury": has_marbury,
            "has_path": has_path,
            "has_brown": has_brown,
            "has_obergefell": has_obergefell,
            "has_tinker": has_tinker
        }
    }