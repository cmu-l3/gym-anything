#!/usr/bin/env python3
"""
Verifier for desk_lamp_armature_rig task.

Verifies:
1. Valid blend file saved.
2. Armature object created.
3. Correct 4 bones exist (Base, LowerArm, UpperArm, Head).
4. Correct bone hierarchy chain.
5. Lamp meshes parented to armature.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_desk_lamp_armature_rig(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback_parts = []
    
    # 1. File Check (10 pts)
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    # Check modification time to prevent using pre-made files (anti-gaming)
    task_start = result.get("task_start", 0)
    file_mtime = result.get("file_mtime", 0)
    if file_mtime <= task_start:
         feedback_parts.append("Warning: File timestamp indicates it wasn't modified during task")
    else:
         score += 10
         feedback_parts.append("File saved")

    analysis = result.get("analysis", {})
    armatures = analysis.get("armatures", [])
    
    # 2. Armature Exists (15 pts)
    if not armatures:
        feedback_parts.append("No armature found in scene")
    else:
        score += 15
        feedback_parts.append(f"Armature found: {armatures[0]['name']}")
        
        # We'll check the first armature found
        bones = armatures[0].get("bones", [])
        bone_map = {b["name"]: b for b in bones}
        
        # 3. Bone Names (20 pts - 5 per bone)
        required_bones = ["Base", "LowerArm", "UpperArm", "Head"]
        bones_found = 0
        for name in required_bones:
            if name in bone_map:
                bones_found += 1
        
        score += (bones_found * 5)
        feedback_parts.append(f"Bones found: {bones_found}/4")

        # 4. Hierarchy Chain (25 pts)
        # Chain: Base (root) -> LowerArm -> UpperArm -> Head
        chain_score = 0
        
        if "Base" in bone_map and bone_map["Base"]["parent"] is None:
            chain_score += 5
        
        if "LowerArm" in bone_map and bone_map["LowerArm"]["parent"] == "Base":
            chain_score += 5
            
        if "UpperArm" in bone_map and bone_map["UpperArm"]["parent"] == "LowerArm":
            chain_score += 5
            
        if "Head" in bone_map and bone_map["Head"]["parent"] == "UpperArm":
            chain_score += 10
            
        score += chain_score
        if chain_score == 25:
            feedback_parts.append("Bone hierarchy correct")
        else:
            feedback_parts.append(f"Bone hierarchy partial score: {chain_score}/25")

    # 5. Mesh Parenting (30 pts)
    meshes = analysis.get("meshes", {})
    mesh_score = 0
    target_meshes = ["LampBase", "LampLowerArm", "LampUpperArm", "LampHead"]
    
    parented_count = 0
    for name in target_meshes:
        m = meshes.get(name)
        if m and m.get("exists"):
            # Check if parented to ARMATURE or has ARMATURE modifier
            is_parented = (m.get("parent_type") == "ARMATURE") or ("ARMATURE" in m.get("modifiers", []))
            if is_parented:
                parented_count += 1
    
    # 7.5 points per mesh
    mesh_score = int(parented_count * 7.5)
    score += mesh_score
    feedback_parts.append(f"Meshes parented: {parented_count}/4")

    # Pass threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": analysis
    }