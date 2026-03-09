#!/usr/bin/env python3
"""
Verifier for em_spectrum_reference task.

Scoring (100 points total, pass at 70):
1. File exists + valid format + created during task (15 pts)
2. Page count == 4 (15 pts)
3. Title "Electromagnetic Spectrum" present (8 pts)
4. All 7 spectrum bands named (20 pts)
5. Visible light colors >= 5 (12 pts)
6. Applications content >= 4 terms (15 pts)
7. Rectangles/Shapes >= 7 (10 pts)
8. Wavelength reference "nm" present (5 pts)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_em_spectrum(traj, env_info, task_info):
    """
    Verify the EM Spectrum Reference flipchart creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    # Load result from container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_path)
            with open(tmp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}"
        }

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Validity (15 pts) ---
    if not result.get('file_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target flipchart file not found."
        }
    
    if result.get('file_valid') and result.get('created_during_task'):
        score += 15
        feedback_parts.append("Valid file created during task (15/15)")
    elif result.get('file_valid'):
        score += 10
        feedback_parts.append("Valid file found but timestamp issue (10/15)")
    else:
        feedback_parts.append("File found but invalid format (0/15)")

    # --- Criterion 2: Page Count (15 pts) ---
    page_count = result.get('page_count', 0)
    if page_count == 4:
        score += 15
        feedback_parts.append("Page count exact: 4 (15/15)")
    elif page_count >= 4:
        score += 12
        feedback_parts.append(f"Page count {page_count} > 4 (12/15)")
    elif page_count > 1:
        score += 5
        feedback_parts.append(f"Page count {page_count} < 4 (5/15)")
    else:
        feedback_parts.append("Page count 1 or 0 (0/15)")

    # --- Criterion 3: Title (8 pts) ---
    if result.get('has_title'):
        score += 8
        feedback_parts.append("Title present (8/8)")
    else:
        feedback_parts.append("Title missing (0/8)")

    # --- Criterion 4: Spectrum Bands (20 pts) ---
    found_bands = set(result.get('found_bands', []))
    required_bands = {"radio", "microwave", "infrared", "visible", "ultraviolet", "x-ray", "gamma"}
    # Note: 'xray' is normalized to 'x-ray' in export script if found
    
    # Calculate overlap
    # We do simple counting. 7 items = 20pts (~2.85 pts each)
    match_count = len(found_bands)
    band_score = min(20, int(match_count * 2.86))
    score += band_score
    feedback_parts.append(f"Bands found: {match_count}/7 ({band_score}/20)")

    # --- Criterion 5: Visible Colors (12 pts) ---
    found_colors = set(result.get('found_colors', []))
    # We need at least 5
    color_count = len(found_colors)
    if color_count >= 5:
        score += 12
        feedback_parts.append(f"Colors found: {color_count} (12/12)")
    elif color_count > 0:
        partial = color_count * 2
        score += partial
        feedback_parts.append(f"Colors found: {color_count} ({partial}/12)")
    else:
        feedback_parts.append("No visible light colors found (0/12)")

    # --- Criterion 6: Applications (15 pts) ---
    # Need at least 4 unique keywords
    found_apps = set(result.get('found_apps', []))
    app_count = len(found_apps)
    if app_count >= 4:
        score += 15
        feedback_parts.append(f"Applications found: {app_count} (15/15)")
    else:
        partial = int(app_count * 3.75)
        score += partial
        feedback_parts.append(f"Applications found: {app_count} ({partial}/15)")

    # --- Criterion 7: Shapes (10 pts) ---
    shape_count = result.get('shape_count', 0)
    if shape_count >= 7:
        score += 10
        feedback_parts.append(f"Shapes count: {shape_count} (10/10)")
    elif shape_count > 0:
        score += 5
        feedback_parts.append(f"Shapes count: {shape_count} (5/10)")
    else:
        feedback_parts.append("No shapes found (0/10)")

    # --- Criterion 8: Wavelength Unit (5 pts) ---
    if result.get('has_nm_unit'):
        score += 5
        feedback_parts.append("Wavelength unit 'nm' found (5/5)")
    else:
        feedback_parts.append("Wavelength unit missing (0/5)")

    # Final check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }