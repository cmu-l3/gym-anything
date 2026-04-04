#!/usr/bin/env python3
"""
Verifier for datacenter_rack_elevation task.

Scoring (100 points total):
- File saved and modified: 10 pts
- Hostname accuracy: 30 pts (3 pts per correct hostname found)
- Vendor/Model accuracy: 15 pts (Dell, Cisco, APC keywords)
- Visual Elements:
  - Color coding used: 10 pts
  - Legend present: 5 pts
  - Rack ID/Title correct: 10 pts
  - Sufficient shapes (equip + rack): 10 pts
- Export:
  - Valid PNG export: 10 pts

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_rack_elevation(traj, env_info, task_info):
    """Verify the rack elevation diagram."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    analysis = result.get('analysis', {})
    score = 0
    feedback = []
    
    # 1. File saved (10 pts)
    if result.get('file_exists') and result.get('file_modified_after_start'):
        score += 10
        feedback.append("File saved successfully.")
    elif result.get('file_exists'):
        feedback.append("File exists but was not modified (0 pts).")
    else:
        return {"passed": False, "score": 0, "feedback": "No diagram file found."}
        
    # 2. Hostnames (30 pts)
    found_hosts = analysis.get('hostnames_found', [])
    unique_hosts = set(found_hosts)
    host_score = min(30, len(unique_hosts) * 3)
    score += host_score
    feedback.append(f"Hostnames found: {len(unique_hosts)}/10 ({host_score} pts)")
    if len(unique_hosts) < 5:
        feedback.append("Missing many hostnames (e.g., web01, sw-tor-a).")
        
    # 3. Vendor Keywords (15 pts)
    found_keywords = set(analysis.get('vendor_keywords', []))
    vendor_score = 0
    
    has_cisco = any(k in found_keywords for k in ['cisco', 'catalyst'])
    has_dell = any(k in found_keywords for k in ['dell', 'poweredge'])
    has_apc = any(k in found_keywords for k in ['apc', 'smart-ups', 'ups'])
    
    if has_cisco: vendor_score += 5
    if has_dell: vendor_score += 5
    if has_apc: vendor_score += 5
    
    score += vendor_score
    feedback.append(f"Equipment types identified: {vendor_score}/15 pts (Cisco:{has_cisco}, Dell:{has_dell}, APC:{has_apc})")
    
    # 4. Color Coding (10 pts)
    colors = analysis.get('distinct_colors', 0)
    if colors >= 3:
        score += 10
        feedback.append(f"Color coding used ({colors} colors detected).")
    elif colors >= 1:
        score += 5
        feedback.append("Minimal color coding used.")
    else:
        feedback.append("No color coding detected (monochrome?).")
        
    # 5. Legend (5 pts)
    if analysis.get('has_legend'):
        score += 5
        feedback.append("Legend found.")
    else:
        feedback.append("Legend missing.")
        
    # 6. Rack ID / Title (10 pts)
    if analysis.get('rack_id_found'):
        score += 10
        feedback.append("Rack ID 'RK-NYC-042' found.")
    elif analysis.get('has_title'):
        score += 5
        feedback.append("Location title found, but Rack ID missing.")
    else:
        feedback.append("Rack ID/Title missing.")
        
    # 7. Shape Count (10 pts)
    # 14 items + 1 rack + legend items -> expect > 15 shapes
    num_shapes = analysis.get('num_shapes', 0)
    if num_shapes >= 12:
        score += 10
        feedback.append(f"Sufficient shapes count ({num_shapes}).")
    elif num_shapes >= 6:
        score += 5
        feedback.append(f"Low shape count ({num_shapes}).")
    else:
        feedback.append("Diagram appears empty.")
        
    # 8. PNG Export (10 pts)
    if result.get('png_exists') and result.get('png_size', 0) > 1000:
        score += 10
        feedback.append("PNG export successful.")
    else:
        feedback.append("PNG export missing or empty.")
        
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }