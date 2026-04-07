#!/usr/bin/env python3
"""
Verifier for branch_prune_variant task.

Criteria:
1. SRS-LITE document exists (30 pts)
2. SRS-LITE name is "Lite System Requirements" (20 pts)
3. SRS-LITE does NOT contain "Log Files" section (30 pts)
4. SRS (original) STILL contains "Log Files" section (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Paths relative to the project structure in the container
# We need to list the directory to find the actual project path if specific logic is needed,
# but the setup script defines it as:
PROJECT_DIR = "/home/ga/Documents/ReqView/branch_prune_project"
SRS_PATH = f"{PROJECT_DIR}/documents/SRS.json"
LITE_PATH = f"{PROJECT_DIR}/documents/SRS-LITE.json"

def _load_json_from_env(copy_func, remote_path):
    """Helper to copy and load a JSON file from the environment."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_func(remote_path, tmp.name)
        with open(tmp.name, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load {remote_path}: {e}")
        return None
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def _has_section(doc_data, section_name):
    """Recursively checks if a section with specific text/heading exists."""
    if not doc_data:
        return False
    
    # ReqView document structure: root dict has 'data' list of children
    items = doc_data if isinstance(doc_data, list) else doc_data.get('data', [])
    
    for item in items:
        # Check heading or text
        heading = item.get('heading', '')
        text = item.get('text', '')
        
        # Simple containment check
        if section_name.lower() in heading.lower() or section_name.lower() in text.lower():
            return True
            
        # Check children
        if 'children' in item:
            if _has_section(item['children'], section_name):
                return True
                
    return False

def verify_branch_prune_variant(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_doc_name', "Lite System Requirements")
    pruned_section = metadata.get('pruned_section_name', "Log Files")

    score = 0
    feedback = []

    # 1. Check SRS-LITE existence (30 pts)
    lite_doc = _load_json_from_env(copy_from_env, LITE_PATH)
    if lite_doc:
        score += 30
        feedback.append("SRS-LITE document created.")
    else:
        feedback.append("SRS-LITE document NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Check SRS-LITE Name (20 pts)
    # The document name is usually stored in the 'name' field of the document JSON
    actual_name = lite_doc.get('name', '')
    if target_name.lower() in actual_name.lower():
        score += 20
        feedback.append(f"Document named correctly ('{actual_name}').")
    else:
        feedback.append(f"Document name incorrect. Expected '{target_name}', got '{actual_name}'.")

    # 3. Check Pruning (30 pts)
    if not _has_section(lite_doc, pruned_section):
        score += 30
        feedback.append(f"Section '{pruned_section}' successfully removed from LITE.")
    else:
        feedback.append(f"Section '{pruned_section}' still present in LITE document.")

    # 4. Check Original Integrity (20 pts)
    srs_doc = _load_json_from_env(copy_from_env, SRS_PATH)
    if srs_doc:
        if _has_section(srs_doc, pruned_section):
            score += 20
            feedback.append(f"Original SRS intact (contains '{pruned_section}').")
        else:
            feedback.append(f"Original SRS was modified! '{pruned_section}' is missing.")
    else:
        feedback.append("Could not verify original SRS (file read error).")

    # Final logic
    passed = (score >= 80) # Must have created doc + pruned section at minimum
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }