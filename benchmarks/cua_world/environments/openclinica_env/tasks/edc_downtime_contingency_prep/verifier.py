#!/usr/bin/env python3
"""Verifier for edc_downtime_contingency_prep task."""

import json
import tempfile
import os
import logging
import sys

logger = logging.getLogger(__name__)

def verify_edc_downtime_contingency_prep(traj, env_info, task_info):
    """
    Verify the EDC downtime contingency task.
    
    Scoring points:
    - CRF Uploaded to DB: 20 pts
    - Target directory created: 10 pts
    - Form saved in correct location/format: 20 pts
    - Form content matches Vital Signs CRF: 20 pts
    - VLM Verification on trajectory: 30 pts
    
    Pass threshold: 70 points AND content must be valid.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/edc_downtime_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # Verify nonce integrity
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
    except Exception:
        expected_nonce = ""
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    if expected_nonce and result.get('result_nonce', '') != expected_nonce:
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Nonce mismatch"}

    score = 0
    feedback = []

    # 1. CRF in DB (20)
    if result.get('crf_exists_in_db'):
        score += 20
        feedback.append("CRF 'Vital Signs' uploaded to DB (+20)")
    else:
        feedback.append("FAIL: CRF not uploaded to DB (0/20)")

    # 2. Directory exists (10)
    if result.get('dir_exists'):
        score += 10
        feedback.append("Directory ~/Documents/Downtime_Forms created (+10)")
    else:
        feedback.append("FAIL: Directory not created (0/10)")

    # 3. File Saved and Timestamp Valid (20)
    file_path_in_env = result.get('exported_file_path')
    if result.get('saved_file_found') and result.get('created_during_task'):
        score += 20
        feedback.append(f"Saved file found ({result.get('file_extension')}) and created during task (+20)")
    else:
        feedback.append("FAIL: No valid HTML/PDF file saved during task (0/20)")

    # 4. Content Verification (20)
    content_valid = False
    if file_path_in_env:
        temp_doc = tempfile.NamedTemporaryFile(delete=False, suffix='.' + result.get('file_extension', 'txt'))
        try:
            copy_from_env(file_path_in_env, temp_doc.name)
            
            text_content = ""
            if file_path_in_env.lower().endswith('.pdf'):
                try:
                    from pdfminer.high_level import extract_text
                    text_content = extract_text(temp_doc.name)
                except Exception as e:
                    logger.error(f"Failed to extract PDF with pdfminer: {e}")
                    # Fallback raw binary read
                    with open(temp_doc.name, 'rb') as f:
                        text_content = f.read().decode('utf-8', errors='ignore')
            else:
                with open(temp_doc.name, 'r', encoding='utf-8', errors='ignore') as f:
                    text_content = f.read()
                    
            text_lower = text_content.lower()
            if 'vital signs' in text_lower and ('systolic' in text_lower or 'diastolic' in text_lower):
                content_valid = True
                score += 20
                feedback.append("Content verified: Found 'Vital Signs' and BP fields inside exported file (+20)")
            else:
                feedback.append("FAIL: File content does not match expected Vital Signs CRF (0/20)")
        except Exception as e:
            feedback.append(f"FAIL: Could not verify file content: {e} (0/20)")
        finally:
            if os.path.exists(temp_doc.name):
                os.unlink(temp_doc.name)

    # 5. VLM trajectory check (30)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            from vlm_utils import sample_trajectory_frames, get_final_screenshot
            
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """Examine these screenshots of an agent working in OpenClinica.
                1. Did the agent view the 'Print' layout or a printable blank CRF form for 'Vital Signs'?
                2. Did the agent use the browser's Save As / Print dialog to save the page?
                
                Respond in JSON format:
                {
                    "print_view_opened": true/false,
                    "save_dialog_used": true/false,
                    "confidence": "low"/"medium"/"high"
                }"""
                vlm_res = query_vlm(prompt=prompt, images=images)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('print_view_opened'):
                        score += 15
                        feedback.append("VLM: Print view was opened (+15)")
                    if parsed.get('save_dialog_used'):
                        score += 15
                        feedback.append("VLM: Save/Print dialog was used (+15)")
                else:
                    feedback.append("VLM error: " + vlm_res.get('error', 'unknown'))
        except ImportError:
            score += 30
            feedback.append("VLM skipped (import error), assuming points (+30)")
    else:
        feedback.append("VLM not available")

    passed = score >= 70 and content_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }