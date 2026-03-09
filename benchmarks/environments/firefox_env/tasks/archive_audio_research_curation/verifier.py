#!/usr/bin/env python3
"""
Verifier for archive_audio_research_curation@1

This script verifies:
1. Directory structure (~/Documents/FDR_Audio/)
2. File presence (At least 3 MP3s, >500KB each)
3. Manifest validity (JSON structure, keys)
4. History evidence (Visits to archive.org)

Input: /tmp/task_result.json (exported by export_result.sh)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_archive_audio_curation(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task result file"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    folder_exists = result.get('folder_exists', False)
    mp3_files = result.get('mp3_files', [])
    manifest_exists = result.get('manifest_exists', False)
    manifest_content = result.get('manifest_content', None)
    archive_visits = result.get('archive_visits', 0)
    task_start = result.get('task_start_time', 0)

    score = 0
    feedback = []

    # 3. Scoring Logic
    
    # Criterion 1: Directory Creation (10 pts)
    if folder_exists:
        score += 10
        feedback.append("Folder ~/Documents/FDR_Audio created (+10).")
    else:
        feedback.append("Folder ~/Documents/FDR_Audio NOT found.")
        # Critical fail if folder missing? No, might have saved elsewhere, but strictly spec says Documents.
        # We will continue scoring but hard to pass without files.

    # Criterion 2: Audio Files (30 pts)
    # Check valid MP3s (size > 500KB to avoid empty files/placeholders)
    valid_mp3s = [f for f in mp3_files if f.get('size', 0) > 500000]
    unique_mp3_names = set(f['name'] for f in valid_mp3s)
    
    mp3_count = len(unique_mp3_names)
    
    if mp3_count >= 3:
        score += 30
        feedback.append(f"Found {mp3_count} valid MP3 files (+30).")
    elif mp3_count > 0:
        partial = mp3_count * 10
        score += partial
        feedback.append(f"Found {mp3_count} valid MP3 files (+{partial}). Needed 3.")
    else:
        feedback.append("No valid MP3 files found (must be >500KB).")

    # Criterion 3: File Renaming (15 pts)
    # Check if names look curated (not just "78_fireside-chat..."). 
    # Spec requested consistent format like "fireside_chat_<topic>.mp3"
    renamed_count = 0
    for f in valid_mp3s:
        name = f['name']
        # Loose check: starts with 'fireside' or contains '_' and doesn't look like a raw id
        if "fireside" in name.lower() or ("_" in name and not name.startswith("78_")):
            renamed_count += 1
            
    if renamed_count >= 3:
        score += 15
        feedback.append("Files appear to be renamed consistently (+15).")
    elif renamed_count > 0:
        score += 5
        feedback.append("Some files renamed, but not all (+5).")
    else:
        feedback.append("Files do not appear to be renamed to a descriptive format.")

    # Criterion 4: Manifest Existence (15 pts)
    if manifest_exists and manifest_content != "INVALID_JSON" and isinstance(manifest_content, list):
        score += 15
        feedback.append("Manifest JSON exists and is a list (+15).")
        
        # Criterion 5: Manifest Content (20 pts)
        # Check keys
        required_keys = ["filename", "original_title", "date", "source_url"]
        entries_valid = 0
        for entry in manifest_content:
            if all(k in entry for k in required_keys):
                # Verify filename matches one of the downloaded files
                if any(entry['filename'] == f['name'] for f in valid_mp3s):
                    entries_valid += 1
        
        if entries_valid >= 3:
            score += 20
            feedback.append("Manifest contains metadata for all 3 files (+20).")
        elif entries_valid > 0:
            score += 10
            feedback.append(f"Manifest contains valid metadata for {entries_valid} files (+10).")
        else:
            feedback.append("Manifest entries do not match downloaded files or missing keys.")
            
    elif manifest_content == "INVALID_JSON":
        feedback.append("Manifest file exists but is not valid JSON.")
    else:
        feedback.append("Manifest file missing or incorrect structure (must be a list).")

    # Criterion 6: Source Verification (10 pts)
    if archive_visits > 0:
        score += 10
        feedback.append("Verified visits to archive.org (+10).")
    else:
        feedback.append("No history of visiting archive.org found.")

    # Final Result
    passed = score >= 70 and mp3_count >= 2 # Need at least 2 files to pass practically
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }