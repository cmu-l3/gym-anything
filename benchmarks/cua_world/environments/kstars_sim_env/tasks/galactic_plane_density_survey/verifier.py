#!/usr/bin/env python3
"""
Verifier for galactic_plane_density_survey task.

Criteria (100 pts total, pass >= 60):
1. Field 01-06 CCD images (≥2 valid FITS per field)          - 8 pts each (48 pts total)
2. Sky view captures (≥3 valid PNGs across all fields)       - 12 pts
3. Directory structure (all 6 subdirectories exist)          - 8 pts
4. Telescope visited distinct fields (verified via headers)  - 12 pts
5. Survey report exists and created during task              - 8 pts
6. Survey report content (mentions multiple fields)          - 12 pts
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_galactic_plane_density_survey(traj, env_info, task_info):
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
    files_info = result.get('files_info', [])
    
    # Filter files to only those created after task start and with content
    valid_files = [f for f in files_info if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    
    # Check CCD frames per field (8 pts each)
    fields_visited_by_fits = set()
    for i in range(1, 7):
        field_id = f"field_0{i}"
        fits_count = sum(1 for f in valid_files if f.get('dir') == field_id and f.get('type') == 'fits')
        
        if fits_count >= 2:
            score += 8
            feedback.append(f"{field_id}: {fits_count} FITS images")
            fields_visited_by_fits.add(field_id)
        elif fits_count == 1:
            score += 4
            feedback.append(f"{field_id}: 1 FITS image")
        else:
            feedback.append(f"{field_id}: 0 FITS images")

    # Sky view captures (12 pts)
    png_count = sum(1 for f in valid_files if f.get('type') == 'png' and f.get('size', 0) > 50000)
    if png_count >= 3:
        score += 12
        feedback.append(f"Sky views: {png_count} PNGs (>=3 required)")
    elif png_count > 0:
        score += int(12 * (png_count / 3))
        feedback.append(f"Sky views: {png_count}/3 PNGs")
    else:
        feedback.append("Sky views: no captures found")

    # Directory structure (8 pts)
    dirs = result.get('dirs', {})
    existing_dirs = sum(1 for k, v in dirs.items() if v)
    if existing_dirs == 6:
        score += 8
        feedback.append("Structure: all 6 field dirs exist")
    elif existing_dirs > 0:
        score += int(8 * (existing_dirs / 6))
        feedback.append(f"Structure: {existing_dirs}/6 dirs exist")
    else:
        feedback.append("Structure: no field dirs created")

    # Telescope visited distinct fields (12 pts)
    distinct_ra_dec = set()
    for f in valid_files:
        if f.get('type') == 'fits' and f.get('ra') and f.get('dec'):
            distinct_ra_dec.add((f.get('ra'), f.get('dec')))
            
    if len(distinct_ra_dec) >= 4:
        score += 12
        feedback.append(f"Slewing: {len(distinct_ra_dec)} distinct target positions in FITS headers")
    elif len(distinct_ra_dec) > 0:
        score += int(12 * (len(distinct_ra_dec) / 4))
        feedback.append(f"Slewing: {len(distinct_ra_dec)} distinct target positions detected")
    else:
        # Fallback to directory counts
        if len(fields_visited_by_fits) >= 4:
            score += 12
            feedback.append(f"Slewing (fallback): >=4 distinct field directories populated")
        else:
            feedback.append("Slewing: insufficient multi-field observations")

    # Report exists (8 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    if report_exists and report_mtime > task_start:
        score += 8
        feedback.append("Report: file created during task")
    else:
        feedback.append("Report: not found or pre-dates task")

    # Report content (12 pts)
    report_b64 = result.get('report_b64', '')
    if report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
            report_upper = report_text.upper()
            
            # Simple heuristic: mention of multiple fields
            fields_mentioned = 0
            for i in range(1, 7):
                if f"0{i}" in report_upper or f"FIELD {i}" in report_upper or f"FIELD_0{i}" in report_upper:
                    fields_mentioned += 1
            
            if fields_mentioned >= 4:
                score += 12
                feedback.append(f"Report content: contains >=4 fields")
            elif fields_mentioned > 0:
                score += int(12 * (fields_mentioned / 4))
                feedback.append(f"Report content: mentions {fields_mentioned} fields")
            else:
                feedback.append("Report content: lacks field summary table")
        except:
            feedback.append("Report content: unreadable")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }