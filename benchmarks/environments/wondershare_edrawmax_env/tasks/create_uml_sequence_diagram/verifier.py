#!/usr/bin/env python3
"""
Verifier for create_uml_sequence_diagram task.

Verification Strategy:
1. Programmatic (File & Content):
   - Check existence and timestamps of .eddx and .png files.
   - Unzip .eddx (which is a ZIP archive) and parse XML content.
   - Verify presence of specific participant names and message labels in the XML.
   
2. Visual (VLM):
   - Analyze the exported PNG (created by the agent).
   - Verify the structure looks like a sequence diagram (lifelines, arrows).
   - Verify 6 lifelines and sequence of messages.
   - Check for title.

Scoring:
- Files exist & valid: 30 pts
- XML Content (Participants): 20 pts
- XML Content (Messages): 20 pts
- VLM Visual Verification: 30 pts
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_uml_sequence_diagram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_participants = metadata.get('required_participants', [])
    required_messages = metadata.get('required_messages', [])
    
    # Files to verify
    eddx_path_remote = metadata.get('expected_eddx_path', '/home/ga/Documents/payment_sequence_diagram.eddx')
    png_path_remote = metadata.get('expected_png_path', '/home/ga/Documents/payment_sequence_diagram.png')
    
    # Load task result JSON
    result_remote_path = "/tmp/task_result.json"
    result_local = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    
    try:
        copy_from_env(result_remote_path, result_local)
        with open(result_local, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(result_local):
            os.unlink(result_local)

    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. File Existence & Integrity (30 pts)
    # =========================================================
    eddx_exists = task_result.get('eddx_exists', False)
    eddx_valid_time = task_result.get('eddx_created_during_task', False)
    eddx_size = task_result.get('eddx_size_bytes', 0)
    
    png_exists = task_result.get('png_exists', False)
    png_valid_time = task_result.get('png_created_during_task', False)
    png_size = task_result.get('png_size_bytes', 0)
    
    files_ok = False
    if eddx_exists and eddx_valid_time and eddx_size > 2000:
        score += 15
        feedback_parts.append(f"EDDX file saved ({eddx_size} bytes)")
        if png_exists and png_valid_time and png_size > 5000:
            score += 15
            feedback_parts.append(f"PNG export saved ({png_size} bytes)")
            files_ok = True
        else:
            feedback_parts.append("PNG export missing or too small")
    else:
        feedback_parts.append("EDDX file missing or invalid")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # =========================================================
    # 2. Content Verification via XML Parsing (40 pts)
    # =========================================================
    # Download EDDX file to inspect content
    eddx_local = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx').name
    try:
        copy_from_env(eddx_path_remote, eddx_local)
        
        # Read XML content from ZIP
        full_xml_content = ""
        try:
            with zipfile.ZipFile(eddx_local, 'r') as zf:
                for name in zf.namelist():
                    if name.endswith('.xml'):
                        try:
                            full_xml_content += zf.read(name).decode('utf-8', errors='ignore')
                        except:
                            pass
        except zipfile.BadZipFile:
            feedback_parts.append("EDDX is not a valid zip archive")
            
        # Check Participants (20 pts)
        found_participants = []
        for p in required_participants:
            if p in full_xml_content:
                found_participants.append(p)
        
        part_score = 0
        if len(found_participants) == len(required_participants):
            part_score = 20
        else:
            part_score = int(20 * (len(found_participants) / len(required_participants)))
        
        score += part_score
        feedback_parts.append(f"Found {len(found_participants)}/{len(required_participants)} participants")
        
        # Check Messages (20 pts)
        found_messages = []
        for m in required_messages:
            # Simple check for label presence
            # Some labels might be escaped in XML, but standard ASCII usually isn't
            if m in full_xml_content:
                found_messages.append(m)
        
        msg_score = 0
        if len(found_messages) == len(required_messages):
            msg_score = 20
        else:
            msg_score = int(20 * (len(found_messages) / len(required_messages)))
            
        score += msg_score
        feedback_parts.append(f"Found {len(found_messages)}/{len(required_messages)} message labels")
        
    except Exception as e:
        feedback_parts.append(f"Content check failed: {e}")
    finally:
        if os.path.exists(eddx_local):
            os.unlink(eddx_local)

    # =========================================================
    # 3. Visual Verification via VLM (30 pts)
    # =========================================================
    # We use the exported PNG for this check as it's the final visual result
    png_local = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    vlm_score = 0
    
    try:
        copy_from_env(png_path_remote, png_local)
        
        # VLM Query
        prompt = """
        You are grading a UML Sequence Diagram created by an agent.
        
        Required Elements:
        1. 6 vertical 'lifelines' (dashed lines dropping from boxes at the top).
        2. Horizontal arrows connecting these lines.
        3. A title 'Payment Processing Sequence Diagram'.
        4. Specific labels on lifelines: User, Web Frontend, API Gateway, Payment Service, Fraud Detection, Bank API.
        
        Does the image show a valid sequence diagram with these elements?
        Is it legible and not blank?
        
        Return JSON:
        {
            "is_sequence_diagram": true/false,
            "lifeline_count_approx": number,
            "has_arrows": true/false,
            "title_visible": true/false,
            "labels_readable": true/false,
            "quality_assessment": "string"
        }
        """
        
        result = query_vlm(prompt=prompt, image=png_local)
        
        if result and result.get('success'):
            parsed = result.get('parsed', {})
            
            if parsed.get('is_sequence_diagram', False):
                vlm_score += 10
            
            # Allow some flexibility in counting via VLM
            count = parsed.get('lifeline_count_approx', 0)
            if 5 <= count <= 7:
                vlm_score += 10
            elif count > 0:
                vlm_score += 5
                
            if parsed.get('has_arrows', False):
                vlm_score += 5
                
            if parsed.get('labels_readable', False) or parsed.get('title_visible', False):
                vlm_score += 5
                
            feedback_parts.append(f"VLM Assessment: {parsed.get('quality_assessment', 'N/A')}")
        else:
            feedback_parts.append("VLM query failed")
            
    except Exception as e:
        feedback_parts.append(f"Visual check failed: {e}")
    finally:
        if os.path.exists(png_local):
            os.unlink(png_local)
            
    score += vlm_score

    # Final Pass/Fail
    # Pass if files exist (30), content is decent (>20), and visual check passed (>10)
    passed = (score >= 60) and files_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }