#!/usr/bin/env python3
"""
Verifier for complete_new_hire_documentation task.
"""

import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

def verify_complete_new_hire_documentation(traj, env_info, task_info):
    """
    Verifies that the agent uploaded the correct profile photo and attachments
    for James Anderson in OrangeHRM.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    photo_uploaded = result.get('photo_uploaded', False)
    attachments = result.get('attachments', [])
    
    score = 0
    feedback = []
    
    # 3. Evaluate Profile Picture (30 points)
    if photo_uploaded:
        score += 30
        feedback.append("Profile picture updated successfully.")
    else:
        feedback.append("Profile picture was NOT updated.")

    # 4. Evaluate Attachments (40 points total)
    # Expected: 'signed_offer.pdf' and 'nda_signed.pdf'
    
    offer_found = False
    offer_comment_ok = False
    nda_found = False
    nda_comment_ok = False
    
    for att in attachments:
        fname = att.get('filename', '').lower()
        desc = att.get('description', '').lower()
        
        # Check for Offer Letter
        if 'signed_offer.pdf' in fname:
            offer_found = True
            if 'offer' in desc:
                offer_comment_ok = True
        
        # Check for NDA
        if 'nda_signed.pdf' in fname:
            nda_found = True
            if 'nda' in desc:
                nda_comment_ok = True

    # Scoring logic for files
    if offer_found:
        score += 20
        feedback.append("Offer letter attached.")
        if offer_comment_ok:
            score += 10
            feedback.append("Offer letter comment is correct.")
        else:
            feedback.append("Offer letter comment missing keyword 'Offer'.")
    else:
        feedback.append("Offer letter attachment NOT found.")

    if nda_found:
        score += 20
        feedback.append("NDA attached.")
        if nda_comment_ok:
            score += 10
            feedback.append("NDA comment is correct.")
        else:
            feedback.append("NDA comment missing keyword 'NDA'.")
    else:
        feedback.append("NDA attachment NOT found.")

    # 5. VLM Verification (10 points - Trajectory Check)
    # We want to see if the agent actually visited the attachments page
    # This acts as an anti-gaming check and visual confirmation
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        if final_shot:
            frames.append(final_shot)
            
        if frames:
            prompt = """
            Analyze these screenshots of the OrangeHRM interface.
            1. Do you see a profile photo that is NOT the default gray silhouette? (Look for a custom image or initial).
            2. Do you see a list of attachments or the text "signed_offer.pdf" or "nda_signed.pdf"?
            3. Is this the PIM/Employee management module?
            
            Return JSON: {"custom_photo_visible": bool, "attachments_visible": bool, "is_pim_module": bool}
            """
            
            try:
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                parsed = vlm_resp.get('parsed', {})
                
                if parsed.get('is_pim_module'):
                    vlm_score += 2
                if parsed.get('custom_photo_visible'):
                    vlm_score += 4
                if parsed.get('attachments_visible'):
                    vlm_score += 4
                    
                score += vlm_score
                if vlm_score > 0:
                    feedback.append(f"Visual verification confirmed actions (+{vlm_score} pts).")
            except Exception as e:
                feedback.append(f"Visual verification skipped due to error: {e}")

    # 6. Final Result Calculation
    # Cap score at 100
    score = min(100, score)
    
    # Pass threshold: Must have photo (30) + at least one doc (20) = 50 minimum
    # But let's set a robust threshold of 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }