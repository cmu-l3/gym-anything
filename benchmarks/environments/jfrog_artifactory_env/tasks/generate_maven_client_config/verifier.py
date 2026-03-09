#!/usr/bin/env python3
import json
import os
import base64
import tempfile
import xml.etree.ElementTree as ET

def verify_generate_maven_client_config(traj, env_info, task_info):
    """
    Verifies that the agent generated a valid maven settings.xml for the correct repository.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_repo_key = metadata.get('target_repo_key', 'example-repo-local')
    target_url_part = metadata.get('target_repo_url_part', 'artifactory/example-repo-local')

    # Load result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence (30 pts)
    if not result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file maven_settings.xml not found."}
    
    score += 30
    feedback_parts.append("File created")

    # Anti-gaming check (must be created/modified during task)
    if not result.get('file_created_during_task', False):
        feedback_parts.append("WARNING: File timestamp predates task start")
        # We penalize but don't fail immediately if content is perfect, though usually this implies pre-seeding
        score -= 20

    # Decode content
    try:
        content_b64 = result.get('file_content_base64', '')
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except Exception:
        return {"passed": False, "score": score, "feedback": "Failed to decode file content."}

    # Criterion 2: Valid XML Format (20 pts)
    try:
        # Wrap in a root element if it's a snippet without one, to make parsing robust
        # The 'Set Me Up' snippet usually starts with <settings> or is a fragment inside <settings>
        # We try parsing directly first
        try:
            root = ET.fromstring(content)
        except ET.ParseError:
            # If strictly a snippet of <server>...</server><profile>...</profile>, wrap it
            wrapped_content = f"<root>{content}</root>"
            root = ET.fromstring(wrapped_content)
        
        score += 20
        feedback_parts.append("Valid XML")
    except ET.ParseError:
        return {"passed": False, "score": score, "feedback": "File content is not valid XML."}

    # Search text for keywords (easier than strict path traversal for varying snippets)
    # Criterion 3: Correct Repository Key (25 pts)
    if target_repo_key in content:
        score += 25
        feedback_parts.append(f"Found repo key '{target_repo_key}'")
    else:
        feedback_parts.append(f"Missing repo key '{target_repo_key}'")

    # Criterion 4: Correct Repository URL (25 pts)
    # We look for the structure "http://localhost:8082/artifactory/example-repo-local"
    # or just the path part if the host is variable, but usually "Set Me Up" uses the configured base URL
    if target_url_part in content:
        score += 25
        feedback_parts.append(f"Found correct URL path '{target_url_part}'")
    else:
        feedback_parts.append(f"Missing correct URL path '{target_url_part}'")

    # Pass threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }