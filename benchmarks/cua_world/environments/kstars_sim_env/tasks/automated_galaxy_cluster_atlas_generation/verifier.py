#!/usr/bin/env python3
"""
Verifier for automated_galaxy_cluster_atlas_generation task.

Criteria (100 pts total, pass >= 70):
1. Script exists (`~/build_atlas.sh` or `~/build_atlas.py`) (15 pts)
2. Directory created `~/Images/cluster_atlas/` (5 pts)
3. Output Generated: PNG files created after task start (30 pts)
4. Output Uniqueness: MD5 hash tracking ensures telescope actually slewed between captures (30 pts)
5. Final Telescope Position: Ensure telescope ends at the final catalog target (20 pts)
"""

import json
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

def verify_automated_galaxy_cluster_atlas_generation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_image_count', 10)
    final_ra = metadata.get('final_target_ra_hours', 11.8266)
    final_dec = metadata.get('final_target_dec_degrees', 22.3983)
    coord_tol = metadata.get('coordinate_tolerance_deg', 0.5)

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

    script_exists = result.get('script_exists', False)
    dir_exists = result.get('dir_exists', False)
    images = result.get('images', [])

    # Filter out empty or stale files
    valid_images = [img for img in images if img.get('mtime', 0) > task_start and img.get('size', 0) > 1024]
    valid_count = len(valid_images)

    # Hash uniqueness explicitly ensures the telescope was moving (or the agent was querying correctly).
    # Re-saving the identical frame without waiting for slewing will result in hash collisions.
    unique_hashes = set(img.get('md5') for img in valid_images if img.get('md5'))
    unique_count = len(unique_hashes)

    # ── Criterion 1: Script Created (15 pts) ──────────────────────────
    if script_exists:
        score += 15
        feedback.append("Automation script found.")
    else:
        feedback.append("Automation script NOT found.")

    # ── Criterion 2: Directory Created (5 pts) ────────────────────────
    if dir_exists:
        score += 5
        feedback.append("Output directory exists.")
    else:
        feedback.append("Output directory NOT found.")

    # ── Criterion 3: Image Generation (30 pts) ────────────────────────
    if valid_count >= expected_count:
        score += 30
        feedback.append(f"Successfully generated {valid_count}/{expected_count} valid images.")
    elif valid_count >= 5:
        score += 15
        feedback.append(f"Generated {valid_count}/{expected_count} images.")
    elif valid_count > 0:
        score += 5
        feedback.append(f"Only generated {valid_count} images.")
    else:
        feedback.append("No valid generated images found.")

    # ── Criterion 4: Image Uniqueness (30 pts) ────────────────────────
    if valid_count > 0 and unique_count == valid_count:
        if valid_count >= expected_count:
            score += 30
            feedback.append(f"All {unique_count} images are unique (proper slewing verified).")
        else:
            score += int(30 * (valid_count / expected_count))
            feedback.append(f"{unique_count} unique images generated.")
    elif valid_count > 0:
        score += int(30 * (unique_count / expected_count))
        feedback.append(f"Only {unique_count} unique images out of {valid_count}. Agent may have failed to wait for slew.")
    else:
        feedback.append("No images to check for uniqueness.")

    # ── Criterion 5: Final Telescope Position (20 pts) ────────────────
    try:
        curr_ra = float(result.get('final_ra', -1))
        curr_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        curr_ra, curr_dec = -1.0, -999.0

    if curr_ra > 0 and curr_dec > -900:
        sep_deg = angular_separation_deg(curr_ra, curr_dec, final_ra, final_dec)
        if sep_deg <= coord_tol:
            score += 20
            feedback.append(f"Telescope correctly pointed at the final catalog target (sep {sep_deg:.2f}°).")
        else:
            feedback.append(f"Telescope is NOT pointed at the final catalog target (sep {sep_deg:.2f}°).")
    else:
        feedback.append("Could not read final telescope coordinates.")

    passed = score >= 70 and unique_count >= 8
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }