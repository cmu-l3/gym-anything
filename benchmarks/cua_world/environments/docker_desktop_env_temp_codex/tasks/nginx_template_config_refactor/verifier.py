#!/usr/bin/env python3
"""
Verifier for nginx_template_config_refactor task.

Scoring Criteria:
1. Template Usage (20 pts): .template file exists OR default.conf used with correct mounts.
2. Variable Syntax (20 pts): Config contains ${BACKEND_URL}.
3. Compose Config (20 pts): docker-compose.yml passes BACKEND_URL.
4. Dynamic Verification (30 pts): Verifier injected a random URL and confirmed it appeared in the generated config.
5. Functional Check (10 pts): The stack works with the default configuration.

Pass Threshold: 70 points (Must pass Dynamic Verification)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nginx_template_refactor(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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
    
    # Extract data
    template_exists = result.get('template_exists', False)
    template_content = result.get('template_content_snippet', '')
    default_conf_content = result.get('default_conf_snippet', '')
    compose_content = result.get('compose_content_snippet', '')
    functional_passed = result.get('functional_check_passed', False)
    dynamic_passed = result.get('dynamic_check_passed', False)
    generated_config = result.get('generated_config_snippet', '')
    
    # 1. Check for Variable Syntax (20 pts)
    # Could be in a .template file OR in default.conf (if they mounted it to /etc/nginx/templates/)
    var_syntax_found = False
    if "${BACKEND_URL}" in template_content:
        var_syntax_found = True
    elif "${BACKEND_URL}" in default_conf_content:
        var_syntax_found = True
        
    if var_syntax_found:
        score += 20
        feedback_parts.append("Variable syntax ${BACKEND_URL} found")
    else:
        feedback_parts.append("Variable syntax ${BACKEND_URL} NOT found in config files")

    # 2. Check Template Usage (20 pts)
    # Either a file ending in .template exists, OR the compose file mounts something to /etc/nginx/templates
    template_usage_detected = False
    if template_exists:
        template_usage_detected = True
    elif "/etc/nginx/templates" in compose_content:
        template_usage_detected = True
    
    if template_usage_detected:
        score += 20
        feedback_parts.append("Template mechanism usage detected")
    else:
        feedback_parts.append("No .template file or mount to /etc/nginx/templates/ detected")

    # 3. Check Compose Env Var (20 pts)
    if "BACKEND_URL" in compose_content and "backend:8080" in compose_content:
        score += 20
        feedback_parts.append("docker-compose.yml correctly passes BACKEND_URL")
    elif "BACKEND_URL" in compose_content:
        score += 15 # Partial if syntax is there but value might be odd
        feedback_parts.append("docker-compose.yml passes BACKEND_URL")
    else:
        feedback_parts.append("BACKEND_URL environment variable missing from docker-compose.yml")

    # 4. Functional Check (10 pts)
    if functional_passed:
        score += 10
        feedback_parts.append("Stack is functional (curl localhost works)")
    else:
        feedback_parts.append("Stack functionality check failed (curl localhost failed)")

    # 5. Dynamic Verification (30 pts) - CRITICAL
    if dynamic_passed:
        score += 30
        feedback_parts.append("Dynamic configuration injection passed")
    else:
        feedback_parts.append("Dynamic configuration injection FAILED (Generated config did not match injected value)")
        # If dynamic failed but syntax was there, maybe they mounted to wrong location
        if var_syntax_found and not template_usage_detected:
             feedback_parts.append("Hint: Did you mount the file to /etc/nginx/templates/?")

    # Pass logic
    # Must have dynamic passed (proof it works) AND score >= 70
    passed = dynamic_passed and (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "functional": functional_passed,
            "dynamic": dynamic_passed,
            "generated_config_sample": generated_config[:100]
        }
    }