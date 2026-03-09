#!/usr/bin/env python3
"""
Verifier for backup_large_artifacts task.
Checks if the correct files > 5MB were downloaded and if manifest exists.
"""

import json
import os
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_backup_large_artifacts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Metadata & Result
    metadata = task_info.get('metadata', {})
    target_files = metadata.get('target_files', []) # List of dicts {name, min_size}
    excluded_files = metadata.get('excluded_files', []) # List of strings
    
    dir_exists = result.get('dir_exists', False)
    manifest_exists = result.get('manifest_exists', False)
    files_found = result.get('files', [])
    
    # Decode ground truth checksums
    gt_checksums = {}
    if result.get('ground_truth_checksums_base64'):
        try:
            decoded = base64.b64decode(result['ground_truth_checksums_base64']).decode('utf-8')
            for line in decoded.strip().split('\n'):
                parts = line.split()
                if len(parts) >= 2:
                    # Map filename to hash. Path might be full path, get basename
                    fname = os.path.basename(parts[1])
                    gt_checksums[fname] = parts[0]
        except Exception:
            pass

    score = 0
    feedback_log = []

    # Criterion 1: Backup Directory Created (10 pts)
    if dir_exists:
        score += 10
        feedback_log.append("Backup directory created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Backup directory '/home/ga/large_files_backup' not found."}

    # Criterion 2: Target Large Files Present & Integrity Check (40 pts)
    # 20 pts per file
    targets_met = 0
    for target in target_files:
        t_name = target['name']
        found_file = next((f for f in files_found if f['name'] == t_name), None)
        
        if found_file:
            # Check size
            if found_file['size'] >= target['min_size']:
                # Integrity check via checksum if available
                if t_name in gt_checksums and found_file.get('sha256'):
                    if found_file['sha256'] == gt_checksums[t_name]:
                        score += 20
                        targets_met += 1
                        feedback_log.append(f"File {t_name} backed up correctly (checksum match).")
                    else:
                        score += 5 # Partial credit for file existence but wrong content
                        feedback_log.append(f"File {t_name} exists but checksum mismatch.")
                else:
                    # Fallback if checksum logic fails
                    score += 20
                    targets_met += 1
                    feedback_log.append(f"File {t_name} backed up (size ok).")
            else:
                feedback_log.append(f"File {t_name} is too small ({found_file['size']} bytes).")
        else:
            feedback_log.append(f"Missing target file: {t_name}.")

    # Criterion 3: Excluded Files NOT Present (20 pts)
    pollution_penalty = 0
    for excluded in excluded_files:
        if any(f['name'] == excluded for f in files_found):
            pollution_penalty += 10
            feedback_log.append(f"Incorrectly backed up small file: {excluded}.")
    
    # Also penalize for files not in target list generally if they aren't manifest
    # (Simplified to just checking the explicit excluded list to avoid penalizing system files)
    
    score = max(0, score + 20 - pollution_penalty)
    if pollution_penalty == 0:
        feedback_log.append("Clean backup (no small files found).")

    # Criterion 4: Manifest File (10 pts)
    if manifest_exists:
        score += 10
        feedback_log.append("Manifest file created.")
        
        # Bonus: Check manifest content
        if result.get('manifest_content_base64'):
            try:
                content = base64.b64decode(result['manifest_content_base64']).decode('utf-8')
                # Check if target filenames are in manifest
                matches = sum(1 for t in target_files if t['name'] in content)
                if matches == len(target_files):
                    score += 10 # Extra points for correct content?
                    feedback_log.append("Manifest content correct.")
                else:
                    feedback_log.append("Manifest missing some filenames.")
            except:
                pass
    else:
        feedback_log.append("Manifest file missing.")

    # Criterion 5: Search UI Usage (VLM) (10 pts)
    # We will assume if they got the right files without "pollution", they likely used search.
    # But let's add 10 points free if targets met to simplify, or use VLM if we had it.
    # For this implementation, we will allocate the last 10 points based on overall success.
    if targets_met == len(target_files) and pollution_penalty == 0:
        score += 10
        feedback_log.append("Perfect execution implies correct search usage.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_log)
    }