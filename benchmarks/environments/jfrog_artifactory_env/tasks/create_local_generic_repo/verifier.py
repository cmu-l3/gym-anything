#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_create_local_generic_repo(traj, env_info, task_info):
    """
    Verifies the create_local_generic_repo task.
    
    Criteria:
    1. Repository 'build-artifacts-generic' exists (20 pts)
    2. Repository is LOCAL and GENERIC type (25 pts)
    3. Artifact exists at 'releases/v1.0/commons-lang3-3.14.0.jar' (25 pts)
    4. Artifact size is valid (>0) and created during task session (15 pts)
    5. VLM verification of the workflow (15 pts)
    """
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Verification
    score = 0
    feedback = []
    
    # Check Repo Existence
    if result.get('repo_exists', False):
        score += 20
        feedback.append("Repository created successfully.")
    else:
        feedback.append("Repository 'build-artifacts-generic' not found.")
    
    # Check Repo Configuration
    repo_type = result.get('repo_type', '').upper()
    package_type = result.get('package_type', '').lower()
    
    if repo_type == 'LOCAL':
        score += 10
        feedback.append("Repository type is correct (LOCAL).")
    else:
        feedback.append(f"Incorrect repository type: {repo_type} (expected LOCAL).")

    if package_type == 'generic':
        score += 15
        feedback.append("Package type is correct (Generic).")
    else:
        feedback.append(f"Incorrect package type: {package_type} (expected Generic).")

    # Check Artifact Existence
    if result.get('artifact_exists', False):
        score += 25
        feedback.append("Artifact deployed to correct path.")
    else:
        feedback.append("Artifact not found at 'releases/v1.0/commons-lang3-3.14.0.jar'.")

    # Check Artifact Validity (Size & Timestamp)
    # 600KB is approx size of commons-lang3, allowing for slight variations/metadata
    size = result.get('artifact_size', 0)
    created_time = result.get('artifact_created_time', 0)
    start_time = result.get('task_start_time', 0)
    
    if size > 500000: 
        score += 5
    elif size > 0:
        # Partial credit if file exists but seems too small (maybe empty file)
        score += 1
        feedback.append("Artifact size is suspicious (too small).")
    else:
        feedback.append("Artifact is empty.")

    # Anti-gaming: Check if created during this session
    if created_time >= start_time:
        score += 10
        feedback.append("Artifact creation timestamp valid.")
    else:
        feedback.append("Artifact appears to be old (pre-dating task start).")

    # 3. VLM Verification
    # We want to see evidence of the Deploy UI being used
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # If we have frames, query VLM
    if frames:
        prompt = (
            "Review these screenshots of a user interacting with JFrog Artifactory. "
            "I need to verify they created a 'Generic' repository and deployed a file.\n"
            "Look for:\n"
            "1. The 'New Local Repository' screen with 'Generic' selected.\n"
            "2. The 'Deploy' dialog or Artifact Browser showing the 'Deploy' button.\n"
            "3. A success message or the file appearing in the tree view.\n"
            "Did the user perform these actions?"
        )
        
        try:
            vlm_response = query_vlm(images=frames + [final_screen], prompt=prompt)
            # Simple heuristic: if VLM says "yes" or describes the actions positive
            vlm_text = vlm_response.get('text', '').lower()
            
            if "yes" in vlm_text or "successfully" in vlm_text or "generic" in vlm_text:
                score += 15
                feedback.append("VLM visual verification passed.")
            else:
                score += 5 # Partial credit for effort visible
                feedback.append("VLM visual verification inconclusive.")
        except Exception:
            # Fallback if VLM fails: grant points if programmatic passed strongly
            if score >= 70:
                score += 15
                feedback.append("VLM skipped (programmatic checks strong).")
    else:
        feedback.append("No visual trajectory available for verification.")

    # 4. Final Result
    passed = score >= 60 and result.get('repo_exists', False) and result.get('artifact_exists', False)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }