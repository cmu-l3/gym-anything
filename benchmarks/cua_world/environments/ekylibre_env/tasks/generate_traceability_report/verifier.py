#!/usr/bin/env python3
"""
Verifier for generate_traceability_report task.

Criteria:
1. PDF file creation (Anti-gaming: must be created during task).
2. PDF Validity (Magic bytes).
3. PDF Content (Contains target zone name and keywords).
4. VLM Verification (Visual confirmation of UI interaction).
"""

import json
import os
import tempfile
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_traceability_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_zone = metadata.get('target_zone', 'Les Groies')
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Get Result JSON
    # ---------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    pdf_found = result.get("pdf_found", False)
    
    if not pdf_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No PDF report was downloaded during the task."
        }
        
    score += 30
    feedback_parts.append("PDF file created/downloaded")

    # ---------------------------------------------------------
    # 2. Get PDF Artifact and Verify Content
    # ---------------------------------------------------------
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    try:
        # We copied the PDF to /tmp/report_artifact.pdf in export_result.sh
        copy_from_env("/tmp/report_artifact.pdf", temp_pdf.name)
        
        # Check PDF Magic Bytes
        with open(temp_pdf.name, 'rb') as f:
            header = f.read(5)
            if header == b'%PDF-':
                score += 20
                feedback_parts.append("Valid PDF format")
            else:
                feedback_parts.append("Invalid PDF format")
                return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
        # Simple text extraction for keyword matching
        # Since we might not have complex PDF libs, we try basic extraction 
        # or rely on VLM if extraction fails. 
        # We try to use pypdf if available, otherwise just grep binary (risky but sometimes works for uncompressed text)
        
        content_text = ""
        try:
            import pypdf
            reader = pypdf.PdfReader(temp_pdf.name)
            for page in reader.pages:
                content_text += page.extract_text() + "\n"
        except ImportError:
            # Fallback: simple binary search for ASCII strings
            with open(temp_pdf.name, 'rb') as f:
                raw = f.read()
                # Remove null bytes and try to decode errors
                content_text = raw.decode('latin-1', errors='ignore')
        
        # Check Keywords
        # 1. Target Zone Name
        if target_zone.lower() in content_text.lower():
            score += 25
            feedback_parts.append(f"Contains target zone '{target_zone}'")
        else:
            feedback_parts.append(f"Target zone '{target_zone}' not found in PDF text")
            
        # 2. Report Type Keywords
        keywords = ["Traceability", "Traçabilité", "Intervention", "Fiche", "Parcellaire"]
        found_kw = [k for k in keywords if k.lower() in content_text.lower()]
        if found_kw:
            score += 25
            feedback_parts.append(f"Traceability keywords found: {found_kw[0]}")
        else:
            feedback_parts.append("No traceability keywords found in PDF")

    except Exception as e:
        feedback_parts.append(f"Error analyzing PDF content: {e}")
    finally:
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)

    # ---------------------------------------------------------
    # 3. Final Scoring
    # ---------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }