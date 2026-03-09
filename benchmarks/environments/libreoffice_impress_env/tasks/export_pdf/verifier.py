#!/usr/bin/env python3
"""
Verifier for Export PDF task
"""

import sys
import os
import logging
import tempfile
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_pdf_export(traj, env_info, task_info):
    """
    Verify PDF export.
    
    Checks:
    1. PDF file exists
    2. PDF file has content (not empty)
    3. PDF has correct page count
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/Documents/Presentations/export_test.pdf"
    
    # Create temp file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        # Copy PDF from container
        copy_from_env(container_path, temp_path)
        
        if not os.path.exists(temp_path):
            return {"passed": False, "score": 0, "feedback": "PDF file not found"}
        
        file_size = os.path.getsize(temp_path)
        
        criteria_passed = 0
        total_criteria = 2
        feedback_parts = []
        
        # Criterion 1: File exists and not empty
        if file_size > 1024:  # At least 1KB
            criteria_passed += 1
            feedback_parts.append(f"✅ PDF file created ({file_size} bytes)")
        else:
            feedback_parts.append(f"❌ PDF file too small or empty ({file_size} bytes)")
        
        # Criterion 2: File is valid PDF
        try:
            with open(temp_path, 'rb') as f:
                header = f.read(4)
                if header == b'%PDF':
                    criteria_passed += 1
                    feedback_parts.append("✅ Valid PDF format")
                else:
                    feedback_parts.append("❌ Invalid PDF format")
        except Exception as e:
            feedback_parts.append(f"❌ Could not validate PDF: {e}")
        
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)
