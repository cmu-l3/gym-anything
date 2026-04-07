#!/usr/bin/env python3
"""
Verifier for configure_doc_sequence task.

Task:
1. Create Sequence "Purchase Order 2025" (Prefix: PO25-, Start: 1000)
2. Assign to Document Type "Purchase Order"

Scoring:
- Sequence created correctly: 40 pts
- DocType linked to new sequence: 40 pts
- VLM Verification (workflow check): 20 pts
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_doc_sequence(traj, env_info, task_info):
    """
    Verify the Configure Document Sequence task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_seq_name = metadata.get('expected_seq_name', 'Purchase Order 2025')
    expected_prefix = metadata.get('expected_prefix', 'PO25-')
    expected_start_no = str(metadata.get('expected_start_no', 1000))

    score = 0
    feedback_parts = []
    passed = False

    # 1. Load result JSON from container
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

    # 2. Verify Sequence Creation (40 pts)
    seq_found = result.get('sequence_found', False)
    seq_details = result.get('sequence_details', {})
    
    if seq_found:
        # Check specific fields
        name_match = seq_details.get('name') == expected_seq_name
        prefix_match = seq_details.get('prefix') == expected_prefix
        start_match = str(seq_details.get('current_next')) == expected_start_no
        
        task_start = result.get('task_start', 0)
        updated_ts = int(seq_details.get('updated_ts', 0))
        created_during_task = updated_ts >= task_start

        if name_match and prefix_match and start_match:
            if created_during_task:
                score += 40
                feedback_parts.append(f"✅ Sequence '{expected_seq_name}' created correctly")
            else:
                score += 20
                feedback_parts.append(f"⚠️ Sequence exists but timestamp indicates pre-existence")
        else:
            score += 10
            feedback_parts.append(f"⚠️ Sequence found but details mismatch (Prefix: {seq_details.get('prefix')}, Start: {seq_details.get('current_next')})")
    else:
        feedback_parts.append(f"❌ Sequence '{expected_seq_name}' not found")

    # 3. Verify Document Type Linkage (40 pts)
    doctype_found = result.get('doctype_found', False)
    doc_details = result.get('doctype_details', {})
    
    if doctype_found:
        linked_seq_id = doc_details.get('linked_sequence_id', '')
        created_seq_id = seq_details.get('id', '')
        
        if linked_seq_id and linked_seq_id == created_seq_id:
            score += 40
            feedback_parts.append("✅ Document Type correctly linked to new sequence")
        elif linked_seq_id:
            feedback_parts.append(f"❌ Document Type linked to wrong sequence ID (Found: {linked_seq_id}, Expected: {created_seq_id})")
        else:
            feedback_parts.append("❌ Document Type has no sequence linked")
    else:
        feedback_parts.append("❌ Target Document Type not found")

    # 4. VLM Verification (20 pts)
    # Check if agent was actually interacting with Sequence/DocType windows
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of an agent using iDempiere ERP.
        The agent should be:
        1. Configuring a 'Sequence' (entering 'PO25-' or '1000').
        2. Modifying a 'Document Type' record.
        
        Do you see the 'Sequence' window or 'Document Type' window open in any frame?
        Do you see data entry related to 'Purchase Order 2025'?
        
        Return JSON: {"evidence_found": true/false, "confidence": "high/medium/low"}
        """
        
        try:
            vlm_response = query_vlm(images=frames + [final_shot], prompt=prompt)
            if vlm_response.get('parsed', {}).get('evidence_found', False):
                vlm_score = 20
                feedback_parts.append("✅ VLM confirms configuration workflow")
            else:
                feedback_parts.append("⚠️ VLM could not visually confirm workflow")
        except Exception as e:
            logger.error(f"VLM error: {e}")
    
    score += vlm_score

    # Final Pass Logic
    # Must have created sequence AND linked it to pass
    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }