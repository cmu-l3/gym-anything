#!/usr/bin/env python3
"""
Verifier for finding_chart_atlas task.

Occupation: Observatory Support Astronomer / Telescope Operator
Context: Prepare a set of finding charts using sky survey images for visiting astronomer.

Criteria (100 pts total, pass >= 60):
1. Abell 2218 chart exists (>50KB, new)           - 15 pts
2. M1 Crab chart exists (>50KB, new)              - 15 pts
3. Sgr A* chart exists (>50KB, new)               - 15 pts
4. 3C 273 chart exists (>50KB, new)               - 15 pts
5. Atlas index file exists                        - 10 pts
6. Index lists all targets                        - 15 pts
7. Telescope at final target (3C 273)             - 15 pts
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

def verify_finding_chart_atlas(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', [])

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
    
    png_files = result.get('png_files', [])
    valid_pngs = {f.get('name'): f for f in png_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 50000}

    # Criterion 1-4: PNGs exist
    target_filenames = [
        "abell2218_fc.png",
        "m1_crab_fc.png",
        "sgra_gc_fc.png",
        "3c273_fc.png"
    ]
    
    for fname in target_filenames:
        if fname in valid_pngs:
            score += 15
            feedback.append(f"{fname} found and valid")
        else:
            feedback.append(f"{fname} missing or invalid")

    # Criterion 5: Index exists
    index_exists = result.get('index_exists', False)
    index_mtime = result.get('index_mtime', 0)
    
    if index_exists and index_mtime > task_start:
        score += 10
        feedback.append("Atlas index file created")
        
        # Criterion 6: Index content
        index_b64 = result.get('index_b64', '')
        if index_b64:
            try:
                index_text = base64.b64decode(index_b64).decode('utf-8', errors='ignore').lower()
                
                targets_found = 0
                if "abell" in index_text and "2218" in index_text:
                    targets_found += 1
                if "m1" in index_text or "crab" in index_text:
                    targets_found += 1
                if "sgr" in index_text or "galactic" in index_text:
                    targets_found += 1
                if "3c" in index_text and "273" in index_text:
                    targets_found += 1
                    
                if targets_found == 4:
                    score += 15
                    feedback.append("Index lists all 4 targets")
                elif targets_found > 0:
                    score += int(15 * (targets_found / 4.0))
                    feedback.append(f"Index lists {targets_found}/4 targets")
                else:
                    feedback.append("Index does not mention expected targets")
            except Exception as e:
                feedback.append(f"Error parsing index: {e}")
        else:
            feedback.append("Index file is empty")
    else:
        feedback.append("Atlas index file not found or pre-dates task")

    # Criterion 7: Telescope at final target (3C 273)
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        # Last target is 3C 273: 12h 29m 07s, +02° 03' 09" -> 12.4853, 2.0525
        sep_deg = angular_separation_deg(final_ra, final_dec, 12.4853, 2.0525)
        if sep_deg <= 1.0:
            score += 15
            feedback.append(f"Telescope is near final target 3C 273 (sep {sep_deg:.2f}°)")
        else:
            feedback.append(f"Telescope not near final target 3C 273 (sep {sep_deg:.2f}°)")
    else:
        feedback.append("Could not read final telescope coordinates")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }