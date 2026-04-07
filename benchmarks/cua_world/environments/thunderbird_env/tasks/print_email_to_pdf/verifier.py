#!/usr/bin/env python3
"""
Verifier for print_email_to_pdf task.
Evaluates file creation timestamps, PDF structure, text content, and visual UI trajectories.
"""
import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_text_from_pdf(pdf_path):
    """Attempt to extract text safely across different PDF library availability."""
    try:
        from pdfminer.high_level import extract_text
        text = extract_text(pdf_path)
        return text
    except ImportError:
        logger.warning("pdfminer not available, trying pdftotext system binary")
        try:
            import subprocess
            result = subprocess.run(["pdftotext", pdf_path, "-"], capture_output=True, text=True)
            return result.stdout
        except Exception as e:
            logger.warning(f"pdftotext failed: {e}")
            try:
                # Absolute last resort fallback: read raw strings from binary
                with open(pdf_path, 'rb') as f:
                    content = f.read().decode('utf-8', errors='ignore')
                    return content
            except Exception:
                return ""
    except Exception as e:
        logger.warning(f"Failed to extract text from PDF: {e}")
        return ""

def verify_print_email_to_pdf(traj, env_info, task_info):
    """
    Verify that the user correctly printed the target email to PDF.
    Ensures PDF file creation logic is robust.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_path', '/home/ga/Documents/Peterson_Settlement.pdf')
    
    # 1. Fetch properties exported by bash script
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    score = 0
    feedback_parts = []
    
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)
    
    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"PDF file not found at {expected_path}"
        }
    
    score += 20
    feedback_parts.append("PDF file exists")
    
    if file_created:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("Warning: File may have existed before task (Anti-gaming flag)")
        
    if file_size > 1000:
        score += 10
        feedback_parts.append("File size is valid")
    else:
        feedback_parts.append("File size too small (might be empty/corrupt)")
        
    # 2. Extract and inspect the PDF itself
    pdf_text = ""
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    try:
        copy_from_env(expected_path, temp_pdf.name)
        with open(temp_pdf.name, 'rb') as f:
            header = f.read(4)
            if header != b'%PDF':
                feedback_parts.append("File is not a valid PDF (invalid magic bytes)")
            else:
                pdf_text = extract_text_from_pdf(temp_pdf.name)
    except Exception as e:
        feedback_parts.append(f"Failed to copy or read PDF: {e}")
    finally:
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)
            
    pdf_text_lower = pdf_text.lower()
    
    if "final settlement terms" in pdf_text_lower:
        score += 20
        feedback_parts.append("Found expected subject in PDF")
    else:
        feedback_parts.append("Missing expected subject in PDF")
        
    if "confidentiality clause" in pdf_text_lower and "500,000" in pdf_text_lower:
        score += 20
        feedback_parts.append("Found expected body clauses in PDF")
    else:
        feedback_parts.append("Missing expected body clauses in PDF")
        
    # 3. VLM Verification (Print dialog trajectory checks)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Sample across timeline
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """You are evaluating an agent that is printing an email to a PDF in Thunderbird.
Look at the sequence of screenshots.
Did the agent open the Print dialog (either Thunderbird's print preview or the system GTK print dialog) at some point?
Did the agent actively use the UI to print to file/PDF?

Respond in JSON format:
{
    "print_dialog_visible": true,
    "confidence": "high",
    "reasoning": "Brief explanation"
}"""
        
        vlm_result = query_vlm(images=images, prompt=prompt)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("print_dialog_visible", False):
                vlm_score = 20
                feedback_parts.append("VLM verified print dialog usage")
            else:
                feedback_parts.append("VLM did not detect print dialog usage")
        else:
            feedback_parts.append("VLM verification failed to run properly")
    except ImportError:
        logger.warning("gym_anything.vlm not available for trajectory verification")
        # Ensure tests pass smoothly if this package isn't present, provided previous checks are strong
        if score >= 80:
            vlm_score = 20
            feedback_parts.append("VLM skipped (not available) - awarded points based on strong programmatic checks")
    except Exception as e:
        logger.warning(f"VLM verification exception: {e}")
        feedback_parts.append(f"VLM verification error: {e}")
        
    score += vlm_score
    
    # 70 is our passing threshold
    passed = output_exists and file_created and file_size > 1000 and score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }