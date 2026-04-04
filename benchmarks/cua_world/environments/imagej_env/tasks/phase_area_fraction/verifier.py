#!/usr/bin/env python3
"""
Verifier for phase_area_fraction task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_phase_area_fraction(traj, env_info, task_info):
    """
    Verify the Metallographic Phase Analysis task.
    
    Scoring Criteria (100 points total):
    1. Result file exists and created during task (15 pts)
    2. At least 3 phases identified (20 pts)
    3. Positive area values recorded (15 pts)
    4. Area fractions sum to ~100% (95-105%) (20 pts)
    5. No degenerate phases (each > 5%) (15 pts)
    6. VLM Verification of workflow (15 pts)
    
    Pass Threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Programmatic Verification (CSV Analysis) - 85 points
    # ---------------------------------------------------------
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                data = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
        
        # Criterion 1: File Existence & Timestamp (15 pts)
        if data.get("file_exists") and data.get("file_created_after_start"):
            score += 15
            feedback_parts.append("Result file created successfully.")
        elif data.get("file_exists"):
            score += 5
            feedback_parts.append("Result file exists but timestamp check failed.")
        else:
            feedback_parts.append("Result file not found.")

        # Criterion 2: 3+ Phases (20 pts)
        phases_found = data.get("phases_found", 0)
        if phases_found >= 3:
            score += 20
            feedback_parts.append(f"Identified {phases_found} phases (>=3 required).")
        elif phases_found > 0:
            score += 10
            feedback_parts.append(f"Only identified {phases_found} phases (need 3).")
        else:
            feedback_parts.append("No phases identified in file.")

        # Criterion 3: Valid Area Values (15 pts)
        numeric_data = data.get("numeric_data", [])
        valid_areas = [r for r in numeric_data if r.get("area", 0) > 100]
        if len(valid_areas) >= 3:
            score += 15
            feedback_parts.append("Valid area measurements found.")
        elif len(valid_areas) > 0:
            score += 5
            feedback_parts.append("Some area measurements found.")

        # Criterion 4: Sum to 100% (20 pts)
        total_pct = data.get("total_fraction_pct", 0)
        # Allow range 95% - 105%
        if 95.0 <= total_pct <= 105.0:
            score += 20
            feedback_parts.append(f"Area fractions sum to {total_pct:.1f}% (Valid).")
        elif 0.95 <= total_pct <= 1.05: # Handle 0-1 range
            score += 20
            feedback_parts.append(f"Area fractions sum to {total_pct:.2f} (Valid).")
        elif total_pct > 0:
            feedback_parts.append(f"Area fractions sum to {total_pct:.1f}% (Invalid, target ~100%).")
        
        # Criterion 5: Non-degenerate phases (15 pts)
        # Each phase should be > 5%
        valid_pcts = []
        for r in numeric_data:
            p = r.get("pct", 0)
            # Normalize 0-1 to 0-100 if needed
            if total_pct <= 1.05 and total_pct > 0: p *= 100
            valid_pcts.append(p)
        
        if len(valid_pcts) >= 3 and all(p > 5.0 for p in valid_pcts):
            score += 15
            feedback_parts.append("All phases have significant volume (>5%).")
        elif len(valid_pcts) >= 3:
             feedback_parts.append("Some phases are too small (<5%).")

    except Exception as e:
        feedback_parts.append(f"Programmatic verification failed: {str(e)}")

    # ---------------------------------------------------------
    # 2. VLM Verification (Workflow Check) - 15 points
    # ---------------------------------------------------------
    # Use VLM to confirm they actually segmented the image visually
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        if final_ss: frames.append(final_ss)
        
        if query_vlm and frames:
            prompt = """
            You are verifying an image analysis task in ImageJ.
            The user should be analyzing the 'AuPbSn 40' sample image (a gray texture with 3 distinct shades).
            
            Look at these screenshots. Can you see:
            1. An image window showing a texture with white, gray, and black regions?
            2. Any evidence of "Threshold" dialog or a red/colored overlay indicating segmentation?
            3. A "Results" table with numbers?
            
            Answer YES or NO for each.
            """
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            response_text = vlm_res.get('text', '').lower()
            
            # Simple heuristic matching
            signals = 0
            if 'yes' in response_text:
                if 'threshold' in response_text or 'overlay' in response_text or 'segment' in response_text:
                    signals += 1
                if 'table' in response_text or 'results' in response_text:
                    signals += 1
                if 'texture' in response_text or 'image' in response_text:
                    signals += 1
            
            if signals >= 2:
                score += 15
                feedback_parts.append("VLM confirms segmentation workflow.")
            elif signals == 1:
                score += 5
                feedback_parts.append("VLM sees some activity but workflow unclear.")
            else:
                feedback_parts.append("VLM did not observe expected workflow steps.")
                
        else:
            # Fallback if VLM fails/not available: give points if programmatic score is high
            if score >= 70:
                score += 15
                feedback_parts.append("VLM skipped (programmatic score sufficient).")

    except Exception as e:
        feedback_parts.append(f"VLM verification error: {e}")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }