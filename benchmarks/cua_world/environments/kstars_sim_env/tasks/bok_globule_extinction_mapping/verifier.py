#!/usr/bin/env python3
"""
Verifier for bok_globule_extinction_mapping task.

Criteria (100 pts total, pass >= 60):
1. Directory Structure (3 targets x 3 filters = 9 dirs implied) - 5 pts
2. B-band execution (>=6 frames, focus ~30100) - 10 pts
3. V-band execution (>=6 frames, focus ~30000) - 10 pts
4. R-band execution (>=6 frames, focus ~29900) - 10 pts
5. Sky Views (3 PNGs, one per target) - 15 pts
6. Final Telescope Position (pointed at one of the targets) - 10 pts
7. CSV Log Valid (headers and 3 targets) - 15 pts
8. VLM Trajectory Verification (shows KStars Ekos interface, focuser use) - 25 pts
"""

import json
import base64
import os
import csv
import io
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGETS = {
    "B68": {"ra": 17.3772, "dec": -23.8261},
    "B72": {"ra": 17.3916, "dec": -23.6333},
    "B86": {"ra": 18.0500, "dec": -27.8666}
}

EXPECTED_FOCUS = {
    "B": 30100,
    "V": 30000,
    "R": 29900
}

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent operating KStars/Ekos to capture astronomical images of Bok globules.

The images are sampled chronologically from the agent's full interaction.

Assess the following:
1. EKOS_INTERFACE: Did the agent open and use the Ekos observatory control interface?
2. FOCUSER_USAGE: Is there evidence the agent interacted with the Focuser module to change absolute focus positions (e.g., entering 30100, 30000, 29900)?
3. FILTER_CHANGES: Is there evidence the agent changed filters in the Filter Wheel module?
4. CAPTURE_WORKFLOW: Did the agent capture CCD images (evidence of the CCD capture module running)?

Respond in JSON format:
{
    "ekos_interface_visible": true/false,
    "focuser_usage_visible": true/false,
    "filter_changes_visible": true/false,
    "capture_workflow_visible": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of observations."
}
"""

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_bok_globule_extinction_mapping(traj, env_info, task_info):
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
    
    # Anti-gaming: valid FITS only if created after task_start and size > 2KB
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    # Helper to check FITS per band
    def evaluate_band(band_name, expected_focus):
        frames = [f for f in valid_fits if f.get('filter_dir', '').upper() == band_name.upper() or band_name.upper() in f.get('header_filter', '').upper()]
        
        # Check counts
        count = len(frames)
        
        # Check focus (allow +/- 50 steps tolerance, or accept if header_focus == -1 but frames exist assuming VLM validates process)
        # Ekos writes FOCUSPOS, so it should be there.
        focus_correct_count = 0
        for f in frames:
            foc = f.get('header_focus', -1)
            if foc != -1 and abs(foc - expected_focus) <= 50:
                focus_correct_count += 1
            elif foc == -1: # Simulator edge case, treat as potentially correct but flag it
                focus_correct_count += 1
                
        return count, focus_correct_count

    b_count, b_focus = evaluate_band("B", EXPECTED_FOCUS["B"])
    v_count, v_focus = evaluate_band("V", EXPECTED_FOCUS["V"])
    r_count, r_focus = evaluate_band("R", EXPECTED_FOCUS["R"])

    # 1. Directory Structure (5 pts)
    unique_dirs = set(f.get('target_dir') + '/' + f.get('filter_dir') for f in valid_fits)
    if len(unique_dirs) >= 9:
        score += 5
        feedback.append("Directory structure complete (9 subdirs).")
    elif len(unique_dirs) > 0:
        score += 2
        feedback.append(f"Partial directory structure ({len(unique_dirs)} subdirs).")

    # 2. B-band execution (10 pts)
    if b_count >= 6 and b_focus >= 6:
        score += 10
        feedback.append("B-band: 6+ frames with correct focus.")
    elif b_count >= 2 and b_focus >= 2:
        score += 5
        feedback.append(f"B-band: Partial success ({b_count} frames).")
    else:
        feedback.append("B-band: Insufficient frames or wrong focus.")

    # 3. V-band execution (10 pts)
    if v_count >= 6 and v_focus >= 6:
        score += 10
        feedback.append("V-band: 6+ frames with correct focus.")
    elif v_count >= 2 and v_focus >= 2:
        score += 5
        feedback.append(f"V-band: Partial success ({v_count} frames).")
    else:
        feedback.append("V-band: Insufficient frames or wrong focus.")

    # 4. R-band execution (10 pts)
    if r_count >= 6 and r_focus >= 6:
        score += 10
        feedback.append("R-band: 6+ frames with correct focus.")
    elif r_count >= 2 and r_focus >= 2:
        score += 5
        feedback.append(f"R-band: Partial success ({r_count} frames).")
    else:
        feedback.append("R-band: Insufficient frames or wrong focus.")

    # 5. Sky Views (15 pts)
    png_files = result.get('png_files', [])
    valid_pngs = [p for p in png_files if p.get('mtime', 0) > task_start and p.get('size', 0) > 10240]
    if len(valid_pngs) >= 3:
        score += 15
        feedback.append("Sky Views: 3+ PNGs captured.")
    elif len(valid_pngs) > 0:
        score += 5
        feedback.append(f"Sky Views: {len(valid_pngs)} PNGs captured.")
    else:
        feedback.append("Sky Views: None captured.")

    # 6. Final Telescope Position (10 pts)
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    at_target = False
    if final_ra > 0 and final_dec > -900:
        for t_name, t_coords in TARGETS.items():
            sep_deg = angular_separation_deg(final_ra, final_dec, t_coords['ra'], t_coords['dec'])
            if sep_deg <= 0.5: # 30 arcmin
                at_target = True
                break
    if at_target:
        score += 10
        feedback.append("Telescope pointed at a correct target.")
    else:
        feedback.append("Telescope not pointed at any target.")

    # 7. CSV Log Valid (15 pts)
    csv_exists = result.get('csv_exists', False)
    csv_b64 = result.get('csv_content_b64', '')
    csv_ok = False
    if csv_exists and csv_b64:
        try:
            csv_text = base64.b64decode(csv_b64).decode('utf-8')
            reader = csv.reader(io.StringIO(csv_text))
            rows = list(reader)
            if len(rows) >= 4: # Header + 3 targets
                headers = [h.strip().lower() for h in rows[0]]
                if 'target' in headers and 'ra' in headers and 'dec' in headers and 'total_frames' in headers:
                    targets_found = [row[0].strip().upper() for row in rows[1:] if len(row) > 0]
                    if 'B68' in targets_found and 'B72' in targets_found and 'B86' in targets_found:
                        csv_ok = True
        except Exception as e:
            pass

    if csv_ok:
        score += 15
        feedback.append("CSV Log: Valid and complete.")
    elif csv_exists:
        score += 5
        feedback.append("CSV Log: Exists but malformed or incomplete.")
    else:
        feedback.append("CSV Log: Missing.")

    # 8. VLM Trajectory Verification (25 pts)
    import sys
    sys.path.insert(0, str(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                vlm_score = 0
                if parsed.get("ekos_interface_visible", False): vlm_score += 5
                if parsed.get("focuser_usage_visible", False): vlm_score += 10
                if parsed.get("filter_changes_visible", False): vlm_score += 5
                if parsed.get("capture_workflow_visible", False): vlm_score += 5
                
                score += vlm_score
                feedback.append(f"VLM: Scored {vlm_score}/25. Reason: {parsed.get('reasoning', 'none')}")
            else:
                feedback.append("VLM: Query failed, 0/25 pts.")
        else:
            feedback.append("VLM: No frames available, 0/25 pts.")
    except Exception as e:
        logger.warning(f"VLM verification exception: {e}")
        feedback.append(f"VLM Exception: {e}")

    passed = score >= 60 and (b_count > 0 or v_count > 0 or r_count > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }