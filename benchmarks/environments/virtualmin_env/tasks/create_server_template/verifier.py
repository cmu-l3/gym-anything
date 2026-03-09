#!/usr/bin/env python3
"""
Verifier for create_server_template task.
"""

import json
import os
import sys
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_virtualmin_config(content):
    """
    Parses a Virtualmin key=value config file content into a dictionary.
    """
    config = {}
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            config[key.strip()] = value.strip()
    return config

def verify_create_server_template(traj, env_info, task_info):
    """
    Verifies that the server template was created with the correct settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('template_name', 'FastWeb Static')
    required_directive = metadata.get('required_directive', 'Options -Indexes +FollowSymLinks')
    required_html = metadata.get('required_html', '<h1>Hosted by FastWeb Static Node</h1>')
    forbidden_features = metadata.get('forbidden_features', ["mail", "mysql", "spam", "virus"])

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    
    os.unlink(temp_json.name)

    # 2. Check if template exists
    if not result.get('template_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Template '{expected_name}' was not found. Ensure you saved it with the exact name."
        }

    # 3. Retrieve Template Content
    template_content_path = result.get('template_content_file')
    temp_content = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(template_content_path, temp_content.name)
        with open(temp_content.name, 'r') as f:
            content_str = f.read()
    except Exception as e:
        if os.path.exists(temp_content.name): os.unlink(temp_content.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to read template content: {e}"}
    
    os.unlink(temp_content.name)

    # 4. Parse Configuration
    config = parse_virtualmin_config(content_str)
    
    score = 0
    feedback = []
    
    # Criterion 1: Template Created (30 pts) - Already confirmed by existence
    score += 30
    feedback.append("Template created successfully.")

    # Criterion 2: Features Disabled (30 pts)
    # Virtualmin uses 'feature_name=1' for enabled, '0' or missing (sometimes) for disabled.
    # In templates, it typically stores the override preferences.
    # Keys like `mail=0`, `mysql=0`.
    features_passed = True
    for feature in forbidden_features:
        # Check if set to 0 (disabled)
        # Sometimes keys are implicit, but in a template defining "disabled", they should appear as 0
        val = config.get(feature)
        if val == '1':
            features_passed = False
            feedback.append(f"Feature '{feature}' was NOT disabled.")
        elif val == '0':
            pass # Good
        else:
            # If missing, it might inherit from default, which is usually enabled.
            # We strictly expect the agent to explicitly disable them in the template.
            # However, technically if the clone source had them disabled it counts, 
            # but standard Default Settings has them enabled.
            # Let's check strict explicit disablement for scoring robustness.
            # Actually, sometimes templates omit keys to use defaults. 
            # But the task asked to disable them.
            pass

    # Let's look for explicit '0's or assume if we cloned 'Default Settings' (where they are 1), 
    # we need to see '0' to override.
    disabled_count = 0
    for feature in forbidden_features:
        if config.get(feature) == '0':
            disabled_count += 1
    
    if disabled_count == len(forbidden_features):
        score += 30
        feedback.append("All specified features disabled correctly.")
    elif disabled_count > 0:
        partial = int(30 * (disabled_count / len(forbidden_features)))
        score += partial
        feedback.append(f"Some features disabled ({disabled_count}/{len(forbidden_features)}).")
    else:
        feedback.append("No required features were explicitly disabled.")

    # Criterion 3: Apache Hardening (20 pts)
    # Key is typically `web_directives`
    web_directives = config.get('web_directives', '')
    # The directives might be stored with literal newlines encoded or stripped.
    # We check if our string is contained.
    # Normalize spaces
    if required_directive.replace(" ", "") in web_directives.replace(" ", ""):
        score += 20
        feedback.append("Apache directives configured correctly.")
    else:
        feedback.append(f"Apache directive missing or incorrect. Found: '{web_directives}'")

    # Criterion 4: Custom HTML (20 pts)
    # Key is `web_html`
    web_html = config.get('web_html', '')
    if required_html in web_html:
        score += 20
        feedback.append("Initial HTML content configured correctly.")
    else:
        feedback.append("Initial HTML content missing or incorrect.")

    # 5. VLM Verification (Optional but recommended for robust "process" check)
    # If score is high (programmatic pass), we trust it. 
    # If low, maybe they did it in a way the parser didn't catch (unlikely for file config).
    # We'll use VLM to just confirm the "Save" action or menu presence as a sanity check.
    
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }