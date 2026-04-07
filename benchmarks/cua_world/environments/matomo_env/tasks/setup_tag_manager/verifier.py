#!/usr/bin/env python3
"""
Verifier for Matomo Tag Manager Setup task.

Verifies:
1. Container existence
2. Trigger creation (Name: AllPages, Type: PageView)
3. Tag creation (Name: ConversionPixel, Type: CustomHtml, Content correct)
4. Link between Tag and Trigger
5. Published Version
"""

import json
import logging
import os
import tempfile
import datetime
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_string(s: str) -> str:
    if not s:
        return ""
    return s.strip().lower()

def verify_setup_tag_manager(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_tag_name = metadata.get('expected_tag_name', 'ConversionPixel')
    expected_tag_content = metadata.get('expected_tag_content', '<script>console.log("matomo-tag-manager-active");</script>')
    expected_trigger_name = metadata.get('expected_trigger_name', 'AllPages')
    
    # Load result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/tag_manager_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    db_data = result.get('db_data', {})
    if not db_data:
        # Handle case where db_data might be nested string or null
        return {"passed": False, "score": 0, "feedback": "No database data found in result"}

    containers = db_data.get('containers', []) or []
    tags = db_data.get('tags', []) or []
    triggers = db_data.get('triggers', []) or []
    versions = db_data.get('versions', []) or []

    score = 0
    feedback = []
    
    # 1. Verify Container (10 pts)
    container_exists = len(containers) > 0
    if container_exists:
        score += 10
        feedback.append(f"Container exists: {containers[0].get('name')} (ID: {containers[0].get('idcontainer')})")
    else:
        feedback.append("No container found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Verify Trigger (15 pts exists, 10 pts type)
    trigger_found = None
    for t in triggers:
        if normalize_string(t.get('name')) == normalize_string(expected_trigger_name):
            trigger_found = t
            break
            
    if trigger_found:
        score += 15
        feedback.append(f"Trigger '{expected_trigger_name}' found")
        # Check type (PageView is usually stored as 'PageView' or internal ID, typically string in JSON export)
        # Note: In TSV export it might be raw string
        t_type = str(trigger_found.get('type', ''))
        if 'PageView' in t_type or 'Pageview' in t_type: # Case insensitive check
            score += 10
            feedback.append("Trigger type is PageView")
        else:
            feedback.append(f"Trigger type mismatch (found: {t_type})")
    else:
        feedback.append(f"Trigger '{expected_trigger_name}' NOT found")

    # 3. Verify Tag (15 pts exists, 10 pts type, 15 pts content)
    tag_found = None
    for t in tags:
        if normalize_string(t.get('name')) == normalize_string(expected_tag_name):
            tag_found = t
            break

    if tag_found:
        score += 15
        feedback.append(f"Tag '{expected_tag_name}' found")
        
        # Check Type
        tag_type = str(tag_found.get('type', ''))
        if 'CustomHtml' in tag_type:
            score += 10
            feedback.append("Tag type is CustomHtml")
        else:
            feedback.append(f"Tag type mismatch (found: {tag_type})")

        # Check Content
        # Parameters is a JSON string: {"customHtml":"<script>..."}
        params_str = tag_found.get('parameters', '{}')
        try:
            params = json.loads(params_str)
            html_content = params.get('customHtml', '')
        except:
            # Fallback if params is already a dict or malformed
            params = params_str if isinstance(params_str, dict) else {}
            html_content = params.get('customHtml', '')

        # Normalize whitespace for comparison
        norm_html = "".join(html_content.split())
        norm_expected = "".join(expected_tag_content.split())
        
        if norm_expected in norm_html:
            score += 15
            feedback.append("Tag content matches expected script")
        else:
            feedback.append("Tag content incorrect or empty")
    else:
        feedback.append(f"Tag '{expected_tag_name}' NOT found")

    # 4. Verify Link (10 pts)
    # Check if tag is linked to trigger
    link_verified = False
    if tag_found and trigger_found:
        trigger_id = trigger_found.get('idtrigger')
        # fire_trigger_ids is a JSON array string: "[1, 2]"
        fire_ids_raw = tag_found.get('fire_trigger_ids', '[]')
        try:
            fire_ids = json.loads(fire_ids_raw)
        except:
            fire_ids = []
            
        # Handle mixed types (int vs string)
        fire_ids_str = [str(x) for x in fire_ids]
        if str(trigger_id) in fire_ids_str:
            link_verified = True
    
    if link_verified:
        score += 10
        feedback.append("Tag correctly linked to Trigger")
    else:
        if tag_found and trigger_found:
            feedback.append("Tag NOT linked to Trigger")

    # 5. Verify Published Version (15 pts)
    # Check for any version with status='live' or just existence of a version
    # 'status' in DB for version: 'live', 'draft', etc.
    # Usually 'live' or 'released'.
    # We check if ANY version exists (since user might not have set it live correctly but published a version)
    # Task asks to "Publish" which creates a version.
    
    published_version = False
    for v in versions:
        # Check if it's not a draft (draft usually doesn't appear in this table or has specific status)
        # In Matomo, versions are snapshots.
        if v.get('name') != 'Current Version' or v.get('idcontainerversion') > 0:
            published_version = True
            break
    
    if published_version:
        score += 15
        feedback.append("Container version published")
    else:
        feedback.append("No published container version found")

    return {
        "passed": score >= 60 and container_exists and tag_found is not None,
        "score": score,
        "feedback": " | ".join(feedback)
    }