#!/usr/bin/env python3
"""
Verifier for rename_case_document task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rename_case_document(traj, env_info, task_info):
    """
    Verify that the document was renamed and type updated.
    
    Criteria:
    1. API: Document name matches 'Response_Letter_March2025' (35 pts)
    2. API: Document type matches 'Correspondence' (30 pts)
    3. API: Case still has documents (integrity check) (15 pts)
    4. VLM: Visual confirmation of change (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_doc_name', 'Response_Letter_March2025')
    target_type = metadata.get('target_doc_type', 'Correspondence')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    api_data = result.get("api_data", {})
    doc_data = api_data.get("document", {})
    
    score = 0
    feedback = []
    
    # 1. Check Document Name (35 pts)
    # API might return 'documentName', 'name', or 'title'
    actual_name = doc_data.get("documentName") or doc_data.get("title") or doc_data.get("name") or ""
    if target_name.lower() in actual_name.lower():
        score += 35
        feedback.append(f"✅ Document name updated to '{actual_name}'")
    else:
        feedback.append(f"❌ Document name mismatch. Expected '{target_name}', got '{actual_name}'")

    # 2. Check Document Type (30 pts)
    actual_type = doc_data.get("documentType") or doc_data.get("type") or ""
    if target_type.lower() in actual_type.lower():
        score += 30
        feedback.append(f"✅ Document type updated to '{actual_type}'")
    else:
        feedback.append(f"❌ Document type mismatch. Expected '{target_type}', got '{actual_type}'")

    # 3. Integrity Check (15 pts)
    doc_count = api_data.get("doc_count", 0)
    if doc_count > 0 and api_data.get("doc_found"):
        score += 15
        feedback.append("✅ Case document integrity maintained")
    else:
        feedback.append("❌ Document not found in case (deleted?)")

    # 4. VLM Verification (20 pts)
    # Check if the list shows the correct info
    frames = sample_trajectory_frames(traj, n=3)
    final_shot = get_final_screenshot(traj)
    
    if final_shot:
        vlm_prompt = f"""
        Does the screenshot verify that a document in the list is named '{target_name}'?
        Also check if the 'Type' or 'Category' column shows '{target_type}'.
        Return JSON with: {{ "name_visible": bool, "type_visible": bool }}
        """
        
        vlm_res = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
        parsed = vlm_res.get("parsed", {})
        
        if parsed.get("name_visible"):
            score += 10
            feedback.append("✅ VLM confirmed name visible")
        if parsed.get("type_visible"):
            score += 10
            feedback.append("✅ VLM confirmed type visible")
    else:
        feedback.append("⚠️ No screenshots available for VLM check")

    return {
        "passed": score >= 65 and (target_name.lower() in actual_name.lower()),
        "score": score,
        "feedback": " | ".join(feedback)
    }