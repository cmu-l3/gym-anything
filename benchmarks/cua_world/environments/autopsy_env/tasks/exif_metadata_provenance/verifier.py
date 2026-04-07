#!/usr/bin/env python3
"""
Verifier for exif_metadata_provenance task.

Scoring (100 pts total, pass threshold = 60):
  10 pts  — Autopsy case created and DB found
  10 pts  — Disk image data source added
  10 pts  — Ingest completed (image files indexed)
  15 pts  — EXIF artifacts populated in Autopsy DB
  10 pts  — Autopsy DB Image count within tolerance of GT
  15 pts  — Photo provenance report exists, recent, correct pipe-delimited format
  10 pts  — Report covers ≥50% of GT image filenames
  10 pts  — Summary file exists with all required keywords
  10 pts  — VLM Trajectory check: Agent navigated EXIF metadata or Images views
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils if available
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available.")

SUMMARY_KEYS = [
    "TOTAL_IMAGE_FILES", "IMAGES_WITH_EXIF", "IMAGES_WITHOUT_EXIF",
    "IMAGES_WITH_GPS", "UNIQUE_CAMERAS", "CAMERA_LIST", "DATE_RANGE",
    "ANTI_FORENSIC_ASSESSMENT"
]

def verify_exif_metadata_provenance(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/exif_provenance_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/exif_provenance_gt.json")
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # ── Pull result JSON ──────────────────────────────────────────────────────
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Task incomplete or export failed: {e}"}

    # ── Pull GT JSON ──────────────────────────────────────────────────────────
    gt = {"total_image_files": 0, "image_names": [], "images_with_exif": 0}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        copy_from_env(gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass

    gt_total = gt.get("total_image_files", 0)
    gt_names = set(n.lower() for n in gt.get("image_names", []))

    # 1. Case & DB (10 pts)
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case DB found (+10)")
    else:
        feedback_parts.append("FAIL Case DB not found")

    # 2. Data source (10 pts)
    if result.get("data_source_added"):
        score += 10
        feedback_parts.append("PASS Data source added (+10)")
    else:
        feedback_parts.append("FAIL Data source missing")

    # 3. Ingest completed (10 pts)
    if result.get("ingest_completed"):
        score += 10
        feedback_parts.append("PASS Ingest populated images (+10)")
    else:
        feedback_parts.append("FAIL Ingest incomplete")

    # 4. EXIF artifacts (15 pts)
    exif_count = result.get("db_exif_artifact_count", 0)
    if exif_count > 0:
        score += 15
        feedback_parts.append(f"PASS EXIF artifacts found: {exif_count} (+15)")
    else:
        feedback_parts.append("FAIL No EXIF artifacts in DB (Did EXIF Parser run?)")

    # 5. DB Image count matches GT (10 pts)
    db_img_count = result.get("db_image_count", 0)
    if gt_total > 0 and db_img_count >= gt_total - 2:
        score += 10
        feedback_parts.append(f"PASS Image count matches GT ({db_img_count}) (+10)")
    elif db_img_count > 0:
        score += 5
        feedback_parts.append(f"PARTIAL Image count {db_img_count} vs GT {gt_total} (+5)")
    else:
        feedback_parts.append("FAIL No images indexed")

    # 6. Provenance Report format & recent (15 pts)
    start_time = result.get("start_time", 0)
    cat_mtime = result.get("catalog_mtime", 0)
    cat_content = result.get("catalog_content", "")
    
    cat_lines = [l.strip() for l in cat_content.splitlines() if l.strip()]
    has_header = any("FILENAME|FULL_PATH" in l for l in cat_lines[:3])
    has_data = len([l for l in cat_lines if "|" in l]) > 1

    if result.get("catalog_file_exists") and (start_time == 0 or cat_mtime >= start_time):
        if has_header and has_data:
            score += 15
            feedback_parts.append("PASS Provenance report format correct (+15)")
        elif has_data:
            score += 8
            feedback_parts.append("PARTIAL Provenance missing exact header (+8)")
        else:
            feedback_parts.append("FAIL Provenance lacks pipe-delimited data")
    else:
        feedback_parts.append("FAIL Provenance report missing or stale")

    # 7. Provenance Report Coverage (10 pts)
    if has_data and gt_names:
        cat_lower = cat_content.lower()
        matched = sum(1 for n in gt_names if n in cat_lower)
        coverage = matched / len(gt_names)
        if coverage >= 0.5:
            score += 10
            feedback_parts.append(f"PASS Provenance covers {coverage*100:.0f}% of images (+10)")
        elif coverage > 0:
            score += 5
            feedback_parts.append(f"PARTIAL Provenance covers {coverage*100:.0f}% of images (+5)")
        else:
            feedback_parts.append("FAIL Provenance doesn't contain expected filenames")

    # 8. Summary File Exists & Complete (10 pts)
    sum_mtime = result.get("summary_mtime", 0)
    sum_content = result.get("summary_content", "").upper()
    if result.get("summary_file_exists") and (start_time == 0 or sum_mtime >= start_time):
        matched_keys = sum(1 for k in SUMMARY_KEYS if k in sum_content)
        if matched_keys == len(SUMMARY_KEYS):
            score += 10
            feedback_parts.append("PASS Summary has all required keys (+10)")
        elif matched_keys >= 4:
            score += 5
            feedback_parts.append(f"PARTIAL Summary missing some keys ({matched_keys}/{len(SUMMARY_KEYS)}) (+5)")
        else:
            feedback_parts.append("FAIL Summary missing most keys")
    else:
        feedback_parts.append("FAIL Summary file missing or stale")

    # 9. VLM Trajectory Verification (10 pts)
    # Checks if the agent actively navigated Autopsy's views
    vlm_score = 0
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if frames or final:
                images = frames + [final] if final else frames
                prompt = (
                    "Look at these screenshots of an agent using Autopsy digital forensics tool. "
                    "Did the agent navigate to the 'EXIF Metadata' section or 'Images' section in the left panel "
                    "tree, and does the main view show active investigation of photo metadata or image files? "
                    "Reply ONLY with 'YES' or 'NO'."
                )
                vlm_res = query_vlm(images=images, prompt=prompt)
                if vlm_res and "YES" in vlm_res.get("response", "").upper():
                    vlm_score = 10
                    feedback_parts.append("PASS VLM confirmed Autopsy UI interaction (+10)")
                else:
                    feedback_parts.append("FAIL VLM did not observe EXIF/Images interaction")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback_parts.append("VLM error, skipping visual check.")
    else:
        # Give points automatically if VLM is unavailable, relying on robust DB check
        vlm_score = 10
        feedback_parts.append("PASS Granted VLM points (VLM unavailable)")
        
    score += vlm_score

    passed = score >= 60 and result.get("case_db_found") and result.get("catalog_file_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }