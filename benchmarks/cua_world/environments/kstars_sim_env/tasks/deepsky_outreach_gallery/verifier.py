#!/usr/bin/env python3
"""
Verifier for deepsky_outreach_gallery task.

Criteria (100 pts total, pass >= 60):
1. Target M42 (8 pts for ≥3 FITS, 5 pts for sky_view.png)
2. Target M31 (8 pts for ≥3 FITS, 5 pts for sky_view.png)
3. Target M1  (8 pts for ≥3 FITS, 5 pts for sky_view.png)
4. Target M57 (8 pts for ≥3 FITS, 5 pts for sky_view.png)
5. Target M51 (8 pts for ≥3 FITS, 5 pts for sky_view.png)
6. Gallery HTML exists (10 pts)
7. Gallery lists all 5 objects & common names (15 pts)
8. Telescope was actively slewed (10 pts)
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGET_NAMES = {
    "M42": "ORION",
    "M31": "ANDROMEDA",
    "M1": "CRAB",
    "M57": "RING",
    "M51": "WHIRLPOOL"
}

def verify_deepsky_outreach_gallery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    # Retrieve result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    
    targets = result.get('targets', {})
    
    # Evaluate targets (65 points total)
    for t in ["M42", "M31", "M1", "M57", "M51"]:
        t_data = targets.get(t, {})
        fits_count = t_data.get('fits_count', 0)
        has_png = t_data.get('has_png', False)
        
        # FITS scoring (8 pts per target)
        if fits_count >= 3:
            score += 8
            feedback.append(f"{t}: captured {fits_count} FITS")
        elif fits_count > 0:
            score += 4
            feedback.append(f"{t}: captured {fits_count}/3 FITS")
        else:
            feedback.append(f"{t}: no valid FITS captured")
            
        # PNG scoring (5 pts per target)
        if has_png:
            score += 5
            feedback.append(f"{t}: sky_view.png generated")
        else:
            feedback.append(f"{t}: sky_view.png missing or invalid")

    # Evaluate Gallery HTML (25 points total)
    gallery = result.get('gallery', {})
    html_exists = gallery.get('exists', False)
    html_b64 = gallery.get('content_b64', "")
    
    if html_exists:
        score += 10
        feedback.append("Gallery HTML file created")
        
        # Check content
        try:
            html_text = base64.b64decode(html_b64).decode('utf-8', errors='ignore').upper()
            
            objects_found = 0
            for desig, name in TARGET_NAMES.items():
                if desig in html_text and name in html_text:
                    objects_found += 1
                    
            if objects_found == 5:
                score += 15
                feedback.append("Gallery mentions all 5 targets & common names")
            elif objects_found > 0:
                score += (objects_found * 3)
                feedback.append(f"Gallery mentions {objects_found}/5 targets")
            else:
                feedback.append("Gallery does not mention target designations/names")
                
        except Exception as e:
            feedback.append(f"Failed to parse HTML content: {e}")
    else:
        feedback.append("Gallery HTML file not found")

    # Evaluate telescope movement (10 points)
    slew_count = result.get('slew_count', 0)
    if slew_count >= 5:
        score += 10
        feedback.append(f"Telescope slewed sufficiently ({slew_count} coordinate sets)")
    elif slew_count > 0:
        score += 5
        feedback.append(f"Telescope slewed occasionally ({slew_count} coordinate sets)")
    else:
        feedback.append("Telescope was never slewed")

    # Final verdict
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }