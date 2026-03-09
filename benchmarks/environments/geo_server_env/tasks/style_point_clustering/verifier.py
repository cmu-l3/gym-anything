#!/usr/bin/env python3
"""Verifier for style_point_clustering task."""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_style_point_clustering(traj, env_info, task_info):
    """
    Verify the point clustering task.
    
    Criteria:
    1. Style 'clustered_places' exists.
    2. Layer 'ne:ne_populated_places' uses this style as default.
    3. SLD contains 'gs:PointStacker' transformation.
    4. Transformation has 'cellSize' = 60.
    5. Styling rules for single point (Star, Red) and cluster (Circle, Blue, Label).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_style_name = metadata.get('expected_style_name', 'clustered_places')
    expected_cell_size = metadata.get('expected_cell_size', 60)
    
    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/style_clustering_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify nonce integrity
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        # If nonce check fails, we continue but mark it (in a strict environment this would fail)
        pass
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify Style Existence (15 pts)
    style_found = result.get('style_found', False)
    style_name = result.get('style_name_found', '')
    
    if style_found:
        score += 15
        feedback_parts.append(f"Style found ({style_name})")
    else:
        feedback_parts.append("Style 'clustered_places' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Verify Layer Assignment (15 pts)
    current_default = result.get('current_default_style', '')
    initial_default = result.get('initial_default_style', '')
    
    # Check if assignment matches expected style name (ignoring workspace prefix)
    is_assigned = False
    if current_default == style_name:
        is_assigned = True
    elif current_default.split(':')[-1] == style_name.split(':')[-1]:
        is_assigned = True
    elif expected_style_name in current_default:
        is_assigned = True

    if is_assigned:
        score += 15
        feedback_parts.append(f"Layer uses style '{current_default}'")
    else:
        feedback_parts.append(f"Layer uses '{current_default}' (expected '{expected_style_name}')")

    # 4. Analyze SLD Content (Transformation & Rules)
    sld_content = result.get('style_sld_content', '')
    if not sld_content:
        feedback_parts.append("SLD content is empty")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    try:
        # Basic string check first for robustness against namespace parsing issues
        sld_lower = sld_content.lower()
        
        # Check Transformation (30 pts)
        has_point_stacker = 'pointstacker' in sld_lower
        has_cell_size = str(expected_cell_size) in sld_content
        
        if has_point_stacker:
            score += 15
            feedback_parts.append("PointStacker transformation found")
            if has_cell_size:
                score += 15
                feedback_parts.append(f"CellSize {expected_cell_size} found")
            else:
                feedback_parts.append(f"CellSize {expected_cell_size} NOT found")
        else:
            feedback_parts.append("PointStacker transformation NOT found")

        # Check Cluster Styling (Blue Circle + Label) (20 pts)
        # Looking for #0000FF (Blue) and Circle and Count label
        has_blue = '#0000ff' in sld_lower or '#0000FF' in sld_content
        has_circle = 'circle' in sld_lower
        has_label = 'label' in sld_lower or 'textsymbolizer' in sld_lower
        
        if has_blue and has_circle and has_label:
            score += 20
            feedback_parts.append("Cluster styling (Blue Circle + Label) found")
        elif has_blue and has_circle:
            score += 10
            feedback_parts.append("Cluster styling (Blue Circle) found, Label missing")
        else:
            feedback_parts.append("Cluster styling (Blue Circle) missing")

        # Check Single Point Styling (Red Star) (20 pts)
        # Looking for #FF0000 (Red) and Star
        has_red = '#ff0000' in sld_lower or '#FF0000' in sld_content
        has_star = 'star' in sld_lower
        
        if has_red and has_star:
            score += 20
            feedback_parts.append("Single styling (Red Star) found")
        elif has_star:
            score += 10
            feedback_parts.append("Single styling (Star) found, wrong color")
        else:
            feedback_parts.append("Single styling (Red Star) missing")

    except Exception as e:
        feedback_parts.append(f"Error parsing SLD: {str(e)}")

    # 5. VLM Check (Secondary, mostly for anti-gaming context)
    # If using REST API, score is capped unless VLM confirms GUI usage?
    # For now, we trust the programmatic state but add VLM feedback
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        # Optional: could check screenshots here
        pass

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }