#!/usr/bin/env python3
"""
Verifier for ultra_faint_dwarf_manual_dither task.

Primary verification leverages the exact physical FITS coordinate headers (OBJCTRA, OBJCTDEC) 
stamped at the moment of exposure by the INDI simulator. This prevents gaming where an agent 
takes all exposures in one spot and merely copies them across directories.

Criteria (100 pts total, pass >= 75):
1. Center frames valid (≥2 with RA~10.141, Dec~12.306) - 15 pts
2. North frames valid (≥2 with RA~10.141, Dec~12.389)  - 15 pts
3. South frames valid (≥2 with RA~10.141, Dec~12.223)  - 15 pts
4. East frames valid (≥2 with RA~10.146, Dec~12.306)   - 15 pts
5. West frames valid (≥2 with RA~10.135, Dec~12.306)   - 15 pts
6. Correct Filter used (Luminance)                     - 15 pts
7. Log created                                         - 10 pts
"""

import json
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Target coordinate offsets mapping (matches task.json metadata)
EXPECTED_POSITIONS = {
    "center": {"ra": 10.1411, "dec": 12.3064},
    "north":  {"ra": 10.1411, "dec": 12.3897},
    "south":  {"ra": 10.1411, "dec": 12.2231},
    "east":   {"ra": 10.1468, "dec": 12.3064},
    "west":   {"ra": 10.1354, "dec": 12.3064}
}

TOLERANCE_RA = 0.005
TOLERANCE_DEC = 0.02


def parse_coord(c_str):
    """
    Parse '10 08 27.96' (HH MM SS or DD MM SS) strings into float.
    INDI typically space-separates coordinates in headers.
    """
    if not c_str:
        return None
    try:
        # If it happens to already be a decimal format
        return float(c_str)
    except ValueError:
        pass
    
    parts = str(c_str).strip().replace(':', ' ').split()
    if len(parts) >= 3:
        try:
            p0 = float(parts[0])
            sign = -1.0 if (parts[0].startswith('-') or p0 < 0) else 1.0
            return sign * (abs(p0) + float(parts[1])/60.0 + float(parts[2])/3600.0)
        except ValueError:
            return None
    return None


def verify_ultra_faint_dwarf_manual_dither(traj, env_info, task_info):
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
    
    # ── Filter Valid Files ─────────────────────────────────────────────
    # Anti-gaming: Exclude the pre-seeded stale files (mtime < task_start)
    all_fits = result.get('fits_files', [])
    valid_fits = [f for f in all_fits if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    
    # Analyze by position
    correct_filter_used = True
    positions_passed = 0
    
    for pos, expected in EXPECTED_POSITIONS.items():
        # Get files saved in this sub-directory
        pos_files = [f for f in valid_fits if f.get('dir', '').lower() == pos]
        
        valid_frames_in_pos = 0
        for pf in pos_files:
            # Verify coordinates in header physically matched the dither offset
            ra_val = parse_coord(pf.get('objctra', ''))
            dec_val = parse_coord(pf.get('objctdec', ''))
            
            if ra_val is not None and dec_val is not None:
                if (abs(ra_val - expected['ra']) <= TOLERANCE_RA and 
                    abs(dec_val - expected['dec']) <= TOLERANCE_DEC):
                    valid_frames_in_pos += 1
            
            # Check filter strictly across all valid frames
            filt = pf.get('filter', '').strip().lower()
            if 'lum' not in filt and filt not in ['1', 'l']:
                correct_filter_used = False

        if valid_frames_in_pos >= 2:
            score += 15
            positions_passed += 1
            feedback.append(f"{pos.capitalize()}: Passed (Found {valid_frames_in_pos} valid offset frames)")
        elif valid_frames_in_pos == 1:
            score += 7
            feedback.append(f"{pos.capitalize()}: Partial (Only 1 valid offset frame)")
        else:
            feedback.append(f"{pos.capitalize()}: Failed (Missing or incorrect offset coordinates)")

    # ── Verify Filter ──────────────────────────────────────────────────
    if correct_filter_used and valid_fits:
        score += 15
        feedback.append("Correct filter (Luminance) used for frames.")
    elif not valid_fits:
        feedback.append("No valid frames to verify filter.")
    else:
        feedback.append("Incorrect filter detected in one or more frames.")

    # ── Verify Log ─────────────────────────────────────────────────────
    log_exists = result.get('log_exists', False)
    log_mtime = result.get('log_mtime', 0)
    if log_exists and log_mtime > task_start:
        score += 10
        feedback.append("Dither completion log successfully created.")
    else:
        feedback.append("Dither completion log missing.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }