#!/usr/bin/env python3
import json
import os
import tempfile
import math
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_shortest_track_duration(traj, env_info, task_info):
    """
    Verifies that the agent correctly identified the shortest track duration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if report file exists (10 pts)
    if not result.get('report_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file not found at C:\\Users\\Docker\\Documents\\shortest_track_report.txt"
        }
    score += 10
    feedback_parts.append("Report file exists")

    # 2. Check if file created during task (10 pts)
    if result.get('file_created_during_task', False):
        score += 10
    else:
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this session")

    # 3. Parse Content
    content = result.get('report_content', '').strip()
    if not content:
        return {"passed": False, "score": score, "feedback": "Report file is empty"}

    # Parse fields
    # Format:
    # Case: 6
    # Shortest Track: [NAME]
    # Duration (minutes): [NUM]
    # Total Case Duration (minutes): [NUM]
    # Coverage Percentage: [NUM]%
    
    track_match = re.search(r"Shortest Track:\s*(.+)", content, re.IGNORECASE)
    dur_match = re.search(r"Duration \(minutes\):\s*([\d\.]+)", content, re.IGNORECASE)
    total_match = re.search(r"Total Case Duration \(minutes\):\s*([\d\.]+)", content, re.IGNORECASE)
    cov_match = re.search(r"Coverage Percentage:\s*([\d\.]+)", content, re.IGNORECASE)
    
    parsed_fields = {
        "track": track_match.group(1).strip() if track_match else None,
        "duration": float(dur_match.group(1)) if dur_match else None,
        "total": float(total_match.group(1)) if total_match else None,
        "coverage": float(cov_match.group(1)) if cov_match else None
    }
    
    # Check if all fields present (10 pts)
    if all(parsed_fields.values()):
        score += 10
        feedback_parts.append("All report fields present")
    else:
        missing = [k for k, v in parsed_fields.items() if v is None]
        feedback_parts.append(f"Missing fields: {', '.join(missing)}")

    # 4. Compare with Ground Truth
    gt_str = result.get('ground_truth', '{}')
    try:
        gt = json.loads(gt_str)
    except:
        gt = {}

    if gt and gt.get('shortest_track') != 'manual_verification_required':
        # Valid ground truth available
        
        # Check Track Name (30 pts)
        # Allow partial match (e.g. "BIS" matching "BIS/BIS")
        gt_track = gt.get('shortest_track', '').lower()
        agent_track = (parsed_fields['track'] or '').lower()
        
        # Check if agent track matches ground truth OR is in the bottom 3 shortest tracks
        # This handles ambiguity where tracks have very similar durations
        all_tracks = gt.get('all_tracks', {})
        sorted_tracks = sorted(all_tracks.items(), key=lambda x: x[1])
        valid_shortest_tracks = [t[0].lower() for t in sorted_tracks[:3]]
        
        track_correct = False
        if agent_track and (agent_track in gt_track or gt_track in agent_track):
            track_correct = True
        elif agent_track:
             for valid_t in valid_shortest_tracks:
                 if agent_track in valid_t or valid_t in agent_track:
                     track_correct = True
                     break
        
        if track_correct:
            score += 30
            feedback_parts.append(f"Correct shortest track identified: {parsed_fields['track']}")
        else:
            feedback_parts.append(f"Incorrect shortest track. Expected: {gt.get('shortest_track')}, Got: {parsed_fields['track']}")

        # Check Durations (20 pts)
        gt_dur = gt.get('duration_minutes', 0)
        agent_dur = parsed_fields['duration'] or 0
        if abs(agent_dur - gt_dur) <= 5: # 5 min tolerance
            score += 20
        else:
            feedback_parts.append(f"Duration mismatch (Expected ~{gt_dur}, Got {agent_dur})")

        # Check Logic (Coverage %) (20 pts)
        # Even if values are wrong, the math should be consistent
        agent_total = parsed_fields['total'] or 1
        agent_cov = parsed_fields['coverage'] or 0
        calc_cov = (agent_dur / agent_total * 100) if agent_total > 0 else 0
        
        if abs(calc_cov - agent_cov) <= 2:
            score += 20
        else:
            feedback_parts.append("Coverage percentage calculation inconsistent")

    else:
        # Fallback if no ground truth (e.g. vitaldb lib missing in env)
        # Check internal consistency and plausibility
        if parsed_fields['track']:
            score += 30
            feedback_parts.append("Track identified (GT unavailable)")
        if parsed_fields['duration'] is not None and 0 < parsed_fields['duration'] < 1000:
             score += 20
        if parsed_fields['total'] is not None and parsed_fields['duration'] is not None:
             # Check math
             calc = (parsed_fields['duration'] / parsed_fields['total'] * 100)
             if parsed_fields['coverage'] is not None and abs(calc - parsed_fields['coverage']) <= 2:
                 score += 20
             else:
                 feedback_parts.append("Math check failed")
    
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }