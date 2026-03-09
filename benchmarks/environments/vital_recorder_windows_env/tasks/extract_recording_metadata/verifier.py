#!/usr/bin/env python3
"""
Verifier for extract_recording_metadata task.

Evaluates the agent's generated metadata file against the ground truth.
Requires precise formatting for Duration and Track Counts, and intelligent matching for Track Names.
"""

import json
import os
import tempfile
import logging
import re
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_recording_metadata(traj, env_info, task_info):
    """
    Verify metadata extraction from Vital Recorder.
    
    Criteria:
    1. Output file exists and was created during task (Anti-gaming).
    2. Duration matches ground truth (Tolerance: +/- 1 minute).
    3. Track count matches ground truth.
    4. Track list contains correct names and types.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    result_path = "C:/workspace/task_result.json"
    output_path = "C:/Users/Docker/Documents/recording_metadata.txt"
    gt_path = "C:/workspace/ground_truth/metadata_gt.json"

    # Temp files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name

    try:
        # Copy files
        copy_from_env(result_path, temp_result)
        
        with open(temp_result, 'r') as f:
            task_result = json.load(f)

        if not task_result.get('output_exists'):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file recording_metadata.txt was not created."
            }

        if not task_result.get('file_created_during_task'):
             return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file timestamp is invalid (pre-dates task)."
            }

        # Copy content and ground truth
        copy_from_env(output_path, temp_output)
        copy_from_env(gt_path, temp_gt)

        with open(temp_output, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
        with open(temp_gt, 'r') as f:
            ground_truth = json.load(f)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving files: {e}"}
    finally:
        for f in [temp_result, temp_output, temp_gt]:
            if os.path.exists(f):
                os.unlink(f)

    # --- Scoring Logic ---
    score = 0
    feedback = []
    
    # 1. Duration Check (20 pts)
    # Expected format: Duration=HH:MM:SS
    dur_match = re.search(r"Duration\s*=\s*(\d+):(\d+):(\d+)", content, re.IGNORECASE)
    if dur_match:
        h, m, s = map(int, dur_match.groups())
        agent_seconds = h * 3600 + m * 60 + s
        gt_seconds = ground_truth.get('duration_sec', 0)
        
        diff = abs(agent_seconds - gt_seconds)
        if diff < 60: # 1 minute tolerance
            score += 20
            feedback.append("✅ Duration correct")
        elif diff < 300: # 5 minute tolerance
            score += 10
            feedback.append(f"⚠️ Duration slightly off (Diff: {diff}s)")
        else:
            feedback.append(f"❌ Duration incorrect (Expected ~{ground_truth.get('duration_str')})")
    else:
        feedback.append("❌ Duration format not found")

    # 2. Track Count Check (20 pts)
    count_match = re.search(r"TrackCount\s*=\s*(\d+)", content, re.IGNORECASE)
    gt_count = ground_truth.get('track_count', 0)
    
    if count_match:
        agent_count = int(count_match.group(1))
        if agent_count == gt_count:
            score += 20
            feedback.append(f"✅ Track count correct ({agent_count})")
        elif abs(agent_count - gt_count) <= 2:
            score += 10
            feedback.append(f"⚠️ Track count close ({agent_count} vs {gt_count})")
        else:
            feedback.append(f"❌ Track count incorrect (Got {agent_count}, Expected {gt_count})")
    else:
        feedback.append("❌ TrackCount format not found")

    # 3. Track Entries Check (60 pts)
    # Parse [Tracks] section
    agent_tracks = []
    in_tracks = False
    for line in content.splitlines():
        line = line.strip()
        if line.lower() == "[tracks]":
            in_tracks = True
            continue
        if in_tracks and line.startswith("["):
            break
        if in_tracks and "," in line:
            parts = line.split(",", 1)
            name = parts[0].strip()
            type_ = parts[1].strip().lower()
            agent_tracks.append((name, type_))

    if not agent_tracks:
        feedback.append("❌ No track entries found in [Tracks] section")
    else:
        # Match against GT
        matched_tracks = 0
        correct_types = 0
        gt_tracks = ground_truth.get('tracks', [])
        
        for ag_name, ag_type in agent_tracks:
            # Fuzzy name match
            best_match = None
            for gt_trk in gt_tracks:
                # Check if partial match (VitalDB names are often "Device/Param")
                gt_name = gt_trk['name']
                if ag_name in gt_name or gt_name in ag_name:
                    best_match = gt_trk
                    break
            
            if best_match:
                matched_tracks += 1
                if ag_type == best_match['type']:
                    correct_types += 1
        
        # Calculate ratio
        total_gt = len(gt_tracks) if len(gt_tracks) > 0 else 1
        coverage = matched_tracks / total_gt
        type_accuracy = correct_types / matched_tracks if matched_tracks > 0 else 0
        
        # Score based on coverage
        if coverage >= 0.8:
            score += 30
            feedback.append(f"✅ Track listing coverage good ({matched_tracks}/{total_gt})")
        elif coverage >= 0.5:
            score += 15
            feedback.append(f"⚠️ Track listing coverage partial ({matched_tracks}/{total_gt})")
        else:
            feedback.append(f"❌ Track listing coverage poor ({matched_tracks}/{total_gt})")
            
        # Score based on type accuracy
        if type_accuracy >= 0.8:
            score += 30
            feedback.append(f"✅ Track type classification accurate")
        elif type_accuracy >= 0.5:
            score += 15
            feedback.append(f"⚠️ Track type classification mixed")
        else:
            feedback.append(f"❌ Track type classification poor")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }