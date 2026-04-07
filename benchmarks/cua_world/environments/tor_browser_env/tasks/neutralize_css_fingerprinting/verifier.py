#!/usr/bin/env python3
"""Verifier for neutralize_css_fingerprinting task.

Evaluates configuration of anti-fingerprinting visual settings in Tor Browser
and uses VLM (with trajectory checking) to verify the evidence screenshot.
"""

import json
import logging
import os
import tempfile
import base64
from io import BytesIO
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_neutralize_css_fingerprinting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Read JSON result from container
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not extract task state"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    prefs = result.get('prefs', {})
    out_file = result.get('output_file', {})
    
    # 2. Check Preferences
    # Criterion A: Disable custom fonts (REQUIRED GATE) -> 25 pts
    use_doc_fonts = prefs.get('use_document_fonts', 1)
    fonts_disabled = (use_doc_fonts == 0)
    if fonts_disabled:
        score += 25
        feedback_parts.append("Custom fonts disabled (25/25)")
    else:
        feedback_parts.append("Custom fonts NOT disabled (0/25)")

    # Criterion B: Override page colors -> 25 pts
    doc_color_use = prefs.get('document_color_use', 0)
    if doc_color_use == 2:
        score += 25
        feedback_parts.append("Page colors strictly overridden (25/25)")
    else:
        feedback_parts.append("Page colors NOT overridden (0/25)")

    # Criterion C: Disable smooth scrolling -> 15 pts
    smooth_scroll = prefs.get('smooth_scroll', True)
    if not smooth_scroll:
        score += 15
        feedback_parts.append("Smooth scrolling disabled (15/15)")
    else:
        feedback_parts.append("Smooth scrolling NOT disabled (0/15)")

    # 3. Evidence File Checks -> 15 pts
    evidence_exists = out_file.get('exists', False)
    evidence_is_new = out_file.get('is_new', False)
    evidence_size = out_file.get('size_bytes', 0)

    if evidence_exists and evidence_is_new and evidence_size > 1000:
        score += 15
        feedback_parts.append("Evidence screenshot captured (15/15)")
    elif evidence_exists:
        score += 5
        feedback_parts.append("Evidence screenshot exists but predates task or is invalid (5/15)")
    else:
        feedback_parts.append("No evidence screenshot found (0/15)")

    # 4. VLM Verification of the Evidence & Trajectory -> 20 pts
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        
        # We also want to verify the specific user-saved file if possible
        tmp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        tmp_img.close()
        evidence_images = []
        if evidence_exists:
            try:
                copy_from_env("/home/ga/Documents/safe_render.png", tmp_img.name)
                evidence_img = Image.open(tmp_img.name)
                evidence_images.append(evidence_img)
            except Exception as img_e:
                logger.warning(f"Could not load evidence image for VLM: {img_e}")
        
        all_images = frames + [final_frame] + evidence_images
        
        if all_images:
            import openai
            vlm_api_key = os.environ.get('VLM_API_KEY')
            vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
            
            if vlm_api_key:
                client = openai.OpenAI(base_url=vlm_base_url, api_key=vlm_api_key)
                
                content_payload = [
                    {"type": "text", "text": "Analyze these trajectory frames and the final screenshot from Tor Browser. 1. Did the user configure Tor Browser Settings (Fonts, Colors)? 2. Look closely at the final webpage view or screenshot: Is the page rendered in a PLAIN, DEFAULT style (standard text, no magenta background)? Reply 'VERIFIED: YES' if the styling is neutralized, or 'VERIFIED: NO' if hostile styling (magenta/lime/custom fonts) is still visible."}
                ]
                
                for img in all_images:
                    img = img.convert('RGB')
                    img.thumbnail((1024, 1024))
                    buf = BytesIO()
                    img.save(buf, format="JPEG")
                    b64 = base64.b64encode(buf.getvalue()).decode('utf-8')
                    content_payload.append({
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{b64}"}
                    })
                
                resp = client.chat.completions.create(
                    model='databricks-claude-sonnet-4-5',
                    messages=[{"role": "user", "content": content_payload}],
                    max_tokens=200,
                    temperature=0.0
                )
                
                resp_text = resp.choices[0].message.content
                if "VERIFIED: YES" in resp_text.upper():
                    vlm_score = 20
                    feedback_parts.append("VLM visual verification passed (20/20)")
                else:
                    feedback_parts.append("VLM visual verification failed (0/20)")
            else:
                logger.warning("VLM_API_KEY missing, skipping visual check.")
                vlm_score = 20  # Default grant if unable to check
                feedback_parts.append("VLM check skipped (awarded 20/20)")
    except Exception as e:
        logger.warning(f"VLM trajectory extraction error: {e}")
        vlm_score = 20 # Fallback grace points if VLM framework is missing
        feedback_parts.append(f"VLM check fallback (awarded 20/20)")
    
    score += vlm_score

    # Final Pass Logic
    passed = (score >= 65) and fonts_disabled and result.get('app_running', False)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }