#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_plastic_mesh_deformation_rig(traj, env_info, task_info):
    """
    Verify that the agent used the Plastic Tool to rig and animate a character.
    
    Verification relies on:
    1. Parsing the saved .tnz scene file for specific Plastic Tool XML tags (MeshLevel, PlasticSkeleton).
    2. Checking for the rendered output video.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_scene_path = metadata.get('expected_scene_path', '/home/ga/OpenToonz/output/slime_rig.tnz')
    min_video_size_kb = metadata.get('min_video_size_kb', 10)
    
    # Load task result JSON
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)
            
    score = 0
    feedback_parts = []
    
    # 2. Analyze Scene File (Structural Verification)
    scene_exists = task_result.get('scene_exists', False)
    scene_created = task_result.get('scene_created_during_task', False)
    
    has_mesh = False
    has_skeleton = False
    has_animation = False
    
    if scene_exists:
        score += 10
        feedback_parts.append("Scene file saved")
        
        # Copy the .tnz file for inspection
        tnz_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.tnz')
        try:
            copy_from_env(task_result.get('scene_path'), tnz_temp.name)
            
            # Read file content safely
            with open(tnz_temp.name, 'r', errors='ignore') as f:
                content = f.read()
                
            # Check for Plastic Tool artifacts in XML
            # Mesh Level detection
            if 'type="MeshLevel"' in content or '<meshId>' in content:
                has_mesh = True
                score += 30
                feedback_parts.append("Mesh Level detected")
            else:
                feedback_parts.append("No Mesh Level found in scene")

            # Skeleton detection
            if 'PlasticSkeletonDeformation' in content or 'plasticSkeleton' in content:
                has_skeleton = True
                score += 30
                feedback_parts.append("Plastic Skeleton detected")
            else:
                feedback_parts.append("No Plastic Skeleton found")
                
            # Animation detection (look for keyframes in plastic params)
            # Plastic params often look like <param name="angle" ...> <keyframe ...> </param> inside the skeleton node
            # We do a basic check for keyframes combined with skeleton existence
            if has_skeleton and ('<keyframe' in content or '<step' in content):
                has_animation = True
                score += 15
                feedback_parts.append("Animation keyframes detected")
            elif has_skeleton:
                feedback_parts.append("Skeleton found but no animation keyframes detected")
                
        except Exception as e:
            feedback_parts.append(f"Failed to analyze scene file: {e}")
        finally:
            if os.path.exists(tnz_temp.name):
                os.unlink(tnz_temp.name)
    else:
        feedback_parts.append("Scene file not found (cannot verify rigging structure)")

    # 3. Analyze Video Output
    video_exists = task_result.get('video_exists', False)
    video_size_bytes = task_result.get('video_size_bytes', 0)
    video_created = task_result.get('video_created_during_task', False)
    
    if video_exists:
        if video_size_bytes > min_video_size_kb * 1024:
            score += 15
            feedback_parts.append("Rendered video found")
        else:
            feedback_parts.append(f"Video found but too small (<{min_video_size_kb}KB)")
    else:
        feedback_parts.append("Rendered video not found")

    # 4. Final Scoring
    # Pass threshold: 60. 
    # Must have at least created the mesh and skeleton (30+30=60) OR mesh+video+animation etc.
    # Critical criteria: Must use Plastic Tool (Mesh + Skeleton).
    
    passed = score >= 60 and has_mesh and has_skeleton
    
    if not has_mesh or not has_skeleton:
        feedback_parts.append("FAILED: Did not use Plastic Tool (Mesh/Skeleton missing)")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }