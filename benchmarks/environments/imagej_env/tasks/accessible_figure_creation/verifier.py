#!/usr/bin/env python3
"""Verifier for accessible_figure_creation task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_accessible_figure(traj, env_info, task_info):
    """
    Verify creation of an accessible scientific figure.
    
    Criteria:
    1. File creation and validity (20 pts)
    2. Color remapping: Red channel suppressed (25 pts)
    3. Color remapping: Magenta channel present (25 pts)
    4. Green channel preservation (10 pts)
    5. Scale bar presence (20 pts)
    
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
        
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/accessible_figure_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
                
        score = 0
        feedback_parts = []
        
        # 1. File checks
        if result.get("file_exists") and result.get("file_valid"):
            if result.get("timestamp_valid"):
                score += 20
                feedback_parts.append("Valid output file created")
            else:
                feedback_parts.append("FAIL: Output file predates task start")
        else:
            feedback_parts.append("FAIL: Output file not created or invalid image")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
            
        # 2. Color Analysis
        # Red ratio should be very low (remapped to Magenta)
        red_ratio = result.get("red_pixel_ratio", 1.0)
        magenta_ratio = result.get("magenta_pixel_ratio", 0.0)
        green_ratio = result.get("green_pixel_ratio", 0.0)
        
        # Thresholds
        # In a magenta/green image, pure red (high R, low G, low B) should be rare
        if red_ratio < 0.01: # Less than 1% pure red
            score += 25
            feedback_parts.append("Red channel successfully suppressed")
        else:
            feedback_parts.append(f"FAIL: Too much pure red ({red_ratio*100:.1f}%) - did you change the LUT to Magenta?")
            
        # Magenta should be present (indicates Channel 1 data is now R+B)
        # Note: Depending on image content, ratios might vary, but should be non-trivial
        if magenta_ratio > 0.005: # At least 0.5% pixels are magenta
            score += 25
            feedback_parts.append(f"Magenta channel present ({magenta_ratio*100:.1f}%)")
        else:
            feedback_parts.append("FAIL: No magenta detected - Channel 1 might be missing or wrong color")
            
        # Green should still be there
        if green_ratio > 0.005:
            score += 10
            feedback_parts.append("Green channel preserved")
        else:
            feedback_parts.append("FAIL: Green channel lost")
            
        # 3. Scale Bar
        if result.get("scale_bar_detected"):
            score += 20
            feedback_parts.append(f"Scale bar detected ({result.get('scale_bar_pixels')} white pixels)")
        else:
            feedback_parts.append("FAIL: No scale bar detected in lower right")
            
        passed = score >= 60
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}