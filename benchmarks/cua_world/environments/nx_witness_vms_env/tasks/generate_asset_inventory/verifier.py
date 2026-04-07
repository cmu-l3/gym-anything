#!/usr/bin/env python3
"""
Verifier for generate_asset_inventory task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import VLM utils from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_asset_inventory(traj, env_info, task_info):
    """
    Verifies the system inventory JSON report.
    
    Criteria:
    1. File exists and is valid JSON (10 pts)
    2. Required structure/keys present (10 pts)
    3. Data accuracy vs Ground Truth (System, Cameras, Users, Servers) (40 pts)
    4. Summary counts match detail arrays (Internal Consistency) (10 pts)
    5. No sensitive data (password hashes) leaked (10 pts)
    6. Timestamp validity (5 pts)
    7. VLM: Verification of work (15 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    required_keys = metadata.get('required_keys', ["report_generated_at", "system", "servers", "cameras", "users", "layouts", "summary"])
    sensitive_patterns = metadata.get('sensitive_patterns', ["passwordHash", "cryptSha512Hash", "digest", "token"])

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    meta = result_data.get('meta', {})
    agent_output = result_data.get('agent_output', {})
    ground_truth = result_data.get('ground_truth', {})

    score = 0
    feedback = []

    # CRITERION 1: File Existence & JSON Validity (10 pts)
    if meta.get('output_exists') and meta.get('file_created_during_task'):
        if "error" in agent_output:
             feedback.append(f"❌ JSON Invalid: {agent_output.get('error')}")
        else:
            score += 10
            feedback.append("✅ Report file created and valid JSON")
    else:
        return {"passed": False, "score": 0, "feedback": "❌ Output file not found or not created during task"}

    # CRITERION 2: Structure & Keys (10 pts)
    missing_keys = [k for k in required_keys if k not in agent_output]
    if not missing_keys:
        score += 10
        feedback.append("✅ All top-level keys present")
    else:
        feedback.append(f"❌ Missing keys: {', '.join(missing_keys)}")

    # CRITERION 3: Data Accuracy (40 pts)
    # Check System Name (5 pts)
    gt_sys_name = ground_truth.get('system', {}).get('systemName', 'GymAnythingVMS')
    agent_sys = agent_output.get('system', {})
    agent_sys_name = agent_sys.get('systemName') or agent_sys.get('name')
    if agent_sys_name and agent_sys_name == gt_sys_name:
        score += 5
    else:
        feedback.append(f"⚠️ System Name mismatch (Expected: {gt_sys_name})")

    # Check Counts (Camera, User, Server, Layout) (20 pts)
    # We allow slight mismatches due to timing, but generally should match
    gt_cams = len(ground_truth.get('cameras', []))
    gt_users = len(ground_truth.get('users', []))
    
    agent_cams = len(agent_output.get('cameras', []))
    agent_users = len(agent_output.get('users', []))

    if agent_cams == gt_cams: score += 10
    else: feedback.append(f"⚠️ Camera count mismatch (Gt: {gt_cams}, Agent: {agent_cams})")

    if agent_users >= gt_users: score += 10 # Agent might find system users
    else: feedback.append(f"⚠️ User count mismatch (Gt: {gt_users}, Agent: {agent_users})")

    # Check Content Freshness/Realness (15 pts)
    # Verify at least one camera name matches
    gt_cam_names = {c.get('name') for c in ground_truth.get('cameras', [])}
    agent_cam_names = {c.get('name') for c in agent_output.get('cameras', [])}
    common_cams = gt_cam_names.intersection(agent_cam_names)
    
    if len(common_cams) > 0:
        score += 15
        feedback.append(f"✅ Verified {len(common_cams)} camera names against live system")
    else:
        feedback.append("❌ No matching camera names found")

    # CRITERION 4: Internal Consistency (Summary vs Arrays) (10 pts)
    summary = agent_output.get('summary', {})
    consistent = True
    if summary.get('total_cameras') != agent_cams: consistent = False
    if summary.get('total_users') != agent_users: consistent = False
    
    if consistent and summary:
        score += 10
        feedback.append("✅ Summary section matches details")
    elif summary:
        feedback.append("⚠️ Summary counts do not match detail arrays")
    else:
        feedback.append("❌ Summary section missing")

    # CRITERION 5: Sensitive Data Check (10 pts)
    # Convert agent output to string to search for leaks
    agent_str = json.dumps(agent_output).lower()
    leaks = [p for p in sensitive_patterns if p.lower() in agent_str]
    
    if not leaks:
        score += 10
        feedback.append("✅ No sensitive data found")
    else:
        feedback.append(f"❌ Sensitive data leaked: {leaks}")

    # CRITERION 6: Timestamp Validity (5 pts)
    ts = agent_output.get('report_generated_at')
    if ts and len(ts) > 10:
        score += 5
    else:
        feedback.append("⚠️ Invalid timestamp")

    # CRITERION 7: VLM Verification (15 pts)
    # We want to see if the agent actually navigated the API or Web Admin
    # Since this is an API task, they might just use curl in terminal, or Firefox.
    # We accept either.
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        prompt = """
        Review these screenshots of an agent performing a task.
        The goal is to generate a system inventory report from Nx Witness VMS.
        
        Look for:
        1. Using a terminal to run 'curl' commands or scripts.
        2. Using Firefox to view the Nx Witness Web Admin or API documentation.
        3. Editing a JSON file or code.
        
        Does the agent appear to be working on gathering system data?
        """
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('confidence') != 'low':
             score += 15
             feedback.append("✅ VLM verified active work")
        else:
             # Fallback: if they got the data right (score > 60), we give them the VLM points
             # because API work might not look like much in screenshots.
             if score >= 60:
                 score += 15
                 feedback.append("✅ Implicit verification (data is correct)")
             else:
                 feedback.append("⚠️ VLM could not clearly verify workflow")
    else:
        # If no VLM, grant points if data is good
        if score >= 60: score += 15

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }