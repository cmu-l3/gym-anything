#!/usr/bin/env python3
"""
Verifier for stride_threat_model_dfd task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stride_threat_model_dfd(traj, env_info, task_info):
    """
    Verify the DFD and STRIDE threat model creation.
    
    Criteria:
    1. File creation/modification (10 pts)
    2. Component coverage (20 pts) - Keyword matching
    3. Data flow complexity (15 pts) - Edge count
    4. Trust boundaries (15 pts) - Dashed containers
    5. Multi-page structure (10 pts)
    6. STRIDE threat catalog (15 pts) - Keywords
    7. PNG Export (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    min_components = metadata.get('min_components', 10)
    min_flows = metadata.get('min_flows', 12)
    min_boundaries = metadata.get('min_boundaries', 3)

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

    # 1. File Sanity (10 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback.append("File saved successfully")
    elif result.get('file_exists'):
        score += 5
        feedback.append("File exists but timestamp check failed (stale?)")
    else:
        feedback.append("FAIL: No .drawio file found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Components (20 pts)
    comps_found = len(analysis.get('components_found', []))
    if comps_found >= min_components:
        score += 20
        feedback.append(f"Components: {comps_found}/{min_components} found (Good)")
    elif comps_found >= 5:
        score += 10
        feedback.append(f"Components: {comps_found}/{min_components} found (Partial)")
    else:
        feedback.append(f"Components: Only {comps_found} found (Insufficient)")

    # 3. Data Flows (15 pts)
    edges = analysis.get('num_edges', 0)
    if edges >= min_flows:
        score += 15
        feedback.append(f"Data Flows: {edges} edges (Good)")
    elif edges >= 5:
        score += 7
        feedback.append(f"Data Flows: {edges} edges (Partial)")
    else:
        feedback.append(f"Data Flows: Only {edges} edges (Insufficient)")

    # 4. Trust Boundaries (15 pts)
    dashed = analysis.get('num_dashed_containers', 0)
    if dashed >= min_boundaries:
        score += 15
        feedback.append(f"Trust Boundaries: {dashed} dashed zones (Good)")
    elif dashed >= 1:
        score += 7
        feedback.append(f"Trust Boundaries: {dashed} dashed zones (Partial)")
    else:
        feedback.append("Trust Boundaries: None found (need dashed containers)")

    # 5. Multi-page (10 pts)
    pages = analysis.get('num_pages', 0)
    if pages >= 2:
        score += 10
        feedback.append("Pages: Multi-page diagram created")
    else:
        feedback.append("Pages: Single page only (expected 2)")

    # 6. STRIDE Catalog (15 pts)
    stride_kw = len(analysis.get('stride_keywords_found', []))
    if stride_kw >= 4:
        score += 15
        feedback.append(f"Threat Catalog: {stride_kw} STRIDE keywords found")
    elif stride_kw >= 2:
        score += 7
        feedback.append(f"Threat Catalog: Partial STRIDE keywords ({stride_kw})")
    else:
        feedback.append("Threat Catalog: No STRIDE keywords found")

    # 7. PNG Export (15 pts)
    if result.get('png_exists'):
        size = result.get('png_size', 0)
        if size > 5000:
            score += 15
            feedback.append("PNG exported valid")
        else:
            score += 5
            feedback.append(f"PNG exported but too small ({size} bytes)")
    else:
        feedback.append("PNG export missing")

    # Final logic
    passed = score >= 60 and comps_found >= 5 and edges >= 5
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }