#!/usr/bin/env python3
"""
Verifier for loc_historical_image_curation task.

Scoring Criteria (100 points total):
1. Directory Structure (10 pts): ~/Documents/curated_images exists.
2. High-Res Assets (45 pts): 3 files exist, each > 2MB (15 pts per file).
3. Metadata File (15 pts): credits.json exists and is valid JSON.
4. Metadata Quality (15 pts): Entries have Title, Call Number, URL.
5. Research Evidence (15 pts): Firefox history shows visits to LOC item pages.

Pass Threshold: 70 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_loc_historical_image_curation(traj, env_info, task_info):
    """Verify LOC image curation task."""
    
    # 1. Retrieve result from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    # Get metadata for threshold configuration
    metadata = task_info.get('metadata', {})
    min_size_bytes = metadata.get('min_file_size_bytes', 2000000) # 2MB default
    
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/loc_curation_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error reading task result: {e}"}

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Directory Structure (10 pts) ---
    if result.get('dir_exists', False):
        score += 10
        feedback_parts.append("Target directory created (+10)")
    else:
        feedback_parts.append("Target directory NOT found (0/10)")

    # --- Criterion 2: High-Res Assets (45 pts) ---
    files = result.get('downloaded_files', [])
    valid_files_count = 0
    small_files_count = 0
    
    for f in files:
        if f['size_bytes'] >= min_size_bytes:
            valid_files_count += 1
        else:
            small_files_count += 1
            
    # Cap at 3 files for points
    points_per_file = 15
    files_score = min(valid_files_count, 3) * points_per_file
    score += files_score
    
    if valid_files_count >= 3:
        feedback_parts.append(f"Found {valid_files_count} high-res images (+{files_score})")
    elif valid_files_count > 0:
        feedback_parts.append(f"Found {valid_files_count} high-res images, need 3 (+{files_score})")
    
    if small_files_count > 0:
        feedback_parts.append(f"Warning: {small_files_count} files were too small (<2MB) - likely thumbnails")
    
    if valid_files_count == 0 and small_files_count == 0:
        feedback_parts.append("No image files downloaded (0/45)")

    # --- Criterion 3: Metadata File Existence (15 pts) ---
    credits_content = result.get('credits_content')
    if result.get('credits_exists', False) and result.get('credits_valid', False):
        score += 15
        feedback_parts.append("Credits JSON file exists and is valid (+15)")
    elif result.get('credits_exists', False):
        score += 5
        feedback_parts.append("Credits file exists but contains invalid JSON (+5)")
    else:
        feedback_parts.append("Credits file missing (0/15)")

    # --- Criterion 4: Metadata Quality (15 pts) ---
    meta_score = 0
    if isinstance(credits_content, list) and len(credits_content) > 0:
        entries_valid = 0
        for entry in credits_content:
            # Check for required keys (case-insensitive keys for robustness)
            entry_lower = {k.lower(): v for k, v in entry.items()}
            has_title = bool(entry_lower.get('title'))
            has_call = bool(entry_lower.get('call_number')) or bool(entry_lower.get('call number'))
            has_url = bool(entry_lower.get('source_url')) or bool(entry_lower.get('url'))
            
            if has_title and has_call and has_url:
                entries_valid += 1
        
        # 5 points per valid entry, max 15
        meta_score = min(entries_valid, 3) * 5
        score += meta_score
        feedback_parts.append(f"Metadata valid for {entries_valid} entries (+{meta_score})")
    elif isinstance(credits_content, list) and len(credits_content) == 0:
        feedback_parts.append("Credits JSON is an empty list (0/15)")

    # --- Criterion 5: Research Evidence (15 pts) ---
    item_visits = result.get('item_visits', 0)
    loc_visits = result.get('loc_visits', 0)
    
    if item_visits >= 3:
        score += 15
        feedback_parts.append(f"Visited {item_visits} specific item pages (+15)")
    elif item_visits >= 1:
        score += 10
        feedback_parts.append(f"Visited {item_visits} item page(s) - need 3 (+10)")
    elif loc_visits > 0:
        score += 5
        feedback_parts.append("Visited LOC home/search but no item pages (+5)")
    else:
        feedback_parts.append("No history of visiting LOC (0/15)")

    # Final Result
    passed = score >= 70
    
    # Sanity check: Must have at least 2 high-res files to pass regardless of score
    if valid_files_count < 2:
        passed = False
        feedback_parts.append("FAIL: Fewer than 2 high-res images found")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }