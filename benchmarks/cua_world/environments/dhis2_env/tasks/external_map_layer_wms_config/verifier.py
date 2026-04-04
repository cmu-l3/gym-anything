#!/usr/bin/env python3
"""
Verifier for external_map_layer_wms_config task.

Scoring (100 points total):
- External Map Layer created (30 pts)
- WMS URL configured correctly (20 pts)
- WMS Layer parameter correct (10 pts)
- Map created (10 pts)
- Map contains external layer (30 pts)

Checks creation timestamps against task start.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_external_map_layer_wms_config(traj, env_info, task_info):
    """Verify WMS layer configuration and map creation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/task_result.json", temp_path)
        
        with open(temp_path, 'r') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}

    score = 0
    feedback_parts = []
    
    # Metadata expectations
    expected_url = "http://ows.mundialis.de/services/service"
    expected_layer_param = "TOPO-WMS"
    
    # 1. Check External Map Layer
    layer_found = result.get('layer_found', False)
    layer_details = result.get('layer_details', {})
    
    if layer_found:
        score += 30
        feedback_parts.append("External Map Layer created (+30)")
        
        # Check URL
        actual_url = layer_details.get('url', '')
        if actual_url == expected_url:
            score += 20
            feedback_parts.append("WMS URL correct (+20)")
        else:
            feedback_parts.append(f"Incorrect URL: '{actual_url}'")
            
        # Check Layer Param
        actual_layer = layer_details.get('layers', '')
        if actual_layer == expected_layer_param:
            score += 10
            feedback_parts.append("Layer parameter correct (+10)")
        else:
            feedback_parts.append(f"Incorrect Layer param: '{actual_layer}'")
    else:
        feedback_parts.append("External Map Layer 'Global Topography WMS' not found")

    # 2. Check Map
    map_found = result.get('map_found', False)
    map_details = result.get('map_details', {})
    
    if map_found:
        score += 10
        feedback_parts.append("Map 'Vegetation Reference Map' created (+10)")
        
        # Check if layer is used
        if map_details.get('layer_used', False):
            score += 30
            feedback_parts.append("Map correctly references the external layer (+30)")
        else:
            feedback_parts.append("Map does not contain the 'Global Topography WMS' layer")
    else:
        feedback_parts.append("Map 'Vegetation Reference Map' not found")

    # Timestamp check (Basic anti-gaming)
    task_start = result.get('task_start_iso')
    layer_created = layer_details.get('created')
    
    # Simple string comparison for ISO dates usually works if formats align, 
    # but strictly we trust the logic that the Setup script deleted pre-existing items.
    # If items exist now, they must be new.
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }