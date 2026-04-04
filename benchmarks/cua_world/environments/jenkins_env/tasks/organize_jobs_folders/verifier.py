#!/usr/bin/env python3
"""
Verifier for organize_jobs_folders task.

Verifies:
1. Two folders exist (platform-team, frontend-team)
2. Folders have correct descriptions
3. Pipeline jobs exist INSIDE the folders (not at root)
4. Pipeline jobs have correct scripts/stages
"""

import json
import logging
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_jobs_folders(traj, env_info, task_info):
    """
    Verify folder structure and job creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/organize_jobs_folders_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- PART 1: Platform Team (50 pts) ---
    
    # 1. Folder Exists (12 pts)
    pf_meta = result.get('platform_folder', {}).get('metadata', {})
    pf_exists = pf_meta.get('_class') is not None
    pf_is_folder = 'Folder' in pf_meta.get('_class', '') or 'folder' in pf_meta.get('_class', '').lower()
    
    if pf_exists and pf_is_folder:
        score += 12
        feedback_parts.append("✔ 'platform-team' folder created")
    elif pf_exists:
        score += 5
        feedback_parts.append("⚠ 'platform-team' created but is not a Folder")
    else:
        feedback_parts.append("✘ 'platform-team' folder missing")

    # 2. Folder Description (8 pts)
    pf_desc = pf_meta.get('description', '') or ""
    if "platform" in pf_desc.lower() and "infrastructure" in pf_desc.lower():
        score += 8
        feedback_parts.append("✔ Platform folder description correct")
    elif pf_desc:
        score += 4
        feedback_parts.append("⚠ Platform folder description present but incomplete")
        
    # 3. Job Exists Inside Folder (12 pts)
    api_meta = result.get('api_service_build', {}).get('metadata', {})
    api_exists = api_meta.get('_class') is not None
    
    # Check for misplacement
    api_at_root = result.get('misplaced', {}).get('api_service_build_at_root', {}).get('_class') is not None
    
    if api_exists:
        score += 12
        feedback_parts.append("✔ 'api-service-build' job created inside folder")
    elif api_at_root:
        feedback_parts.append("✘ 'api-service-build' job created at ROOT (wrong location)")
    else:
        feedback_parts.append("✘ 'api-service-build' job missing")

    # 4. Job Type & Config (18 pts)
    if api_exists:
        # Check type (5 pts)
        if 'WorkflowJob' in api_meta.get('_class', ''):
            score += 5
            feedback_parts.append("✔ Job type is Pipeline")
        else:
            feedback_parts.append("✘ Job is not a Pipeline")
            
        # Check script content (13 pts)
        config_xml = result.get('api_service_build', {}).get('config_xml', '')
        if "Building API service" in config_xml and "Running API tests" in config_xml:
            score += 13
            feedback_parts.append("✔ Pipeline script correct")
        elif "Building API service" in config_xml or "Running API tests" in config_xml:
            score += 6
            feedback_parts.append("⚠ Pipeline script partially correct")
        else:
            feedback_parts.append("✘ Pipeline script missing expected stages")

    # --- PART 2: Frontend Team (50 pts) ---
    
    # 1. Folder Exists (12 pts)
    ff_meta = result.get('frontend_folder', {}).get('metadata', {})
    ff_exists = ff_meta.get('_class') is not None
    ff_is_folder = 'Folder' in ff_meta.get('_class', '') or 'folder' in ff_meta.get('_class', '').lower()
    
    if ff_exists and ff_is_folder:
        score += 12
        feedback_parts.append("✔ 'frontend-team' folder created")
    elif ff_exists:
        score += 5
        feedback_parts.append("⚠ 'frontend-team' created but is not a Folder")
    else:
        feedback_parts.append("✘ 'frontend-team' folder missing")

    # 2. Folder Description (8 pts)
    ff_desc = ff_meta.get('description', '') or ""
    if "frontend" in ff_desc.lower() and "development" in ff_desc.lower():
        score += 8
        feedback_parts.append("✔ Frontend folder description correct")
    elif ff_desc:
        score += 4
        feedback_parts.append("⚠ Frontend folder description present but incomplete")

    # 3. Job Exists Inside Folder (12 pts)
    web_meta = result.get('webapp_build', {}).get('metadata', {})
    web_exists = web_meta.get('_class') is not None
    
    # Check for misplacement
    web_at_root = result.get('misplaced', {}).get('webapp_build_at_root', {}).get('_class') is not None
    
    if web_exists:
        score += 12
        feedback_parts.append("✔ 'webapp-build' job created inside folder")
    elif web_at_root:
        feedback_parts.append("✘ 'webapp-build' job created at ROOT (wrong location)")
    else:
        feedback_parts.append("✘ 'webapp-build' job missing")

    # 4. Job Type & Config (18 pts)
    if web_exists:
        # Check type (5 pts)
        if 'WorkflowJob' in web_meta.get('_class', ''):
            score += 5
            feedback_parts.append("✔ Job type is Pipeline")
        else:
            feedback_parts.append("✘ Job is not a Pipeline")
            
        # Check script content (13 pts)
        config_xml = result.get('webapp_build', {}).get('config_xml', '')
        # Check for key phrases from the requested script
        script_points = 0
        if "Installing dependencies" in config_xml: script_points += 4
        if "Building webapp" in config_xml: script_points += 4
        if "Running linter" in config_xml: script_points += 5
        
        score += script_points
        if script_points == 13:
            feedback_parts.append("✔ Pipeline script correct")
        elif script_points > 0:
            feedback_parts.append("⚠ Pipeline script partially correct")
        else:
            feedback_parts.append("✘ Pipeline script missing expected content")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }