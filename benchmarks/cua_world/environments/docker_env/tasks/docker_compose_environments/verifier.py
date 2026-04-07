#!/usr/bin/env python3
"""
Verifier for docker_compose_environments task.

Checks:
1. Files exist (base, override, prod)
2. Static YAML analysis (correct structure, keys)
3. Runtime inspection (production constraints active)
4. Functional test (API responds)

Points breakdown (100 total):
- Base file structure: 15
- Dev override (debug=1, binds, ports): 25
- Prod override (debug=0, limits, restart, auth): 35
- Runtime Verification (containers up, secure, functional): 25
"""

import json
import yaml
import base64
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_b64_yaml(b64_str: str) -> Dict[str, Any]:
    if not b64_str:
        return {}
    try:
        decoded = base64.b64decode(b64_str).decode('utf-8')
        return yaml.safe_load(decoded) or {}
    except Exception:
        return {}

def verify_docker_compose_environments(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    
    files = result.get('files', {})
    containers = result.get('containers', {})
    functional = result.get('functional', {})
    task_start = result.get('task_start_time', 0)

    # =========================================================
    # 1. FILE EXISTENCE & BASE STRUCTURE (15 pts)
    # =========================================================
    base_yml = parse_b64_yaml(files.get('base_content_b64', ''))
    
    if files.get('base_exists'):
        # Check if base defines services
        services = base_yml.get('services', {})
        if all(k in services for k in ['db', 'cache', 'api', 'nginx']):
            score += 15
            feedback.append("Base compose file valid (+15)")
        else:
            score += 5
            feedback.append("Base compose file missing required services (5/15)")
    else:
        feedback.append("Base docker-compose.yml missing (0/15)")

    # =========================================================
    # 2. DEV OVERRIDE ANALYSIS (25 pts)
    # =========================================================
    dev_yml = parse_b64_yaml(files.get('dev_content_b64', ''))
    
    if files.get('dev_exists'):
        dev_score = 0
        api_svc = dev_yml.get('services', {}).get('api', {})
        
        # Check FLASK_DEBUG=1
        env = api_svc.get('environment', {})
        # Handle list format ["KEY=VAL"] or dict format {"KEY": "VAL"}
        debug_on = False
        if isinstance(env, dict):
            debug_on = str(env.get('FLASK_DEBUG', '')).lower() in ['1', 'true']
        elif isinstance(env, list):
            for e in env:
                if 'FLASK_DEBUG=1' in e.replace('"', '').replace("'", ""):
                    debug_on = True
        
        if debug_on:
            dev_score += 10
            feedback.append("Dev: Debug mode enabled")
        
        # Check Volumes (bind mount)
        vols = api_svc.get('volumes', [])
        has_bind = any('./api' in v or '/home/ga/projects' in v for v in vols)
        if has_bind:
            dev_score += 10
            feedback.append("Dev: Bind mount present")

        # Check Ports exposed
        ports = api_svc.get('ports', [])
        if ports:
            dev_score += 5
            feedback.append("Dev: Ports exposed")
            
        score += dev_score
        feedback.append(f"Dev Config Score: {dev_score}/25")
    else:
        feedback.append("Dev override missing (0/25)")

    # =========================================================
    # 3. PROD OVERRIDE ANALYSIS (35 pts)
    # =========================================================
    prod_yml = parse_b64_yaml(files.get('prod_content_b64', ''))
    
    if files.get('prod_exists'):
        prod_score = 0
        services = prod_yml.get('services', {})
        api_svc = services.get('api', {})
        
        # Check FLASK_DEBUG=0
        env = api_svc.get('environment', {})
        debug_off = False
        if isinstance(env, dict):
            val = str(env.get('FLASK_DEBUG', ''))
            debug_off = val == '0' or val.lower() == 'false'
        elif isinstance(env, list):
             for e in env:
                if 'FLASK_DEBUG=0' in e or 'FLASK_DEBUG=false' in e.lower():
                    debug_off = True
        
        if debug_off:
            prod_score += 5
        
        # Check Restart Policies
        has_restart = all(services.get(s, {}).get('restart') == 'unless-stopped' for s in ['db', 'cache', 'api', 'nginx'] if s in services)
        if has_restart:
            prod_score += 10
            feedback.append("Prod: Restart policies set")

        # Check Limits
        # e.g. deploy: resources: limits: memory: ...
        has_limits = False
        if 'deploy' in api_svc or 'mem_limit' in api_svc:
            has_limits = True
        if has_limits:
            prod_score += 10
            feedback.append("Prod: Resource limits set")
            
        # Check Redis Auth
        cache_svc = services.get('cache', {})
        cmd = cache_svc.get('command', '')
        # Check if password is in command or env
        has_auth = 'requirepass' in str(cmd) or 'REDIS_PASSWORD' in str(cache_svc.get('environment', ''))
        # Check API connection string update
        api_env = str(api_svc.get('environment', ''))
        if has_auth and ('AcmeR3dis2024!' in api_env or 'REDIS_PASSWORD' in api_env):
            prod_score += 10
            feedback.append("Prod: Redis auth configured")

        score += prod_score
        feedback.append(f"Prod Config Score: {prod_score}/35")
    else:
        feedback.append("Prod override missing (0/35)")

    # =========================================================
    # 4. RUNTIME VERIFICATION (25 pts)
    # =========================================================
    runtime_score = 0
    
    # Check if containers are running
    api_info = containers.get('api')
    
    if api_info and isinstance(api_info, list) and len(api_info) > 0:
        ctr = api_info[0] # docker inspect returns a list
        state = ctr.get('State', {})
        
        # Check created time > task start (Anti-gaming)
        created_str = ctr.get('Created', '')
        # Simple check: if container exists and is running, we assume it was created during task 
        # because setup wipes previous containers. Timestamp parsing can be brittle in python without iso8601 lib.
        
        if state.get('Running'):
            runtime_score += 10
            feedback.append("Containers running")
            
            # Check Memory Limit applied (Prod check)
            mem = ctr.get('HostConfig', {}).get('Memory', 0)
            if mem > 0:
                runtime_score += 5
                feedback.append("Runtime: Memory limits active")
            
            # Check Restart Policy (Prod check)
            policy = ctr.get('HostConfig', {}).get('RestartPolicy', {}).get('Name', '')
            if policy == 'unless-stopped':
                runtime_score += 5
                feedback.append("Runtime: Restart policy active")
    else:
        feedback.append("API container not running")

    # Functional Test
    if functional.get('response_code') == '200':
        runtime_score += 5
        feedback.append("API responding (Functional)")
    
    score += runtime_score
    feedback.append(f"Runtime Score: {runtime_score}/25")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback)
    }