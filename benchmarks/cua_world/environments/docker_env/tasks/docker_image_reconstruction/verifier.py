#!/usr/bin/env python3
"""
Verifier for docker_image_reconstruction task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_image_reconstruction(traj, env_info, task_info):
    """
    Verify that Dockerfiles were reconstructed correctly and images match expected config.
    """
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
    
    files = result.get('files', {})
    images = result.get('images_exist', {})
    configs = result.get('configs', {})
    functional = result.get('functional', {})

    # =========================================================
    # 1. ACME-API Verification (35 pts)
    # =========================================================
    api_score = 0
    if files.get('api_dockerfile') and images.get('api'):
        api_score += 5
        
        # Config checks
        api_conf = configs.get('api', {})
        
        # Check User (must be appuser)
        if api_conf.get('User') == 'appuser':
            api_score += 10
            feedback_parts.append("API: Correct User")
        else:
            feedback_parts.append(f"API: Wrong User ({api_conf.get('User')})")

        # Check WorkingDir
        if api_conf.get('WorkingDir') == '/opt/api':
            api_score += 5
            feedback_parts.append("API: Correct WorkDir")

        # Check Healthcheck
        hc = api_conf.get('Healthcheck')
        if hc and isinstance(hc, dict) and hc.get('Test'):
            api_score += 5
            feedback_parts.append("API: Healthcheck present")
        else:
            feedback_parts.append("API: Missing Healthcheck")

        # Functional Check
        if functional.get('api'):
            api_score += 10
            feedback_parts.append("API: Functional test passed")
        else:
            feedback_parts.append("API: Functional test failed")
    else:
        feedback_parts.append("API: Missing Dockerfile or Image")
    
    score += api_score

    # =========================================================
    # 2. ACME-CRON Verification (30 pts)
    # =========================================================
    cron_score = 0
    if files.get('cron_dockerfile') and images.get('cron'):
        cron_score += 5

        cron_conf = configs.get('cron', {})
        
        # Check Env
        env_list = cron_conf.get('Env', []) or []
        has_schedule = any('SCHEDULE_INTERVAL=300' in e for e in env_list)
        has_log = any('LOG_LEVEL=INFO' in e for e in env_list)
        
        if has_schedule and has_log:
            cron_score += 10
            feedback_parts.append("Cron: Correct ENV vars")
        else:
            feedback_parts.append("Cron: Missing ENV vars")

        # Check Entrypoint/Cmd
        ep = cron_conf.get('Entrypoint')
        cmd = cron_conf.get('Cmd')
        # Expecting Entrypoint=["python"] Cmd=["scheduler.py"]
        if ep and 'python' in ep[0] and cmd and 'scheduler.py' in cmd[0]:
            cron_score += 10
            feedback_parts.append("Cron: Correct Entrypoint/Cmd")
        else:
            feedback_parts.append("Cron: Wrong Entrypoint/Cmd structure")

        # Functional
        if functional.get('cron'):
            cron_score += 5
            feedback_parts.append("Cron: Runs successfully")
    else:
        feedback_parts.append("Cron: Missing Dockerfile or Image")
        
    score += cron_score

    # =========================================================
    # 3. ACME-GATEWAY Verification (25 pts)
    # =========================================================
    gw_score = 0
    if files.get('gateway_dockerfile') and images.get('gateway'):
        gw_score += 5
        
        gw_conf = configs.get('gateway', {})
        ports = gw_conf.get('ExposedPorts', {}) or {}
        
        if '80/tcp' in ports:
            gw_score += 10
            feedback_parts.append("Gateway: Exposes port 80")
        
        if functional.get('gateway'):
            gw_score += 10
            feedback_parts.append("Gateway: Responds on port")
    else:
        feedback_parts.append("Gateway: Missing Dockerfile or Image")
        
    score += gw_score

    # =========================================================
    # 4. Documentation (10 pts)
    # =========================================================
    if files.get('notes'):
        score += 10
        feedback_parts.append("Notes created")
    else:
        feedback_parts.append("Notes missing")

    # Final result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }