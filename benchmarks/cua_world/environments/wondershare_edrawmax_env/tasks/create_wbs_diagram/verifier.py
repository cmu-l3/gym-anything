#!/usr/bin/env python3
"""
Verifier for create_wbs_diagram task.

Criteria:
1. Files (.eddx and .png) exist and were created during the task.
2. Content Verification: .eddx file (XML) contains the required text labels.
3. Visual Verification: VLM confirms hierarchical structure and connectors.
"""

import json
import os
import tempfile
import zipfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utils (provided by framework)
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utils not available")


def verify_eddx_content(eddx_path: str, metadata: Dict[str, Any]) -> Dict[str, Any]:
    """Parse .eddx (ZIP) and check for required text labels."""
    score = 0
    details = []
    
    root_label = metadata.get("root_label", "")
    phases = metadata.get("phases", [])
    work_packages = metadata.get("work_packages", [])
    
    # Extract all text from XML/JSON files inside the .eddx zip
    all_text = ""
    try:
        with zipfile.ZipFile(eddx_path, "r") as zf:
            for name in zf.namelist():
                if name.endswith(".xml") or name.endswith(".json"):
                    try:
                        content = zf.read(name).decode("utf-8", errors="ignore")
                        all_text += content + "\n"
                    except Exception:
                        pass
    except zipfile.BadZipFile:
        return {"score": 0, "details": ["Invalid EDDX file format"], "text_found": False}
    except Exception as e:
        return {"score": 0, "details": [f"Error reading EDDX: {str(e)}"], "text_found": False}
    
    # Normalize for case-insensitive search
    all_text_lower = all_text.lower()
    
    # Check Root (8 pts)
    if root_label.lower() in all_text_lower:
        score += 8
        details.append(f"Found root: '{root_label}'")
    else:
        details.append(f"Missing root: '{root_label}'")
        
    # Check Phases (3 pts each, max 18)
    phases_found = 0
    for phase in phases:
        if phase.lower() in all_text_lower:
            score += 3
            phases_found += 1
    details.append(f"Found {phases_found}/{len(phases)} phases")
    
    # Check Work Packages (1.5 pts each, max 27 -> capped at 24 in scoring logic below)
    wp_found = 0
    for wp in work_packages:
        if wp.lower() in all_text_lower:
            score += 1.5
            wp_found += 1
    details.append(f"Found {wp_found}/{len(work_packages)} work packages")
    
    # Cap content score at 50 points total
    # (8 + 18 + 27 = 53 max possible raw, cap at 50)
    final_content_score = min(score, 50)
    
    return {
        "score": final_content_score,
        "details": details,
        "text_found": True,
        "raw_stats": {"root": 1 if root_label.lower() in all_text_lower else 0, "phases": phases_found, "wp": wp_found}
    }


def verify_visuals(traj: List[Any], png_path: str) -> Dict[str, Any]:
    """Use VLM to verify the diagram structure."""
    if not VLM_AVAILABLE:
        return {"score": 0, "feedback": "VLM not available", "passed": False}

    # Prepare prompt
    prompt = """
    You are evaluating a Work Breakdown Structure (WBS) diagram created by an agent.
    
    The diagram should show:
    1. A hierarchical tree structure (not just a list or random shapes).
    2. A single root node at the top or left.
    3. Multiple levels of child nodes branching out.
    4. Connectors (lines) visible between parents and children.
    
    Look at the provided image (either the exported PNG or the final screenshot).
    
    Question: Does this look like a valid hierarchical WBS diagram with multiple levels and connectors?
    
    Respond in JSON:
    {
        "is_hierarchical_tree": true/false,
        "has_connectors": true/false,
        "has_multiple_levels": true/false,
        "root_node_distinct": true/false,
        "confidence": "low/medium/high",
        "reasoning": "brief explanation"
    }
    """
    
    # Try using the exported PNG first (if available in the trajectory/env, 
    # but here we rely on the final screenshot captured by framework for safety)
    # Ideally, we'd inspect the png_path file, but we can't easily pass that to VLM 
    # without copying it back. Using framework screenshots is safer.
    
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, 3)
    
    images_to_check = frames + ([final_screenshot] if final_screenshot else [])
    
    if not images_to_check:
        return {"score": 0, "feedback": "No screenshots available for VLM", "passed": False}

    result = query_vlm(prompt=prompt, images=images_to_check)
    
    if not result.get("success"):
        return {"score": 0, "feedback": f"VLM query failed: {result.get('error')}", "passed": False}
        
    parsed = result.get("parsed", {})
    
    criteria_met = sum([
        parsed.get("is_hierarchical_tree", False),
        parsed.get("has_connectors", False),
        parsed.get("has_multiple_levels", False)
    ])
    
    # Calculate score (max 30)
    vlm_score = 0
    if criteria_met >= 3:
        vlm_score = 30
    elif criteria_met == 2:
        vlm_score = 20
    elif criteria_met == 1:
        vlm_score = 10
        
    return {
        "score": vlm_score,
        "feedback": parsed.get("reasoning", "VLM analysis complete"),
        "passed": criteria_met >= 2
    }


def verify_create_wbs_diagram(traj, env_info, task_info):
    """
    Main verification entry point.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Paths in container
    eddx_path = metadata.get('eddx_path', '/home/ga/Diagrams/erp_migration_wbs.eddx')
    png_path = metadata.get('png_path', '/home/ga/Diagrams/erp_migration_wbs.png')
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Task Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            tmp.seek(0)
            task_result = json.load(tmp)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

    # 2. File Verification (Max 20 pts)
    # EDDX File
    if task_result.get("eddx_exists") and task_result.get("eddx_created_during_task") and task_result.get("eddx_size", 0) > 1000:
        score += 10
        feedback_parts.append("EDDX file created successfully")
    elif task_result.get("eddx_exists"):
        score += 5 # Exists but maybe stale or empty
        feedback_parts.append("EDDX file exists but timestamp/size verification failed")
    else:
        feedback_parts.append("EDDX file NOT found")
        
    # PNG File
    if task_result.get("png_exists") and task_result.get("png_created_during_task") and task_result.get("png_size", 0) > 1000:
        score += 10
        feedback_parts.append("PNG exported successfully")
    else:
        feedback_parts.append("PNG export NOT found or invalid")

    # 3. Content Verification (Max 50 pts)
    # We need to copy the .eddx file to host to parse it
    content_score = 0
    if task_result.get("eddx_exists"):
        with tempfile.NamedTemporaryFile(suffix='.eddx') as tmp_eddx:
            try:
                copy_from_env(eddx_path, tmp_eddx.name)
                content_result = verify_eddx_content(tmp_eddx.name, metadata)
                content_score = content_result["score"]
                score += content_score
                feedback_parts.extend(content_result["details"])
            except Exception as e:
                feedback_parts.append(f"Failed to verify EDDX content: {e}")
    
    # 4. Visual Verification (Max 30 pts)
    visual_result = verify_visuals(traj, png_path)
    score += visual_result["score"]
    feedback_parts.append(f"Visual check: {visual_result['feedback']}")
    
    # Final Pass/Fail Logic
    # Pass if Score >= 60 AND critical files exist AND reasonable content found
    passed = (score >= 60 and 
              task_result.get("eddx_exists") and 
              task_result.get("png_exists") and
              content_score >= 20) # Must have found at least ~20 pts worth of text labels
              
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }