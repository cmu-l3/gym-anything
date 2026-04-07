#!/usr/bin/env python3
"""
Verifier for Tabular Dataset Generation task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. CSV file exists and was modified/created during task (15 points)
2. CSV contains the correct headers: band_2, band_3, simple_ratio (25 points)
3. Spatial subset was successful: 40,000 <= rows <= 250,000 (25 points)
4. Mathematical anti-gaming check: simple_ratio == band_2 / band_3 for sampled rows (25 points)
5. VLM Trajectory: verifies proper UI interaction (10 points)

Pass threshold: 70
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent performing a machine learning data extraction task in ESA SNAP Desktop.

The agent's goals were:
1. Use 'Raster > Band Maths' to create a new band.
2. Use 'Raster > Subset' to create a spatial crop of the image (e.g., entering 300x300 in the Pixel Coordinates tab).
3. Use 'File > Export > CSV' to save the dataset.

Review these trajectory frames and determine if the agent utilized the expected SNAP UI dialogs (Band Maths, Subset tool, or Export dialog).

Respond in JSON format:
{
    "ui_dialogs_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Briefly describe if you see the Band Maths, Spatial Subset, or Export CSV dialogs."
}
"""

def verify_tabular_dataset_generation_for_ml(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_rows = metadata.get('min_rows', 40000)
    max_rows = metadata.get('max_rows', 250000)

    score = 0
    feedback_parts = []

    # ================================================================
    # 1. Retrieve Result JSON
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ml_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ================================================================
    # 2. File Existence & Modification (15 pts)
    # ================================================================
    csv_found = result.get('csv_found', False)
    csv_created = result.get('csv_created_after_start', False)
    
    if csv_found and csv_created:
        score += 15
        feedback_parts.append("Exported file found and created during task (+15)")
    elif csv_found:
        score += 8
        feedback_parts.append("Exported file found but timestamp unclear (+8)")
    else:
        feedback_parts.append("No exported CSV file found (0/15)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # ================================================================
    # 3. Headers Check (25 pts)
    # ================================================================
    headers = [h.lower() for h in result.get('headers', [])]
    b2_idx, b3_idx, ratio_idx = -1, -1, -1
    
    for i, h in enumerate(headers):
        if 'band_2' in h: b2_idx = i
        if 'band_3' in h: b3_idx = i
        if 'simple_ratio' in h: ratio_idx = i

    has_required_cols = b2_idx >= 0 and b3_idx >= 0 and ratio_idx >= 0
    if has_required_cols:
        score += 25
        feedback_parts.append("Required columns present in export (+25)")
    else:
        missing = []
        if b2_idx < 0: missing.append("band_2")
        if b3_idx < 0: missing.append("band_3")
        if ratio_idx < 0: missing.append("simple_ratio")
        feedback_parts.append(f"Missing columns: {', '.join(missing)} (0/25)")

    # ================================================================
    # 4. Subset Validation via Row Count (25 pts)
    # ================================================================
    row_count = result.get('row_count', 0)
    if min_rows <= row_count <= max_rows:
        score += 25
        feedback_parts.append(f"Row count {row_count} confirms successful spatial subset (+25)")
    elif row_count > max_rows:
        score += 10
        feedback_parts.append(f"Row count {row_count} too large (subset was not performed properly) (+10)")
    elif row_count > 0:
        score += 10
        feedback_parts.append(f"Row count {row_count} too small (+10)")
    else:
        feedback_parts.append("CSV contains no data rows (0/25)")

    # ================================================================
    # 5. Mathematical Anti-Gaming Check (25 pts)
    # ================================================================
    samples = result.get('samples', [])
    if has_required_cols and len(samples) > 0:
        valid_rows = 0
        correct_rows = 0
        for row in samples:
            try:
                b2 = float(row[b2_idx])
                b3 = float(row[b3_idx])
                ratio = float(row[ratio_idx])
                if abs(b3) > 1e-6:
                    expected = b2 / b3
                    if abs(ratio - expected) <= max(0.01, 0.05 * abs(expected)):
                        correct_rows += 1
                    valid_rows += 1
                else:
                    valid_rows += 1
                    correct_rows += 1  # Gracefully skip div/0 logic
            except Exception:
                pass
                
        if valid_rows > 0 and (correct_rows / valid_rows) >= 0.8:
            score += 25
            feedback_parts.append("Mathematical integrity verified (+25)")
        else:
            feedback_parts.append("Mathematical integrity check failed: simple_ratio != band_2 / band_3 (0/25)")
    else:
        feedback_parts.append("Could not verify mathematical integrity (0/25)")

    # ================================================================
    # 6. VLM Trajectory Check (10 pts)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    frames = sample_trajectory_frames(traj, n=5)
    
    if query_vlm and frames:
        try:
            resp = query_vlm(prompt=VLM_PROMPT, images=frames)
            if resp.get("success") and resp.get("parsed", {}).get("ui_dialogs_visible"):
                score += 10
                feedback_parts.append("VLM confirms UI usage (+10)")
            else:
                feedback_parts.append("VLM did not detect expected UI usage (+0)")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM verification skipped (error)")
    else:
        feedback_parts.append("VLM verification skipped (no frames or API)")

    # ================================================================
    # Final Evaluation
    # ================================================================
    passed = score >= 70 and has_required_cols
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }