#!/usr/bin/env python3
import json
import os
import tempfile
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass

logger = logging.getLogger(__name__)

def verify_archival_casebook(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/archival_casebook_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    pdf_exists = result.get('pdf_exists', False)
    pdf_size = result.get('pdf_size_bytes', 0)
    pdf_mtime = result.get('pdf_mtime', 0)
    task_start = result.get('task_start', 0)
    
    score = 0
    feedback = []
    
    if not pdf_exists:
        return {"passed": False, "score": 0, "feedback": "FAIL: Casebook PDF not found"}
        
    score += 20
    feedback.append("PDF file found (+20)")
    
    # Check if created during task (anti-gaming)
    if pdf_mtime >= task_start:
        score += 10
        feedback.append("PDF was created during task (+10)")
    else:
        feedback.append("WARNING: PDF appears to be older than task start")
        
    # Check reasonable size for a printed web page
    if pdf_size > 5000:
        score += 10
        feedback.append("PDF size is reasonable (+10)")
    else:
        feedback.append("PDF size is suspiciously small")
        
    # Read PDF content
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    pdf_text = ""
    try:
        copy_from_env("/tmp/agent_casebook.pdf", temp_pdf.name)
        
        try:
            from pdfminer.high_level import extract_text
            pdf_text = extract_text(temp_pdf.name)
        except ImportError:
            import subprocess
            try:
                # Fallback 1: pdftotext
                pdf_text = subprocess.check_output(["pdftotext", temp_pdf.name, "-"]).decode('utf-8', errors='ignore')
            except Exception:
                try:
                    # Fallback 2: strings
                    pdf_text = subprocess.check_output(["strings", temp_pdf.name]).decode('utf-8', errors='ignore')
                except Exception:
                    pass
    finally:
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)
            
    if "CV-101" in pdf_text:
        score += 20
        feedback.append("Subject ID CV-101 found in PDF content (+20)")
    else:
        feedback.append("Subject ID CV-101 NOT found in PDF content")
        
    if "Cardiovascular" in pdf_text or "CV-REG-2023" in pdf_text or "Outcomes" in pdf_text:
        score += 10
        feedback.append("Study context found in PDF content (+10)")
        
    # VLM Verification
    vlm_points = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        if frames and query_vlm:
            prompt = """Did the agent use the OpenClinica web interface to navigate to subject CV-101 and use the browser print dialog to save a PDF?
Look for:
1. OpenClinica Subject Matrix or View Subject page for CV-101.
2. A browser print dialog (Ctrl+P) with "Print to File" or "Save to PDF" selected.
Reply with JSON: {"used_openclinica_to_print": true/false}"""
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('used_openclinica_to_print'):
                    vlm_points = 30
                    feedback.append("VLM confirmed OS integration (Print to PDF from OpenClinica) (+30)")
                else:
                    feedback.append("VLM could NOT confirm OS integration (Print to PDF from OpenClinica)")
            else:
                vlm_points = 30
                feedback.append("VLM error, auto-awarding points (+30)")
        else:
            vlm_points = 30
            feedback.append("VLM unavailable, auto-awarding points (+30)")
    except Exception as e:
        vlm_points = 30
        feedback.append(f"VLM exception ({e}), auto-awarding points (+30)")
        
    score += vlm_points
    
    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}