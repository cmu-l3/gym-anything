#!/usr/bin/env python3
import json
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_corridor_mode(traj, env_info, task_info):
    """
    Verify that cameras are rotated correctly and renamed.
    
    Rubric:
    - Server Room Camera: Rotation 90 (25pts), Renamed (15pts)
    - Entrance Camera: Rotation 270 (25pts), Renamed (15pts)
    - Other cameras: Untouched (20pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load artifacts
    import tempfile
    
    # Helper to load JSON from container
    def load_json_from_env(path):
        tf = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(path, tf.name)
            with open(tf.name, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load {path}: {e}")
            return None
        finally:
            if os.path.exists(tf.name):
                os.unlink(tf.name)

    # 1. Load Result Metadata
    result_meta = load_json_from_env("/tmp/task_result.json")
    if not result_meta:
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result metadata"}

    # 2. Load Initial Map (Name -> ID)
    initial_map = load_json_from_env(result_meta.get("initial_map_path"))
    if not initial_map:
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve initial camera state"}

    # 3. Load Final State (List of Devices)
    final_devices_list = load_json_from_env(result_meta.get("final_state_path"))
    if not final_devices_list:
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve final device state"}

    # Convert list to dict by ID for easy lookup
    final_devices = {d.get('id'): d for d in final_devices_list}

    score = 0
    feedback = []

    # Define targets
    targets = [
        {
            "original_name": "Server Room Camera",
            "required_rotation": "90",
            "required_suffix": " [Corridor]",
            "points_rotation": 25,
            "points_rename": 15
        },
        {
            "original_name": "Entrance Camera",
            "required_rotation": "270",
            "required_suffix": " [Corridor]",
            "points_rotation": 25,
            "points_rename": 15
        }
    ]

    # Track processed IDs to verify "Others Unaffected"
    processed_ids = set()

    # --- VERIFY TARGETS ---
    for target in targets:
        orig_name = target["original_name"]
        cam_id = initial_map.get(orig_name)
        
        if not cam_id:
            feedback.append(f"❌ Setup error: {orig_name} not found in initial state.")
            continue
            
        processed_ids.add(cam_id)
        device = final_devices.get(cam_id)
        
        if not device:
            feedback.append(f"❌ Camera {orig_name} seems to have been deleted.")
            continue

        # Check Rotation
        # Rotation is usually in parameters.rotation or sometimes a top-level property depending on API version
        # The setup script assumes parameters.rotation. We check there.
        # Note: values are strings "0", "90", "180", "270"
        params = device.get("parameters", {})
        rotation = str(params.get("rotation", "0"))
        
        if rotation == target["required_rotation"]:
            score += target["points_rotation"]
            feedback.append(f"✅ {orig_name} rotation correct ({rotation}°).")
        else:
            feedback.append(f"❌ {orig_name} rotation is {rotation}°, expected {target['required_rotation']}°.")

        # Check Rename
        curr_name = device.get("name", "")
        expected_suffix = target["required_suffix"]
        
        if curr_name.endswith(expected_suffix):
            score += target["points_rename"]
            feedback.append(f"✅ {orig_name} renamed correctly.")
        else:
            feedback.append(f"❌ {orig_name} name '{curr_name}' missing suffix '{expected_suffix}'.")

    # --- VERIFY OTHERS UNAFFECTED ---
    others_violated = False
    for name, cam_id in initial_map.items():
        if cam_id in processed_ids:
            continue
            
        device = final_devices.get(cam_id)
        if not device: 
            continue # Deleted?
            
        params = device.get("parameters", {})
        rotation = str(params.get("rotation", "0"))
        curr_name = device.get("name", "")
        
        if rotation != "0":
            others_violated = True
            feedback.append(f"⚠️ Unrelated camera '{name}' was rotated to {rotation}°.")
        
        if " [Corridor]" in curr_name:
            others_violated = True
            feedback.append(f"⚠️ Unrelated camera '{name}' was renamed.")

    if not others_violated:
        score += 20
        feedback.append("✅ Other cameras remained untouched.")
    else:
        feedback.append("❌ Collateral damage detected on other cameras.")

    # Final tally
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }