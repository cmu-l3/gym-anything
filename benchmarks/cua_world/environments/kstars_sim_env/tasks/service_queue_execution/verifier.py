#!/usr/bin/env python3
"""
Verifier for service_queue_execution task.

Occupation: Observatory Operator / Service Observer
Context: Executing an observing queue involving 3 distinct targets, filter changes, and specific directory tracking.

Criteria (100 pts total, pass >= 60):
1. M44 FITS images (≥10 new FITS files in /home/ga/Images/queue/m44/)      - 20 pts
2. NGC 2392 FITS images (≥6 new FITS files in /home/ga/Images/queue/ngc2392/) - 20 pts
3. M51 FITS images (≥8 new FITS files in /home/ga/Images/queue/m51/)       - 20 pts
4. Telescope near M51 (Final position within 2° of M51)                    - 10 pts
5. Sky capture exists (final_sky.png is present and >50KB)                 - 5 pts
6. Session log exists (created during task)                                - 10 pts
7. Session log content (Log mentions M44, NGC 2392, and M51)               - 15 pts

Anti-gaming: Relies heavily on file creation timestamps. Ensures multiple directories have content.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_service_queue_execution(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

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
    task_start = result.get('task_start', 0)
    fits_files = result.get('fits_files', [])

    # Filter out empty stubs or pre-task files
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def count_dir(dirname):
        return sum(1 for f in valid_fits if f.get('dir') == dirname)

    m44_count = count_dir('m44')
    ngc2392_count = count_dir('ngc2392')
    m51_count = count_dir('m51')

    # Criterion 1: M44 (20 pts)
    if m44_count >= 10:
        score += 20
        feedback.append(f"M44: {m44_count} valid frames")
    elif m44_count >= 5:
        score += 10
        feedback.append(f"M44: {m44_count}/10 valid frames")
    else:
        feedback.append(f"M44: {m44_count} frames found")

    # Criterion 2: NGC 2392 (20 pts)
    if ngc2392_count >= 6:
        score += 20
        feedback.append(f"NGC 2392: {ngc2392_count} valid frames")
    elif ngc2392_count >= 3:
        score += 10
        feedback.append(f"NGC 2392: {ngc2392_count}/6 valid frames")
    else:
        feedback.append(f"NGC 2392: {ngc2392_count} frames found")

    # Criterion 3: M51 (20 pts)
    if m51_count >= 8:
        score += 20
        feedback.append(f"M51: {m51_count} valid frames")
    elif m51_count >= 4:
        score += 10
        feedback.append(f"M51: {m51_count}/8 valid frames")
    else:
        feedback.append(f"M51: {m51_count} frames found")

    # Criterion 4: Telescope near M51 (10 pts)
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0
    
    if final_ra > 0 and final_dec > -900:
        # M51 target RA: 13.498h, Dec: 47.195 deg
        sep_deg = angular_separation_deg(final_ra, final_dec, 13.498, 47.195)
        if sep_deg <= 2.0:
            score += 10
            feedback.append(f"Telescope near M51 (sep {sep_deg:.1f}°)")
        else:
            feedback.append(f"Telescope not near M51 (sep {sep_deg:.1f}°)")
    else:
        feedback.append("Could not determine final telescope coordinates")
    
    # Criterion 5: Sky capture exists (5 pts)
    if result.get('sky_capture_exists') and int(result.get('sky_capture_size', 0)) > 50000:
        score += 5
        feedback.append("Sky capture successfully completed")
    else:
        feedback.append("Sky capture missing or invalid size")

    # Criteria 6 & 7: Session log existence (10 pts) and content (15 pts)
    if result.get('log_exists'):
        score += 10
        feedback.append("Session log exists")
        
        log_b64 = result.get('log_b64', '')
        if log_b64:
            try:
                log_text = base64.b64decode(log_b64).decode('utf-8', errors='ignore').lower()
                
                has_m44 = 'm44' in log_text or 'beehive' in log_text or 'praesepe' in log_text
                has_ngc2392 = 'ngc 2392' in log_text or 'ngc2392' in log_text or 'eskimo' in log_text
                has_m51 = 'm51' in log_text or 'whirlpool' in log_text
                
                mentions = sum([has_m44, has_ngc2392, has_m51])
                
                if mentions == 3:
                    score += 15
                    feedback.append("Session log mentions all 3 queue targets")
                elif mentions > 0:
                    score += 5 * mentions
                    feedback.append(f"Session log mentions {mentions}/3 queue targets")
                else:
                    feedback.append("Session log lacks required target mention references")
            except Exception as e:
                feedback.append("Could not parse session log content")
    else:
        feedback.append("Session log missing")

    # Requires at least one sequence to have genuinely progressed
    passed = score >= 60 and (m44_count > 0 or ngc2392_count > 0 or m51_count > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }