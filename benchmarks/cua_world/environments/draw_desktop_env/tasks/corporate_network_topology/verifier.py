#!/usr/bin/env python3
"""
Verifier for corporate_network_topology task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_corporate_network_topology(traj, env_info, task_info):
    """
    Verifies the corporate network topology task.
    
    Scoring Criteria:
    1. File Existence & Validity (10 pts)
    2. Device Coverage (20 pts): >=15 devices found
    3. Topology Complexity (15 pts): >=12 edges
    4. Zone Structure (20 pts): >=4 zones found
    5. Subnet/VLAN Info (10 pts): Detected in text
    6. Multi-page (10 pts): >=2 pages
    7. PNG Export (15 pts): Valid PNG exists
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    analysis = result.get('analysis', {})
    
    score = 0
    feedback = []
    
    # 1. File Existence & Modification (10 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback.append("File saved and modified.")
    else:
        return {"passed": False, "score": 0, "feedback": "Task failed: Output file not created or not modified."}
        
    # 2. Device Coverage (20 pts)
    # Metadata defines 23 devices. Thresholds: 15 for full pts, 8 for partial.
    found_devices = analysis.get('found_devices', [])
    num_found = len(found_devices)
    
    if num_found >= 15:
        score += 20
        feedback.append(f"Device coverage good ({num_found}/23 detected).")
    elif num_found >= 8:
        score += 10
        feedback.append(f"Device coverage partial ({num_found}/23 detected).")
    else:
        feedback.append(f"Device coverage poor ({num_found}/23 detected).")
        
    # 3. Connections/Edges (15 pts)
    # Thresholds: 12 for full, 6 for partial
    num_edges = analysis.get('num_edges', 0)
    if num_edges >= 12:
        score += 15
        feedback.append(f"Topology connectivity good ({num_edges} edges).")
    elif num_edges >= 6:
        score += 7
        feedback.append(f"Topology connectivity partial ({num_edges} edges).")
    else:
        feedback.append(f"Topology connectivity poor ({num_edges} edges).")
        
    # 4. Zone Structure (20 pts)
    # Zones: WAN, DMZ, Core, Server, Wireless, Management
    found_zones = analysis.get('found_zones', [])
    num_zones = len(found_zones)
    if num_zones >= 4:
        score += 20
        feedback.append(f"Zone structure good ({num_zones} zones found).")
    elif num_zones >= 2:
        score += 10
        feedback.append(f"Zone structure partial ({num_zones} zones found).")
    else:
        feedback.append(f"Zone structure missing or unlabeled.")
        
    # 5. Subnet/VLAN Annotations (10 pts)
    # We check if text content detected IP-table like keywords
    if analysis.get('has_ip_table'):
        score += 10
        feedback.append("IP/Subnet information detected.")
    else:
        # Fallback: check raw text length as proxy for annotations if specific keywords missed
        if analysis.get('text_content_length', 0) > 1000:
             score += 5
             feedback.append("Significant text content found (likely annotations).")
        else:
             feedback.append("Missing IP/Subnet documentation.")
             
    # 6. Multi-page (10 pts)
    if analysis.get('num_pages', 0) >= 2:
        score += 10
        feedback.append("Multi-page diagram created.")
    else:
        feedback.append("Only single page detected (requested 2).")
        
    # 7. PNG Export (15 pts)
    if result.get('png_exists') and result.get('png_size', 0) > 2000:
        score += 15
        feedback.append("PNG export successful.")
    elif result.get('png_exists'):
        score += 5
        feedback.append("PNG export exists but small.")
    else:
        feedback.append("PNG export missing.")
        
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }