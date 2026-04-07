#!/usr/bin/env python3
"""
Verifier for arp_interacting_galaxies_survey task.

Criteria (100 pts total, pass >= 70):
1. Arp 244 FITS (≥3 in arp_survey/arp244, ~120s exposure)   - 12.5 pts
2. Arp 273 FITS (≥3 in arp_survey/arp273, ~120s exposure)   - 12.5 pts
3. Arp 242 FITS (≥3 in arp_survey/arp242, ~120s exposure)   - 12.5 pts
4. Arp 81 FITS  (≥3 in arp_survey/arp81,  ~120s exposure)   - 12.5 pts
5. Correct Filter Used (Luminance evaluated across valid frames) - 10 pts
6. Morphology PNGs (≥4 PNGs with specific names across target dirs) - 20 pts
7. JSON Log valid and contains target names                 - 20 pts

Anti-gaming:
- Ignores stale data seeded before the task started (e.g. arp220 files)
- Filters strictly for creation time > task_start
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGETS = ['arp244', 'arp273', 'arp242', 'arp81']
EXPOSURE_TOLERANCE = 5.0  # seconds


def verify_arp_interacting_galaxies_survey(traj, env_info, task_info):
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
    
    media_info = result.get('media_info', {})
    fits_files = media_info.get('fits', [])
    png_files = media_info.get('pngs', [])

    # Filter for valid frames created DURING the task
    valid_fits = [
        f for f in fits_files
        if f.get('mtime', 0) > task_start 
        and f.get('size', 0) > 1024
        and abs(f.get('exptime', 0) - 120.0) <= EXPOSURE_TOLERANCE
    ]

    valid_pngs = [
        p for p in png_files
        if p.get('mtime', 0) > task_start
        and p.get('name', '').lower().startswith('morphology_')
    ]

    def score_target_fits(target_name):
        # Count valid frames located within the target's subdirectory
        count = sum(1 for f in valid_fits if f.get('dir', '').lower() == target_name)
        pts = 0
        if count >= 3:
            pts = 12.5
        elif count == 2:
            pts = 8.0
        elif count == 1:
            pts = 4.0
        return pts, count

    # Score FITS per target
    for t in TARGETS:
        pts, cnt = score_target_fits(t)
        score += pts
        if cnt >= 3:
            feedback.append(f"{t.upper()}: {cnt} frames (OK)")
        else:
            feedback.append(f"{t.upper()}: {cnt}/3 frames")

    # Evaluate correct filter usage (across whatever valid FITS exist)
    if len(valid_fits) > 0:
        correct_filter_count = sum(
            1 for f in valid_fits 
            if f.get('filter', '').upper() in ('LUMINANCE', 'L', 'CLEAR')
        )
        ratio = correct_filter_count / len(valid_fits)
        if ratio >= 0.8:  # 80%+ have the correct filter
            score += 10
            feedback.append("Filter: Luminance used correctly")
        else:
            feedback.append(f"Filter: Wrong filter used (Correct {ratio*100:.0f}%)")
    else:
        feedback.append("Filter: No valid frames to evaluate")

    # Evaluate Morphology PNG captures
    # We want 1 valid morphology PNG in each target directory
    png_dirs_covered = set()
    for p in valid_pngs:
        d = p.get('dir', '').lower()
        if d in TARGETS:
            png_dirs_covered.add(d)
    
    png_cnt = len(png_dirs_covered)
    if png_cnt >= 4:
        score += 20
        feedback.append("Morphology Captures: 4/4 completed")
    else:
        score += png_cnt * 5
        feedback.append(f"Morphology Captures: {png_cnt}/4 completed")

    # Evaluate JSON log
    log_exists = result.get('log_exists', False)
    log_b64 = result.get('log_content_b64', '')
    
    if log_exists and log_b64:
        try:
            log_content = base64.b64decode(log_b64).decode('utf-8', errors='ignore')
            log_data = json.loads(log_content)
            
            # Convert JSON dump to a single lowercase string to easily check for references
            log_str = json.dumps(log_data).lower()
            found_targets = sum(1 for t in TARGETS if t in log_str)
            
            if found_targets >= 4:
                score += 20
                feedback.append("JSON Log: Valid and references all 4 targets")
            elif found_targets >= 2:
                score += 10
                feedback.append(f"JSON Log: Valid but missing some targets ({found_targets}/4)")
            else:
                score += 5
                feedback.append("JSON Log: Valid but missing most/all target names")
        except json.JSONDecodeError:
            feedback.append("JSON Log: File exists but is not valid JSON")
    else:
        feedback.append("JSON Log: Not found or empty")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }