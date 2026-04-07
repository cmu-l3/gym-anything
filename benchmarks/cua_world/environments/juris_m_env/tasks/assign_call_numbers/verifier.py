#!/usr/bin/env python3
"""
Verifier for assign_call_numbers task.

Scoring Criteria (100 points total):
1. Brown v. Board Call Number (20 pts): KF4155 .B76 1954
2. Miranda v. Arizona Call Number (20 pts): KF9625 .M57 1966
3. Marbury v. Madison Call Number (20 pts): KF4541 .M37 1803
4. Modification Check (10 pts): Items were modified during the task
5. VLM Verification (30 pts):
   - 15 pts: Trajectory shows detailed item pane (Info tab)
   - 15 pts: Trajectory shows interaction with library list

Pass Threshold: 60 points
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_call_numbers(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that call numbers were correctly assigned to the three cases."""
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON
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
            "feedback": f"Could not retrieve export result: {e}. Was the task completed?",
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    score = 0
    feedback = []
    
    items = result.get("items", {})
    
    # 1. Check Brown v. Board (20 pts)
    brown = items.get("brown", {})
    brown_cn = brown.get("call_number", "")
    expected_brown = "KF4155 .B76 1954"
    
    if brown_cn == expected_brown:
        score += 20
        feedback.append("Brown v. Board call number correct (+20)")
    elif brown_cn and "KF4155" in brown_cn:
        score += 10
        feedback.append(f"Brown v. Board call number partial match (+10, got '{brown_cn}')")
    else:
        feedback.append(f"Brown v. Board incorrect (expected '{expected_brown}', got '{brown_cn}')")

    # 2. Check Miranda v. Arizona (20 pts)
    miranda = items.get("miranda", {})
    miranda_cn = miranda.get("call_number", "")
    expected_miranda = "KF9625 .M57 1966"
    
    if miranda_cn == expected_miranda:
        score += 20
        feedback.append("Miranda v. Arizona call number correct (+20)")
    elif miranda_cn and "KF9625" in miranda_cn:
        score += 10
        feedback.append(f"Miranda v. Arizona call number partial match (+10, got '{miranda_cn}')")
    else:
        feedback.append(f"Miranda v. Arizona incorrect (expected '{expected_miranda}', got '{miranda_cn}')")

    # 3. Check Marbury v. Madison (20 pts)
    marbury = items.get("marbury", {})
    marbury_cn = marbury.get("call_number", "")
    expected_marbury = "KF4541 .M37 1803"
    
    if marbury_cn == expected_marbury:
        score += 20
        feedback.append("Marbury v. Madison call number correct (+20)")
    elif marbury_cn and "KF4541" in marbury_cn:
        score += 10
        feedback.append(f"Marbury v. Madison call number partial match (+10, got '{marbury_cn}')")
    else:
        feedback.append(f"Marbury v. Madison incorrect (expected '{expected_marbury}', got '{marbury_cn}')")

    # 4. Modification Check (10 pts)
    # Check if ANY of the correct items were modified during the task
    modified_count = 0
    for key in ["brown", "miranda", "marbury"]:
        if items.get(key, {}).get("modified_during_task", False):
            modified_count += 1
    
    if modified_count >= 3:
        score += 10
        feedback.append("All items modified during task (+10)")
    elif modified_count > 0:
        score += 5
        feedback.append(f"Some items modified during task ({modified_count}/3) (+5)")
    else:
        feedback.append("No items modified during task session")

    # 5. VLM Verification (30 pts)
    # We use trajectory frames to verify the workflow
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_response = query_vlm(
                images=frames,
                prompt="""
                Analyze these screenshots of Juris-M reference manager software.
                I am looking for evidence that the user was editing bibliographic metadata.
                
                Look for:
                1. The 'Info' tab being active in the right-hand pane.
                2. Fields like 'Call Number', 'Case Name', or 'Court' being visible/edited.
                3. The user selecting items from the center list.
                
                Return JSON:
                {
                    "info_tab_visible": boolean,
                    "fields_visible": boolean,
                    "item_selection_visible": boolean,
                    "confidence": "high/medium/low"
                }
                """
            )
            
            # Simple parsing of VLM JSON response (robustness handled by gym_anything usually, but explicit here)
            import json
            try:
                # Handle potential markdown code blocks in response
                clean_json = vlm_response.replace("