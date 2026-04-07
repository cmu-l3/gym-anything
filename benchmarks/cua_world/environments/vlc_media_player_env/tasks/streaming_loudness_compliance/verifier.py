#!/usr/bin/env python3
"""
Verifier for streaming_loudness_compliance task.

Verification Strategy:
1. Copy the /tmp/export_metrics.json (programmatic FFmpeg LUFS/format measurements).
2. Copy the agent's /tmp/loudness_compliance_report.json.
3. Compare the LUFS of all 12 output files to the strict target constraints (±1.5 LUFS).
4. Verify correct codecs and sample rates for each platform.
5. Validate the agent's report against the real measured values (Anti-gaming / verification).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_streaming_loudness_compliance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    platforms = metadata.get('platforms', {})
    tolerance = metadata.get('tolerance_lufs', 1.5)
    
    score = 0
    max_score = 66
    feedback_parts = []
    
    # 1. Load exported metrics
    temp_metrics = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_time = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env("/tmp/export_metrics.json", temp_metrics.name)
        with open(temp_metrics.name, 'r') as f:
            metrics = json.load(f)
            
        copy_from_env("/tmp/loudness_compliance_report.json", temp_report.name)
        try:
            with open(temp_report.name, 'r') as f:
                agent_report = json.load(f)
        except json.JSONDecodeError:
            agent_report = {}

        try:
            copy_from_env("/tmp/task_start_time.txt", temp_time.name)
            with open(temp_time.name, 'r') as f:
                task_start = float(f.read().strip())
        except:
            task_start = 0.0

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve exported files: {e}"}
    finally:
        for tmp in [temp_metrics, temp_report, temp_time]:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # Helper function to process platform checks
    def evaluate_platform(plat_name, expected_lufs, expected_codec, expected_sr):
        nonlocal score
        plat_data = metrics.get('deliverables', {}).get(plat_name, {})
        valid_files = 0
        format_correct = True
        
        for track in ['track_01_overture', 'track_02_nocturne', 'track_03_pulse', 'track_04_finale']:
            file_data = plat_data.get(track)
            if not file_data or not file_data.get('exists'):
                feedback_parts.append(f"[{plat_name}] {track} missing.")
                format_correct = False
                continue
            
            # Anti-gaming: Ensure file was processed during task
            if file_data.get('mtime', 0) < task_start:
                feedback_parts.append(f"[{plat_name}] {track} was not processed during task.")
                format_correct = False
                continue

            lufs = file_data.get('lufs', -99.0)
            codec = file_data.get('codec', '')
            sr = file_data.get('sample_rate', 0)

            # Check LUFS
            if abs(lufs - expected_lufs) <= tolerance:
                score += 3
                valid_files += 1
            else:
                feedback_parts.append(f"[{plat_name}] {track} LUFS mismatch: {lufs:.1f} (Target: {expected_lufs})")

            # Check formats
            if codec != expected_codec or sr != expected_sr:
                format_correct = False

        if valid_files == 4:
            feedback_parts.append(f"[{plat_name}] All LUFS normalized correctly.")
        
        if format_correct and valid_files > 0:
            score += 4
            feedback_parts.append(f"[{plat_name}] Formats correct ({expected_codec}, {expected_sr}Hz).")
        elif valid_files > 0:
            feedback_parts.append(f"[{plat_name}] Format mismatch (expected {expected_codec}, {expected_sr}Hz).")

    # Evaluate Platforms
    evaluate_platform('spotify', -14.0, 'mp3', 44100)
    evaluate_platform('apple', -16.0, 'aac', 44100)
    evaluate_platform('youtube', -13.0, 'opus', 48000)

    # Evaluate Agent's JSON Report
    if agent_report and isinstance(agent_report.get('tracks'), list) and len(agent_report['tracks']) > 0:
        score += 4  # Report exists and is parseable
        feedback_parts.append("[Report] Valid JSON structure.")
        
        source_accuracy_points = 0
        achieved_accuracy_points = 0
        
        for track_rpt in agent_report.get('tracks', []):
            src_file = track_rpt.get('source_file', '')
            if not src_file:
                continue
                
            # Check source measurement accuracy (Proves agent analyzed before changing)
            reported_src_lufs = float(track_rpt.get('source_lufs', -99.0))
            actual_src_lufs = metrics.get('source_tracks', {}).get(src_file, {}).get('lufs', -99.0)
            
            if abs(reported_src_lufs - actual_src_lufs) <= 2.0:
                source_accuracy_points += 1.5

            # Check achieved measurement accuracy (Anti-fabrication)
            plats = track_rpt.get('platforms', {})
            track_base = src_file.replace('.wav', '')
            
            plat_maps = [('spotify', 'spotify'), ('apple_music', 'apple'), ('youtube_music', 'youtube')]
            for rpt_plat, sys_plat in plat_maps:
                if rpt_plat in plats:
                    reported_achieved = float(plats[rpt_plat].get('achieved_lufs', -99.0))
                    actual_achieved = metrics.get('deliverables', {}).get(sys_plat, {}).get(track_base, {}).get('lufs', -99.0)
                    # Must be within 1.0 LU of the actual measurement the verifier makes
                    if abs(reported_achieved - actual_achieved) <= 1.0 and actual_achieved != -99.0:
                        achieved_accuracy_points += 0.5  # 0.5 * 3 platforms = 1.5 per track

        score += source_accuracy_points
        score += achieved_accuracy_points
        
        if source_accuracy_points >= 5:
            feedback_parts.append("[Report] Source measurements highly accurate.")
        if achieved_accuracy_points >= 5:
            feedback_parts.append("[Report] Final achieved measurements highly accurate (cross-validated).")
    else:
        feedback_parts.append("[Report] Missing, invalid, or empty JSON compliance report.")

    # Directory layout structure check (implicit if files were found, but we reward it)
    if any(metrics.get('deliverables', {}).get(p, {}) for p in ['spotify', 'apple', 'youtube']):
        score += 2

    # Determine Pass / Fail
    score = min(max_score, score)
    passed = score >= 40  # Approx 60% requirement

    if passed:
        feedback_parts.insert(0, f"SUCCESS! Score: {score}/{max_score}.")
    else:
        feedback_parts.insert(0, f"FAILED. Score: {score}/{max_score}. Threshold is 40.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }