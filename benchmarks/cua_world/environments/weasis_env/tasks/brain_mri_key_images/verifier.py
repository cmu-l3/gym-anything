#!/usr/bin/env python3
"""
Verifier for brain_mri_key_images task.

A Radiologic Technologist must:
1. Load brain MRI series in Weasis
2. Apply brain window (W:80 L:40)
3. Select 3 key images at standard anatomical levels:
   - Vertex / high convexity (superior cortex)
   - Basal ganglia / thalamus level
   - Posterior fossa / cerebellum level
4. Export each as key_image_01.png, key_image_02.png, key_image_03.png
   to /home/ga/DICOM/exports/key_images/
5. Write a summary to /home/ga/DICOM/exports/key_image_summary.txt
   documenting anatomical level, slice number, and window settings

Scoring (100 points):
- 45 pts: Key images exported (15 per image: exists, new, ≥20KB)
- 20 pts: At least 3 new PNG files found anywhere (catches alternate naming)
- 20 pts: Summary file exists, is new, has content (>30 chars)
- 15 pts: Summary mentions anatomical levels (vertex/basal ganglia/cerebellum)

Pass threshold: 60 points
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/brain_mri_key_images_result.json"
PASS_THRESHOLD = 60


def verify_brain_mri_key_images(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []

    # ---------------------------------------------------------------
    # Criterion 1 (45 pts): Three key images exported, named correctly
    # 15 pts per image: exists + new + ≥20KB
    # ---------------------------------------------------------------
    valid_count = result.get("valid_key_images_count", 0)
    any_new_in_key_dir = result.get("any_new_png_in_key_images", 0)
    any_new_in_exports = result.get("any_new_png_in_exports", 0)

    img_scores = []
    for i in range(1, 4):
        exists = result.get(f"key_image_0{i}_exists", False)
        is_new = result.get(f"key_image_0{i}_is_new", False)
        size_kb = result.get(f"key_image_0{i}_size_kb", 0)
        if exists and is_new and size_kb >= 20:
            img_scores.append(15)
        elif exists and is_new:
            img_scores.append(8)
        elif exists:
            img_scores.append(0)
        else:
            img_scores.append(0)

    images_score = sum(img_scores)

    # If images not correctly named, fall back on any-new-PNG count
    if images_score < 30 and any_new_in_key_dir >= 3:
        images_score = max(images_score, 35)
        feedback_parts.append(f"{any_new_in_key_dir} new PNGs in key_images dir (alternate naming) ({images_score}/45)")
    elif images_score < 30 and any_new_in_exports >= 3:
        images_score = max(images_score, 30)
        feedback_parts.append(f"{any_new_in_exports} new PNGs in exports dir (not in key_images subdir) ({images_score}/45)")
    elif images_score < 30 and any_new_in_exports >= 1:
        images_score = max(images_score, 15)
        feedback_parts.append(f"{any_new_in_exports} new PNGs in exports dir (only {any_new_in_exports}/3) ({images_score}/45)")
    else:
        counts = [f"img{i+1}={img_scores[i]}" for i in range(3)]
        feedback_parts.append(f"Key images: {', '.join(counts)} ({images_score}/45)")

    score += images_score

    # ---------------------------------------------------------------
    # Criterion 2 (20 pts): 3 new PNGs present anywhere in exports
    # Catches agents that exported but used wrong filenames/directory
    # ---------------------------------------------------------------
    if any_new_in_exports >= 3:
        score += 20
        feedback_parts.append(f"3+ new PNG exports confirmed ({any_new_in_exports} total) (20/20)")
    elif any_new_in_exports == 2:
        score += 13
        feedback_parts.append(f"Only 2 new PNG exports found (expected 3) (13/20)")
    elif any_new_in_exports == 1:
        score += 7
        feedback_parts.append(f"Only 1 new PNG export found (expected 3) (7/20)")
    else:
        feedback_parts.append("No new PNG exports found in exports directory (0/20)")

    # ---------------------------------------------------------------
    # Criterion 3 (20 pts): Summary file exists, new, has content
    # ---------------------------------------------------------------
    summ_exists = result.get("summary_exists", False)
    summ_new = result.get("summary_is_new", False)
    summ_size = result.get("summary_size_bytes", 0)

    if summ_exists and summ_new and summ_size >= 30:
        score += 20
        feedback_parts.append(f"Key image summary OK ({summ_size} bytes) (20/20)")
    elif summ_exists and summ_new:
        score += 10
        feedback_parts.append(f"Summary exists+new but very short ({summ_size} bytes) (10/20)")
    elif summ_exists:
        feedback_parts.append("Summary exists but NOT modified after task start (0/20)")
    else:
        feedback_parts.append("No key image summary found (0/20)")

    # ---------------------------------------------------------------
    # Criterion 4 (15 pts): Summary mentions anatomical levels
    # The summary should document which anatomical level each image represents
    # ---------------------------------------------------------------
    anat_mentioned = result.get("anatomical_levels_mentioned", False)
    window_mentioned = result.get("window_mentioned_in_summary", False)
    slice_mentioned = result.get("slice_info_mentioned", False)

    if anat_mentioned:
        score += 15
        feedback_parts.append("Anatomical levels documented in summary (15/15)")
    else:
        # Try direct text check
        if summ_exists and summ_new:
            try:
                tmp_summ = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
                tmp_summ.close()
                copy_from_env("/home/ga/DICOM/exports/key_image_summary.txt", tmp_summ.name)
                with open(tmp_summ.name, "r", errors="replace") as f:
                    summ_text = f.read()
                os.unlink(tmp_summ.name)
                has_anat = bool(re.search(
                    r"\b(vertex|convex|basal|gangli|thalamus|cerebellum|posterior\s+fossa|"
                    r"fourth\s+ventricle|pons|brainstem|cortex|caudate|putamen)\b",
                    summ_text, re.IGNORECASE))
                has_window = bool(re.search(
                    r"\b(window|W/L|WW|WL|80|40)\b", summ_text, re.IGNORECASE))
                has_slice = bool(re.search(
                    r"\b(slice|position|level|series|image\s+[0-9]|#\s*[0-9])\b",
                    summ_text, re.IGNORECASE))
                if has_anat and has_window and has_slice:
                    score += 15
                    feedback_parts.append("Summary complete: anatomy+window+slice documented (15/15)")
                elif has_anat:
                    score += 10
                    feedback_parts.append("Anatomical levels in summary (partial) (10/15)")
                elif has_window or has_slice:
                    score += 5
                    feedback_parts.append("Partial documentation in summary (5/15)")
                else:
                    feedback_parts.append("Summary lacks anatomical level documentation (0/15)")
            except Exception:
                feedback_parts.append("Could not verify summary content (0/15)")
        else:
            feedback_parts.append("Summary unavailable for content check (0/15)")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
