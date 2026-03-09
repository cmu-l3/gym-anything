#!/usr/bin/env python3
import json
import os
import base64
import re
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

def verify_extract_maven_snippet(traj, env_info, task_info):
    """
    Verifies that the agent extracted the correct Maven dependency snippet.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_group = metadata.get('expected_group_id', 'org.apache.commons')
    expected_artifact = metadata.get('expected_artifact_id', 'commons-lang3')
    expected_version = metadata.get('expected_version', '3.14.0')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Criterion 1: File Existence (20 pts)
    if result.get('output_exists'):
        score += 20
        feedback.append("Output file exists.")
    else:
        feedback.append("Output file '/home/ga/Desktop/maven_snippet.xml' NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Created during task (10 pts)
    if result.get('file_created_during_task'):
        score += 10
        feedback.append("File created during task.")
    else:
        feedback.append("Warning: File timestamp indicates it was not created during this session.")

    # Criterion 3: Content Verification (50 pts)
    content_b64 = result.get('content_base64', '')
    try:
        content = base64.b64decode(content_b64).decode('utf-8')
    except:
        content = ""

    # Normalize whitespace for flexible matching
    content_norm = re.sub(r'\s+', ' ', content).strip()
    
    checks_passed = 0
    
    # Check for Maven structure
    if '<dependency>' in content and '</dependency>' in content:
        score += 10
        checks_passed += 1
    else:
        feedback.append("Missing <dependency> tags.")

    # Check Group ID
    if expected_group in content:
        score += 15
        checks_passed += 1
    else:
        feedback.append(f"Missing groupId: {expected_group}")

    # Check Artifact ID
    if expected_artifact in content:
        score += 15
        checks_passed += 1
    else:
        feedback.append(f"Missing artifactId: {expected_artifact}")

    # Check Version
    if expected_version in content:
        score += 10
        checks_passed += 1
    else:
        feedback.append(f"Missing version: {expected_version}")

    # Criterion 4: VLM Trajectory Verification (20 pts)
    # Ensure they actually used the Artifactory UI
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        prompt = (
            "Review these screenshots of a user interacting with JFrog Artifactory. "
            "Did the user: "
            "1. Navigate to the artifact browser/tree view? "
            "2. Select the 'commons-lang3' artifact? "
            "3. View the 'Dependency Declaration' or 'Usage' tab? "
            "Respond with 'YES' if they navigated the UI to find the artifact info, or 'NO' otherwise."
        )
        vlm_resp = query_vlm(images=frames, prompt=prompt).get('response', '').upper()
        
        if "YES" in vlm_resp:
            score += 20
            feedback.append("VLM confirmed UI navigation.")
        else:
            feedback.append("VLM did not confirm correct UI navigation.")
    else:
        # Fallback if VLM not available, give partial credit if content is perfect
        if checks_passed == 4:
            score += 20
            feedback.append("VLM skipped, assuming success based on correct content.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }