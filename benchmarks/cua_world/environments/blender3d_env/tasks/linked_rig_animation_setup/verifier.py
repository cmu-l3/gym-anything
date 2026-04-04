#!/usr/bin/env python3
import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_linked_rig_animation(traj, env_info, task_info):
    """
    Verify the linked rig animation task.
    Criteria:
    1. Output file exists and modified.
    2. Rig is Linked (via Library Override), NOT Appended.
    3. Rig has Library Override active.
    4. Rig is posed (bones moved).
    5. Keyframes exist.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback = []
    
    # Check 1: File existence (10 pts)
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    if not result.get("file_created_during_task", False):
        feedback.append("Warning: File timestamp suggests it wasn't modified during task.")
    else:
        score += 10
        feedback.append("File saved successfully.")

    analysis = result.get("analysis", {})
    
    if not analysis.get("rig_found", False):
        return {"passed": False, "score": score, "feedback": "No armature found in the scene."}

    # Check 2: Linked vs Appended (30 pts)
    # Correct state: has_override=True AND is_linked=True (implied by override referencing library)
    # Wrong state: is_appended=True
    
    if analysis.get("is_appended", False):
        feedback.append("❌ Rig was Appended (local copy). Task required Linking.")
    elif analysis.get("has_override", False):
        score += 30
        feedback.append("✅ Rig is Linked with Library Override.")
    elif analysis.get("is_linked", False):
        feedback.append("⚠️ Rig is Linked but missing Library Override (cannot be animated).")
        score += 15
    else:
        feedback.append("❌ Rig status unclear (likely local created from scratch).")

    # Check 3: Library Override (30 pts)
    # Already checked above somewhat, but specific points for editable state
    if analysis.get("has_override", False):
        score += 30
        feedback.append("✅ Library Override active.")
    else:
        feedback.append("❌ No Library Override found.")

    # Check 4: Posed (15 pts)
    if analysis.get("is_posed", False):
        score += 15
        feedback.append("✅ Rig has been posed.")
    else:
        feedback.append("❌ Rig is still in rest pose.")

    # Check 5: Keyframes (15 pts)
    if analysis.get("has_keyframes", False):
        score += 15
        feedback.append("✅ Keyframes found.")
    else:
        feedback.append("❌ No animation keyframes found.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }