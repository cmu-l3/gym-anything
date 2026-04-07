#!/usr/bin/env python3
"""
Verifier for configure_pm2_ecosystem task.

Evaluates DevOps skills by analyzing:
1. File timestamps and sizes (Anti-gaming).
2. The parsed JavaScript module structure of ecosystem.config.js.
3. The actual PM2 background process state.
4. Trajectory verification via VLM to ensure CLI/editor tools were used.
"""

import os
import json
import tempfile
import logging

# Import VLM utilities for trajectory verification
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are analyzing an agent's desktop trajectory completing a DevOps task.
The goal was to create a PM2 ecosystem file (`ecosystem.config.js`) and start microservices.

Please verify:
1. Did the agent use a text editor (like nano, vim, gedit, or vscode) to write a JavaScript configuration file?
2. Did the agent use the terminal to interact with the PM2 CLI (e.g., typing `pm2 start`, `pm2 save`, `pm2 status`)?

Return a JSON object:
{
    "used_editor": true/false,
    "used_pm2_cli": true/false,
    "reasoning": "brief explanation of what you see in the terminal"
}
"""

def verify_pm2_ecosystem(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_services = metadata.get('expected_services', ["user", "feeds", "publish", "notification"])
    base_cwd = metadata.get('base_cwd', '/opt/socioboard/socioboard-api')

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Retrieve Artifacts from Container
    # ---------------------------------------------------------
    files_to_copy = {
        'result': '/tmp/task_result.json',
        'parsed_eco': '/tmp/parsed_ecosystem.json',
        'pm2_list': '/tmp/pm2_jlist.json'
    }
    
    data = {}
    for key, path in files_to_copy.items():
        tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(path, tmp_file.name)
            with open(tmp_file.name, 'r') as f:
                content = f.read().strip()
                data[key] = json.loads(content) if content else {}
        except Exception as e:
            logger.warning(f"Failed to read {path}: {e}")
            data[key] = {}
        finally:
            if os.path.exists(tmp_file.name):
                os.unlink(tmp_file.name)

    result = data.get('result', {})
    parsed_eco = data.get('parsed_eco', {})
    pm2_list = data.get('pm2_list', [])

    # ---------------------------------------------------------
    # 2. File Existence & Anti-Gaming Checks (10 pts)
    # ---------------------------------------------------------
    task_start = result.get('task_start', 0)
    eco_exists = result.get('eco_exists', False)
    eco_mtime = result.get('eco_mtime', 0)
    eco_size = result.get('eco_size', 0)

    if not eco_exists:
        return {"passed": False, "score": 0, "feedback": "ecosystem.config.js was not created."}
    
    if eco_mtime < task_start:
        return {"passed": False, "score": 0, "feedback": "Anti-gaming failure: File timestamp predates task start."}

    if eco_size >= 100:
        score += 10
        feedback_parts.append("Ecosystem file exists and has valid timestamp.")
    else:
        feedback_parts.append("Ecosystem file is too small to be valid.")

    # ---------------------------------------------------------
    # 3. JavaScript Module Validation (10 pts)
    # ---------------------------------------------------------
    if parsed_eco.get('success', False):
        score += 10
        feedback_parts.append("Ecosystem file is valid JavaScript.")
    else:
        err = parsed_eco.get('error', 'Unknown error')
        feedback_parts.append(f"Ecosystem JS Parse Error: {err}")

    # ---------------------------------------------------------
    # 4. Evaluate 'apps' Array Content (20 pts)
    # ---------------------------------------------------------
    apps = parsed_eco.get('data', {}).get('apps', [])
    if isinstance(apps, list) and len(apps) > 0:
        valid_services_count = 0
        correct_cwds = 0
        correct_envs = 0
        
        # Track which of the 4 expected services were configured
        configured_services = set()
        
        for app in apps:
            name = app.get('name', '').lower()
            cwd = app.get('cwd', '')
            env_vars = app.get('env', {}) or app.get('env_development', {})
            
            # Match against expected services
            for expected in expected_services:
                if expected in name:
                    configured_services.add(expected)
                    valid_services_count += 1
            
            # Validate Working Directory context
            if base_cwd in cwd:
                correct_cwds += 1
                
            # Validate Environment configuration
            if env_vars.get('NODE_ENV') == 'development':
                correct_envs += 1

        if len(configured_services) == len(expected_services):
            score += 10
            feedback_parts.append("All required services named in config.")
        elif len(configured_services) > 0:
            score += (len(configured_services) * 2)
            feedback_parts.append(f"Partial services defined: {list(configured_services)}.")
            
        if correct_cwds >= len(expected_services):
            score += 5
            
        if correct_envs >= len(expected_services):
            score += 5
    else:
        feedback_parts.append("Ecosystem file missing 'apps' array.")

    # ---------------------------------------------------------
    # 5. Check Actual PM2 Process State (20 pts)
    # ---------------------------------------------------------
    pm2_online_count = 0
    for proc in pm2_list:
        status = proc.get('pm2_env', {}).get('status', '')
        if status == 'online':
            pm2_online_count += 1

    if pm2_online_count >= len(expected_services):
        score += 20
        feedback_parts.append(f"PM2 successfully running {pm2_online_count} processes.")
    elif pm2_online_count > 0:
        score += (pm2_online_count * 5)
        feedback_parts.append(f"Only {pm2_online_count} processes online in PM2.")
    else:
        feedback_parts.append("No online PM2 processes detected.")

    # ---------------------------------------------------------
    # 6. Check Status Report Artifact (10 pts)
    # ---------------------------------------------------------
    if result.get('status_exists', False) and result.get('status_size', 0) > 50:
        score += 10
        feedback_parts.append("Status report saved correctly.")
    else:
        feedback_parts.append("Status report missing or incomplete.")

    # ---------------------------------------------------------
    # 7. VLM Trajectory Verification (30 pts)
    # ---------------------------------------------------------
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        vlm_resp = query_vlm(images=frames + [final], prompt=VLM_PROMPT)
        
        if vlm_resp.get("success"):
            parsed_vlm = vlm_resp.get("parsed", {})
            used_editor = parsed_vlm.get("used_editor", False)
            used_pm2 = parsed_vlm.get("used_pm2_cli", False)
            
            vlm_score = 0
            if used_editor:
                vlm_score += 15
            if used_pm2:
                vlm_score += 15
                
            score += vlm_score
            feedback_parts.append(f"VLM verification: editor={used_editor}, pm2={used_pm2}")
        else:
            feedback_parts.append("VLM verification failed to process.")
    except Exception as e:
        logger.error(f"VLM analysis error: {e}")
        feedback_parts.append("VLM analysis error.")

    # Final scoring calculation
    passed = score >= 60 and eco_exists and pm2_online_count > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }