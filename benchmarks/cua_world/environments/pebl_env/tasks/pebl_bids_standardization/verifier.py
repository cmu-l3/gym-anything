#!/usr/bin/env python3
"""
Verifier for PEBL BIDS Standardization task.

Scoring System (100 points total):
  - BIDS Root Exists (5 pts)
  - Dataset Description JSON (15 pts)
  - Participants TSV Valid (20 pts)
  - Subject IDs Formatted with 'sub-' (10 pts)
  - Behavioral Folders created (10 pts)
  - Files Renamed & Moved properly (30 pts)
  - Task Sidecars created (10 pts)

Pass Threshold: 75 points (Requires TSV validation and file mappings to be mostly correct)
"""

import json
import os
import tarfile
import tempfile
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pebl_bids_standardization(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available."}

    score = 0
    feedback = []
    
    # 1. Fetch metadata result
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_res:
        tmp_res_path = tmp_res.name
        
    try:
        copy_from_env('/tmp/task_result.json', tmp_res_path)
        with open(tmp_res_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}
    finally:
        if os.path.exists(tmp_res_path):
            os.unlink(tmp_res_path)

    if not result.get('bids_dir_exists') or not result.get('tarball_exists'):
        return {"passed": False, "score": 0, "feedback": "BIDS directory 'bids_dataset' was not created."}
    
    score += 5
    feedback.append("[+5] BIDS root directory exists.")

    expected_ids = result.get('ground_truth_ids', [])
    expected_subs = [f"sub-{i}" for i in expected_ids]
    
    # 2. Fetch and extract tarball
    with tempfile.NamedTemporaryFile(suffix='.tar.gz', delete=False) as tmp_tar:
        tmp_tar_path = tmp_tar.name
        
    extract_dir = tempfile.mkdtemp()
    try:
        copy_from_env('/tmp/bids_dataset.tar.gz', tmp_tar_path)
        with tarfile.open(tmp_tar_path, 'r:gz') as tar:
            tar.extractall(path=extract_dir)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to extract BIDS tarball: {e}"}
    finally:
        if os.path.exists(tmp_tar_path):
            os.unlink(tmp_tar_path)

    bids_root = os.path.join(extract_dir, 'bids_dataset')
    
    # Criterion 2: dataset_description.json (15 pts)
    desc_path = os.path.join(bids_root, 'dataset_description.json')
    if os.path.exists(desc_path):
        try:
            with open(desc_path, 'r', encoding='utf-8') as f:
                desc = json.load(f)
            if 'Name' in desc and 'BIDSVersion' in desc:
                score += 15
                feedback.append("[+15] dataset_description.json valid.")
            else:
                feedback.append("[0] dataset_description.json missing 'Name' or 'BIDSVersion'.")
        except json.JSONDecodeError:
            feedback.append("[0] dataset_description.json is invalid JSON.")
    else:
        feedback.append("[0] dataset_description.json missing.")

    # Criterion 3 & 4: participants.tsv (20 + 10 pts)
    tsv_path = os.path.join(bids_root, 'participants.tsv')
    tsv_valid = False
    ids_formatted = False
    if os.path.exists(tsv_path):
        try:
            with open(tsv_path, 'r', encoding='utf-8') as f:
                reader = csv.reader(f, delimiter='\t')
                headers = next(reader)
                if 'participant_id' in headers:
                    score += 20
                    tsv_valid = True
                    feedback.append("[+20] participants.tsv is valid tab-separated with 'participant_id'.")
                    
                    id_idx = headers.index('participant_id')
                    found_subs = [row[id_idx] for row in reader if len(row) > id_idx]
                    
                    if all(sub in found_subs for sub in expected_subs):
                        score += 10
                        ids_formatted = True
                        feedback.append("[+10] Subject IDs dynamically mapped and properly prefixed with 'sub-'.")
                    else:
                        feedback.append(f"[0] TSV IDs {found_subs} do not match expected BIDS sub- IDs {expected_subs}.")
                else:
                    feedback.append("[0] participants.tsv missing 'participant_id' header.")
        except Exception as e:
            feedback.append(f"[0] participants.tsv parsing error: {e}")
    else:
        feedback.append("[0] participants.tsv missing.")

    # Criterion 5 & 6: Behavioral Folders (10 pts) and File Renaming (30 pts)
    tasks = ['bart', 'flanker', 'simon', 'wcst']
    found_folders = 0
    correct_files = 0
    
    for sub in expected_subs:
        beh_dir = os.path.join(bids_root, sub, 'beh')
        if os.path.exists(beh_dir) and os.path.isdir(beh_dir):
            found_folders += 1
            
        for task in tasks:
            expected_filename = f"{sub}_task-{task}_beh.csv"
            fpath = os.path.join(bids_root, sub, 'beh', expected_filename)
            # Check existence and ensure it is not an empty touch file (anti-gaming)
            if os.path.exists(fpath) and os.path.getsize(fpath) > 20:
                correct_files += 1

    if found_folders == len(expected_subs):
        score += 10
        feedback.append("[+10] All subject beh/ folders created.")
    else:
        feedback.append(f"[0] Only {found_folders}/{len(expected_subs)} beh/ folders found.")

    file_pts = int((correct_files / 12) * 30)
    score += file_pts
    feedback.append(f"[+{file_pts}] {correct_files}/12 raw logs correctly renamed, mapped, and verified by size.")

    # Criterion 7: Task sidecars (10 pts)
    correct_sidecars = 0
    for task in tasks:
        sidecar_path = os.path.join(bids_root, f"task-{task}_beh.json")
        if os.path.exists(sidecar_path):
            try:
                with open(sidecar_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                if data.get('SoftwareName') == 'PEBL':
                    correct_sidecars += 1
            except:
                pass

    sidecar_pts = int((correct_sidecars / 4) * 10)
    score += sidecar_pts
    feedback.append(f"[+{sidecar_pts}] {correct_sidecars}/4 task JSON sidecars valid.")

    # Cleanup extraction
    try:
        import shutil
        shutil.rmtree(extract_dir)
    except:
        pass

    passed = score >= 75 and tsv_valid and correct_files >= 10
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }