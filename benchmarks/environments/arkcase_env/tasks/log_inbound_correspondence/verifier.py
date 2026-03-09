#!/usr/bin/env python3
"""
Verifier for log_inbound_correspondence task.

Verifies:
1. New correspondence record created (API)
2. Subject/Title matches email (API)
3. Content/Body contains email text (API)
4. Attachment exists (API)
5. Inbound direction/category set correctly (API)
6. VLM Verification of UI state (Trajectory)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_log_inbound_correspondence(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject', "Urgent: Construction Violation Report")
    expected_content = metadata.get('expected_content_snippet', "violation of the city noise ordinance")

    # Load Result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    initial_count = int(result.get('initial_count', 0))
    final_count = int(result.get('final_count', 0))
    correspondence_list = result.get('correspondence_data', [])

    # === CRITERION 1: Record Created (20 pts) ===
    if final_count > initial_count:
        score += 20
        feedback_parts.append("✅ New correspondence record created")
    else:
        feedback_parts.append("❌ No new correspondence record found")

    # Analyze the new/matching record
    target_record = None
    # Strategy: Look for the record that matches our expected subject
    for record in correspondence_list:
        # Check standard ArkCase fields: subject, title, name
        rec_subject = record.get('subject') or record.get('title') or record.get('name') or ""
        if expected_subject.lower() in str(rec_subject).lower():
            target_record = record
            break
    
    # If not found by subject, try finding by content if count increased
    if not target_record and final_count > initial_count:
        # Assume the last added record is the one
        target_record = correspondence_list[-1] if correspondence_list else None

    if target_record:
        # === CRITERION 2: Correct Subject (20 pts) ===
        rec_subject = target_record.get('subject') or target_record.get('title') or ""
        if expected_subject.lower() in str(rec_subject).lower():
            score += 20
            feedback_parts.append(f"✅ Subject correct: '{rec_subject}'")
        else:
            feedback_parts.append(f"❌ Subject mismatch. Expected '{expected_subject}', got '{rec_subject}'")

        # === CRITERION 3: Inbound/Direction (15 pts) ===
        # Check direction, category, or type fields
        direction = str(target_record.get('direction', '')).upper()
        category = str(target_record.get('category', '')).upper()
        if "INBOUND" in direction or "INBOUND" in category or "FROM" in direction:
            score += 15
            feedback_parts.append("✅ Direction set to Inbound")
        else:
            # Partial credit if direction is at least set
            if direction:
                score += 5
                feedback_parts.append(f"⚠️ Direction is '{direction}' (Expected Inbound)")
            else:
                feedback_parts.append("❌ Direction not specified")

        # === CRITERION 4: Body Content (15 pts) ===
        description = str(target_record.get('description') or target_record.get('body') or target_record.get('details') or "")
        if expected_content.lower() in description.lower():
            score += 15
            feedback_parts.append("✅ Body text transcribed correctly")
        else:
            feedback_parts.append("❌ Body text missing or incomplete")

        # === CRITERION 5: Attachment (30 pts) ===
        has_attachments = target_record.get('hasAttachments', False)
        attachments = target_record.get('attachments', [])
        
        # Sometimes attachments are a count or a list
        is_attached = has_attachments or (isinstance(attachments, list) and len(attachments) > 0)
        
        if is_attached:
            score += 30
            feedback_parts.append("✅ File attached")
        else:
            feedback_parts.append("❌ No file attached to record")

    else:
        feedback_parts.append("❌ Could not locate the specific correspondence record")

    # === VLM VERIFICATION (Backup/Confirmation) ===
    # Use VLM if API scoring is ambiguous or just to confirm UI state
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    if score < 70 and final_img:
        # If API check failed (maybe API structure changed?), try VLM rescue
        vlm_prompt = f"""
        Does the screenshot show a correspondence or email record in ArkCase?
        Look for:
        1. Subject: '{expected_subject}'
        2. Sender: 'Alice Neighbor'
        3. An attachment icon or file named 'evidence_email.eml'
        """
        try:
            vlm_res = query_vlm(prompt=vlm_prompt, images=frames + [final_img])
            if vlm_res.get('success'):
                analysis = vlm_res.get('parsed', {}).get('analysis', '').lower()
                if "yes" in analysis or "shows" in analysis:
                    score = max(score, 60) # Rescue score
                    feedback_parts.append("⚠️ API check failed but VLM confirmed visual presence (+Rescue Points)")
        except Exception:
            pass

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }