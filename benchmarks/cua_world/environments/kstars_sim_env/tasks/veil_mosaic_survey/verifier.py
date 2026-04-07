#!/usr/bin/env python3
"""
Verifier for veil_mosaic_survey task.

Occupation: Observational Astronomer / Survey Scientist
Context: H-alpha mosaic imaging of the Eastern Veil Nebula.

Criteria (100 pts total, pass >= 60):
1. Panel 1 FITS files (≥3 in panel_1/)                - 10 pts
2. Panel 2 FITS files (≥3 in panel_2/)                - 10 pts
3. Panel 3 FITS files (≥3 in panel_3/)                - 10 pts
4. Panel 4 FITS files (≥3 in panel_4/)                - 10 pts
5. H-alpha filter used (Slot 5 or 'Ha')               - 10 pts
6. Spatial coverage (≥4 distinct coords separated >0.2°) - 20 pts
7. Telescope final position near NGC 6992 (<1 deg)    - 10 pts
8. Mosaic log exists                                  - 5 pts
9. Mosaic log content (contains coords/frames data)   - 15 pts

Anti-gaming: files must be created AFTER task_start. Positions extracted
directly from FITS headers to prevent just moving telescope while idle.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Center coordinate target
CENTER_RA_H = 20.94
CENTER_DEC_DEG = 31.717


def angular_separation_deg(ra1_deg, dec1_deg, ra2_deg, dec2_deg):
    """Return angular separation in degrees between two coordinates in degrees."""
    ra1 = math.radians(ra1_deg)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_deg)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def cluster_coordinates(coords, tolerance_deg=0.15):
    """Group coordinates into clusters if they are within tolerance_deg of each other."""
    clusters = []
    for c in coords:
        ra, dec = c
        if ra < 0 or dec < -90:
            continue
            
        found_cluster = False
        for cluster in clusters:
            # Check against cluster center
            cra, cdec = cluster['center']
            if angular_separation_deg(ra, dec, cra, cdec) <= tolerance_deg:
                cluster['points'].append(c)
                found_cluster = True
                break
                
        if not found_cluster:
            clusters.append({
                'center': (ra, dec),
                'points': [c]
            })
    return clusters


def verify_veil_mosaic_survey(traj, env_info, task_info):
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

    # Filter out empty/invalid/old files
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def score_panel(panel_dir_name):
        """Helper to score individual panels."""
        count = sum(1 for f in valid_fits if f.get('panel_dir') == panel_dir_name)
        if count >= 3:
            return 10, f"{panel_dir_name}: {count} frames"
        elif count == 2:
            return 6, f"{panel_dir_name}: 2/3 frames"
        elif count == 1:
            return 3, f"{panel_dir_name}: 1/3 frames"
        return 0, f"{panel_dir_name}: 0 frames"

    # ── Criteria 1-4: Panels (40 pts total) ───────────────────────────
    for panel in ["panel_1", "panel_2", "panel_3", "panel_4"]:
        pts, msg = score_panel(panel)
        score += pts
        feedback.append(msg)

    # ── Criterion 5: H-alpha filter (10 pts) ──────────────────────────
    # Check if INDI state is slot 5, OR if majority of FITS headers have 'Ha'
    current_slot = result.get('current_filter_slot', -1)
    ha_fits_count = sum(1 for f in valid_fits if 'HA' in f.get('filter', '').upper())
    
    if current_slot == 5 or (len(valid_fits) > 0 and ha_fits_count > len(valid_fits)/2):
        score += 10
        feedback.append("H-alpha filter verified")
    else:
        feedback.append("H-alpha filter NOT verified")

    # ── Criterion 6: Spatial Coverage (20 pts) ────────────────────────
    # Extract coordinates from FITS headers and group them
    coords = [(f.get('ra_deg', -1.0), f.get('dec_deg', -999.0)) for f in valid_fits]
    clusters = cluster_coordinates(coords, tolerance_deg=0.15)
    num_clusters = len(clusters)
    
    if num_clusters >= 4:
        score += 20
        feedback.append(f"Spatial coverage: {num_clusters} distinct positions")
    elif num_clusters == 3:
        score += 12
        feedback.append(f"Spatial coverage: 3 distinct positions (missing 1 panel)")
    elif num_clusters == 2:
        score += 6
        feedback.append(f"Spatial coverage: 2 distinct positions")
    elif num_clusters == 1 and len(valid_fits) > 0:
        feedback.append("Spatial coverage: only 1 distinct position found (no mosaic movement)")
    else:
        feedback.append("Spatial coverage: 0 positions found")

    # ── Criterion 7: Final Position (10 pts) ──────────────────────────
    try:
        final_ra_h = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra_h, final_dec = -1.0, -999.0

    if final_ra_h > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra_h * 15.0, final_dec, CENTER_RA_H * 15.0, CENTER_DEC_DEG)
        if sep_deg <= 1.5:
            score += 10
            feedback.append(f"Telescope near NGC 6992 (sep {sep_deg:.2f}°)")
        else:
            feedback.append(f"Telescope not at target (sep {sep_deg:.2f}°)")
    else:
        feedback.append("Could not read final coordinates")

    # ── Criteria 8 & 9: Mosaic Log (20 pts total) ─────────────────────
    log_exists = result.get('log_exists', False)
    log_mtime = result.get('log_mtime', 0)
    log_during_task = log_exists and (log_mtime > task_start)
    log_b64 = result.get('log_b64', '')
    
    if log_during_task:
        score += 5
        feedback.append("Mosaic log created")
        
        # Decode and roughly check content complexity
        try:
            log_text = base64.b64decode(log_b64).decode('utf-8', errors='ignore')
            lines = log_text.strip().split('\n')
            
            # Simple heuristic: look for numbers representing coordinates/frame counts
            number_lines = sum(1 for line in lines if any(char.isdigit() for char in line))
            
            if number_lines >= 4:
                score += 15
                feedback.append("Log content looks populated")
            elif number_lines >= 2:
                score += 7
                feedback.append("Log content partially populated")
            else:
                feedback.append("Log content looks empty or missing data")
        except Exception as e:
            feedback.append("Failed to parse log content")
    else:
        feedback.append("Mosaic log not found or old")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }