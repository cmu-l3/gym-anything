#!/usr/bin/env python3
"""
Verifier for configure_guide_sleeve task.

Verifies:
1. PDF Report existence and creation time.
2. PDF Content (Offset 9.5, Diameter 5.3).
3. VLM confirmation of settings in screenshot/report.
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_text_from_pdf(pdf_path):
    """Extract text from PDF using pdfminer."""
    try:
        from pdfminer.high_level import extract_text
        return extract_text(pdf_path)
    except ImportError:
        logger.warning("pdfminer not available, trying pypdf")
        try:
            from pypdf import PdfReader
            reader = PdfReader(pdf_path)
            text = ""
            for page in reader.pages:
                text += page.extract_text()
            return text
        except ImportError:
            logger.error("No PDF parsing library available")
            return ""
    except Exception as e:
        logger.error(f"Error reading PDF: {e}")
        return ""

def verify_configure_guide_sleeve(traj, env_info, task_info):
    """
    Verify the guide sleeve configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', r"C:\Users\Docker\Documents\BlueSkyPlan\Sleeve_Report.pdf")

    # Temp files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')

    try:
        # 1. Fetch JSON Result
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)

        # 2. Fetch PDF Report
        pdf_copied = False
        try:
            copy_from_env(expected_output_path, temp_pdf.name)
            pdf_copied = True
        except Exception:
            logger.info("Could not copy PDF report - likely does not exist")

        score = 0
        feedback_parts = []
        
        # Criterion 1: Report Exists & Created During Task (30 pts)
        if result_data.get('output_exists') and result_data.get('file_created_during_task'):
            score += 30
            feedback_parts.append("PDF report generated successfully.")
        elif result_data.get('output_exists'):
            score += 10
            feedback_parts.append("PDF exists but timestamp uncertain.")
        else:
            feedback_parts.append("PDF report not found.")

        # Criterion 2: Content Verification (40 pts)
        pdf_text = ""
        if pdf_copied:
            pdf_text = extract_text_from_pdf(temp_pdf.name)
            
            # Check for Offset 9.5
            if "9.5" in pdf_text:
                score += 15
                feedback_parts.append("Correct Offset (9.5mm) found in report.")
            else:
                feedback_parts.append("Offset 9.5mm NOT found in report.")
                
            # Check for Diameter 5.3
            if "5.3" in pdf_text:
                score += 15
                feedback_parts.append("Correct Diameter (5.3mm) found in report.")
            else:
                feedback_parts.append("Diameter 5.3mm NOT found in report.")
                
            # Check for Implant 30
            if "30" in pdf_text or "#30" in pdf_text:
                score += 10
                feedback_parts.append("Implant site #30 confirmed.")
            else:
                feedback_parts.append("Site #30 not explicitly found in text.")

        # Criterion 3: VLM Verification (30 pts)
        # We check if the settings panel or the report was visible at any point with correct numbers
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_prompt = """
        Review these screenshots from Blue Sky Plan dental software.
        I am looking for evidence that the user configured a surgical guide tube with:
        - Offset: 9.5 mm
        - Hole Diameter: 5.3 mm
        - Height: 4.0 mm
        
        Look for a "Guide Tube" or "Drilling Report" panel showing these numbers.
        Does the screenshot show these specific values?
        """
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_result.get('success'):
            # Simple heuristic on VLM text response
            analysis = vlm_result.get('result', '').lower()
            if "yes" in analysis and "9.5" in analysis and "5.3" in analysis:
                score += 30
                feedback_parts.append("VLM confirms correct settings visible.")
            elif "yes" in analysis:
                score += 20
                feedback_parts.append("VLM confirms settings panel visible but numbers unclear.")
            else:
                feedback_parts.append("VLM could not confirm settings visually.")
        else:
            feedback_parts.append("VLM analysis failed.")

        passed = score >= 80
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
        
    finally:
        # Cleanup
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)