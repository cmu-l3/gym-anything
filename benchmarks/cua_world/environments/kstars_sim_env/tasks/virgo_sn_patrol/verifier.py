#!/usr/bin/env python3
"""
Verifier for virgo_sn_patrol task.

Occupation: Amateur Astronomer / Survey Participant
Context: Supernova patrol of 4 Virgo Cluster galaxies.

Criteria (100 pts total, pass >= 60):
1. M87 frames captured (≥4 in M87/ dir)                        - 15 pts
2. M84 frames captured (≥4 in M84/ dir)                        - 15 pts
3. M100 frames captured (≥4 in M100/ dir)                      - 15 pts
4. M49 frames captured (≥4 in M49/ dir)                        - 15 pts
5. Directory structure correct (all 4 dirs exist)               - 8 pts
6. Telescope moved to Virgo (within 5° of any target)           - 7 pts
7. Patrol log exists                                            - 5 pts
8. Patrol log lists all 4 targets                               - 10 pts
9. Patrol log contains coordinate data                          - 5 pts
10. Sky view capture created                                    - 5 pts

Anti-gaming:
- Stale decoy files in M87 predate task start and must NOT be counted.
- Files must be > 2048 bytes to count as real FITS images.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Target coordinates
TARGETS = {
    "M87": (12.5137, 12.3911),
    "M84": (12.4177, 12.8869),
    "M100": (12.3819, 15.8225),
    "M49": (12.4963, 8.0006)
}

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_virgo_sn_patrol(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_frames = metadata.get('min_frames_per_target', 4)

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

    # Filter out stale decoy files and tiny files
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and
                  f.get('size', 0) > 2048 and
                  "old_patrol" not in f.get('name', '')]

    def count_target(target_name):
        return sum(1 for f in valid_fits if f.get('target') == target_name)

    counts = {
        "M87": count_target("M87"),
        "M84": count_target("M84"),
        "M100": count_target("M100"),
        "M49": count_target("M49")
    }

    # ── Criteria 1-4: Frame counts per target (4 * 15 = 60 pts) ──────────
    for target in ["M87", "M84", "M100", "M49"]:
        cnt = counts[target]
        if cnt >= min_frames:
            score += 15
            feedback.append(f"{target}: {cnt} frames captured")
        elif cnt >= 2:
            score += 7
            feedback.append(f"{target}: {cnt}/{min_frames} frames")
        elif cnt == 1:
            score += 3
            feedback.append(f"{target}: only {cnt} frame")
        else:
            feedback.append(f"{target}: no valid frames captured")

    # ── Criterion 5: Directory structure (8 pts) ─────────────────────────
    dirs = result.get('dirs', {})
    dirs_present = sum(1 for v in dirs.values() if v)
    if dirs_present == 4:
        score += 8
        feedback.append("Directory structure complete (4/4 dirs)")
    elif dirs_present > 0:
        score += dirs_present * 2
        feedback.append(f"Directory structure partial ({dirs_present}/4 dirs)")

    # ── Criterion 6: Telescope moved to Virgo (7 pts) ────────────────────
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        # Check distance to any of the 4 targets (Virgo cluster spans a few degrees)
        min_dist = min(angular_separation_deg(final_ra, final_dec, t_ra, t_dec) 
                       for t_ra, t_dec in TARGETS.values())
        if min_dist <= 5.0:
            score += 7
            feedback.append("Telescope pointed at Virgo Cluster")
        else:
            feedback.append(f"Telescope not at Virgo (closest target {min_dist:.1f}° away)")
    else:
        feedback.append("Could not verify telescope position")

    # ── Criterion 7-9: Patrol log (20 pts) ───────────────────────────────
    log_exists = result.get('log_exists', False)
    log_mtime = result.get('log_mtime', 0)
    log_b64 = result.get('log_b64', '')

    if log_exists and log_mtime > task_start:
        score += 5
        feedback.append("Patrol log created")

        log_text = ''
        if log_b64:
            try:
                log_text = base64.b64decode(log_b64).decode('utf-8', errors='ignore').upper()
            except:
                pass

        if log_text:
            targets_found = sum(1 for t in ["M87", "M84", "M100", "M49"] if t in log_text)
            if targets_found == 4:
                score += 10
                feedback.append("Log mentions all 4 targets")
            elif targets_found > 0:
                score += targets_found * 2
                feedback.append(f"Log mentions {targets_found}/4 targets")
            
            # Check for coordinates (RA, DEC, degree symbol, or hours)
            if any(term in log_text for term in ["RA", "DEC", "12H", "12 ", "°", "DEG", "12."]):
                score += 5
                feedback.append("Log contains coordinate data")
            else:
                feedback.append("Log missing coordinate data")
    elif log_exists:
        feedback.append("Patrol log exists but has old timestamp")
    else:
        feedback.append("Patrol log not found")

    # ── Criterion 10: Sky view capture (5 pts) ───────────────────────────
    if result.get('sky_capture_exists', False):
        score += 5
        feedback.append("Sky view capture created")
    else:
        feedback.append("Sky view capture missing")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "counts": counts,
            "stale_files_ignored": True
        }
    }