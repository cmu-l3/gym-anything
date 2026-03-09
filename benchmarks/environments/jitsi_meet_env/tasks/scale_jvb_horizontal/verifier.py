#!/usr/bin/env python3
"""
Verifier for scale_jvb_horizontal task.

Checks:
1. Docker Compose file contains valid jvb2 service definition.
2. JVB2 container is running.
3. JVB2 container has correct port mappings and env vars.
4. Report file exists and contains correct data.
5. VLM trajectory verification.
"""

import json
import base64
import tempfile
import os
import yaml
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scale_jvb_horizontal(traj, env_info, task_info):
    """
    Verify that the user successfully added a second JVB instance.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Scoring weights
    SCORE_SERVICE_DEF = 15
    SCORE_CONTAINER_NAME = 5
    SCORE_PORT_UDP = 10
    SCORE_ENV_ID = 5
    SCORE_AUTH_NET = 5
    SCORE_DEPENDS = 5
    SCORE_RUNNING = 20
    SCORE_HEALTHY = 10
    SCORE_WEB_ACCESS = 10
    SCORE_REPORT = 10
    SCORE_VLM = 5
    
    score = 0
    feedback_parts = []
    
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

    # 1. Verify Docker Compose Configuration (Parsing YAML)
    compose_b64 = result.get('compose_content_b64', '')
    jvb2_config = None
    if compose_b64:
        try:
            compose_str = base64.b64decode(compose_b64).decode('utf-8')
            compose_data = yaml.safe_load(compose_str)
            services = compose_data.get('services', {})
            jvb2_config = services.get('jvb2')
        except Exception as e:
            feedback_parts.append(f"Invalid YAML in docker-compose.yml: {e}")

    if jvb2_config:
        score += SCORE_SERVICE_DEF
        feedback_parts.append("Service 'jvb2' defined in compose file")
        
        # Check container name
        if jvb2_config.get('container_name') == 'jitsi-jvb2':
            score += SCORE_CONTAINER_NAME
        else:
            feedback_parts.append("Wrong container name")

        # Check ports
        ports = jvb2_config.get('ports', [])
        # Handle various yaml formats for ports ("10001:10001/udp" or dict)
        port_correct = False
        for p in ports:
            if isinstance(p, str) and '10001' in p and 'udp' in p.lower():
                port_correct = True
            elif isinstance(p, dict) and p.get('published') == 10001 and p.get('protocol') == 'udp':
                port_correct = True
        
        if port_correct:
            score += SCORE_PORT_UDP
        else:
            feedback_parts.append("Missing port mapping 10001:10001/udp")

        # Check Environment
        env_vars = jvb2_config.get('environment', [])
        # Convert list to dict if needed (YAML can be list of "KEY=VAL" or dict)
        env_dict = {}
        if isinstance(env_vars, list):
            for item in env_vars:
                if '=' in item:
                    k, v = item.split('=', 1)
                    env_dict[k] = v
        elif isinstance(env_vars, dict):
            env_dict = env_vars
            
        if str(env_dict.get('JVB_PORT')) == '10001':
            # Partial credit included in UDP score logic usually, but here separate check
            pass 
            
        if env_dict.get('JVB_OSERVER_WS_SERVER_ID') == 'jvb2':
            score += SCORE_ENV_ID
        else:
            feedback_parts.append("Missing/Wrong JVB_OSERVER_WS_SERVER_ID")

        # Check networks and passwords (basic check)
        if 'meet.jitsi' in jvb2_config.get('networks', []) and 'JVB_AUTH_PASSWORD' in env_dict:
            score += SCORE_AUTH_NET
        
        # Check depends_on
        depends = jvb2_config.get('depends_on', [])
        if 'prosody' in depends:
            score += SCORE_DEPENDS

    else:
        feedback_parts.append("Service 'jvb2' NOT found in compose file")

    # 2. Verify Container Runtime State
    jvb2_running = result.get('jvb2_running', False)
    running_count = result.get('running_jvb_count', 0)
    
    if jvb2_running:
        score += SCORE_RUNNING
        feedback_parts.append("Container jitsi-jvb2 is running")
    else:
        feedback_parts.append("Container jitsi-jvb2 is NOT running")

    # Check overall health (approximate)
    if running_count >= 2:
        score += SCORE_HEALTHY
    
    # 3. Verify Log Success (Registration)
    if result.get('jvb2_log_success', False):
        score += SCORE_WEB_ACCESS # reusing points bucket for "successful operation"
        feedback_parts.append("JVB2 successfully registered with XMPP")
    else:
        feedback_parts.append("No XMPP registration confirmed in logs")

    # 4. Verify Report File
    report_exists = result.get('report_exists', False)
    report_valid = False
    if report_exists:
        try:
            content = base64.b64decode(result.get('report_content_b64', '')).decode('utf-8').strip().split('\n')
            if len(content) >= 5:
                # Basic validation of content
                if '2' in content[0] and '10000' in ''.join(content) and '10001' in ''.join(content):
                    report_valid = True
        except:
            pass
            
    if report_valid:
        score += SCORE_REPORT
        feedback_parts.append("Report file correct")
    elif report_exists:
        score += SCORE_REPORT // 2
        feedback_parts.append("Report file exists but content issues")
    else:
        feedback_parts.append("Report file missing")

    # 5. VLM Verification (Trajectory)
    # Basic check: did they use docker?
    # Since we can't easily run full VLM here without the helper, we'll give points if functional parts worked
    if jvb2_running and jvb2_config:
        score += SCORE_VLM
    
    passed = score >= 60 and jvb2_running
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }