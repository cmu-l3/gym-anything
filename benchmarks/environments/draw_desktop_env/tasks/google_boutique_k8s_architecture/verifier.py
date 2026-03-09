#!/usr/bin/env python3
"""
Verifier for google_boutique_k8s_architecture task.

Criteria:
1. Drawio file exists and modified (5 pts)
2. PNG export exists and valid size (15 pts)
3. 9+ of 11 services identified (25 pts)
4. Redis data store found (5 pts)
5. 12+ connection edges (15 pts)
6. Protocols (gRPC/HTTP) labeled (10 pts)
7. Namespace group/container used (10 pts)
8. Ingress/Gateway shape used (5 pts)
9. Two diagram pages created (10 pts)

Pass Threshold: 60/100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_boutique_architecture(traj, env_info, task_info):
    """Verify the Google Boutique architecture diagram."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}
    
    # Load result
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
            
    analysis = result.get('analysis', {})
    score = 0
    feedback = []
    
    # 1. File existence (5 pts)
    if result.get('file_exists') and result.get('file_modified_after_start'):
        score += 5
        feedback.append("Drawio file saved")
    else:
        feedback.append("Drawio file missing or not saved")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
        
    # 2. PNG Export (15 pts)
    png_size = result.get('png_size', 0)
    if result.get('png_exists') and png_size > 2000:
        score += 15
        feedback.append("PNG exported")
    elif result.get('png_exists'):
        score += 5
        feedback.append(f"PNG exported but small ({png_size} bytes)")
    else:
        feedback.append("PNG export missing")
        
    # 3. Services Found (25 pts)
    found_services = analysis.get('found_services', [])
    unique_services = set(found_services)
    count = len(unique_services)
    
    if count >= 9:
        score += 25
        feedback.append(f"Services: {count}/11 found")
    elif count >= 7:
        score += 15
        feedback.append(f"Services: {count}/11 found (partial)")
    elif count >= 4:
        score += 8
        feedback.append(f"Services: {count}/11 found (low)")
    else:
        feedback.append(f"Services: only {count} found")
        
    # 4. Redis (5 pts)
    if analysis.get('found_redis'):
        score += 5
        feedback.append("Redis found")
    else:
        feedback.append("Redis missing")
        
    # 5. Edges (15 pts)
    num_edges = analysis.get('num_edges', 0)
    if num_edges >= 12:
        score += 15
        feedback.append(f"Edges: {num_edges}")
    elif num_edges >= 8:
        score += 10
        feedback.append(f"Edges: {num_edges} (partial)")
    elif num_edges >= 4:
        score += 5
        feedback.append(f"Edges: {num_edges} (low)")
    else:
        feedback.append("Edges missing")
        
    # 6. Protocols (10 pts)
    protocols = analysis.get('found_protocols', [])
    if 'grpc' in protocols and 'http' in protocols:
        score += 10
        feedback.append("Protocols: gRPC & HTTP found")
    elif len(protocols) > 0:
        score += 5
        feedback.append(f"Protocols: {', '.join(protocols)} found")
    else:
        feedback.append("Protocols missing")
        
    # 7. Namespace Group (10 pts)
    if analysis.get('has_namespace_group'):
        score += 10
        feedback.append("Namespace group found")
    else:
        feedback.append("Namespace group missing")
        
    # 8. Ingress (5 pts)
    if analysis.get('found_ingress'):
        score += 5
        feedback.append("Ingress found")
    else:
        feedback.append("Ingress missing")
        
    # 9. Pages (10 pts)
    num_pages = analysis.get('num_pages', 0)
    if num_pages >= 2:
        score += 10
        feedback.append("Multi-page diagram")
    else:
        feedback.append("Single page only")
        
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }