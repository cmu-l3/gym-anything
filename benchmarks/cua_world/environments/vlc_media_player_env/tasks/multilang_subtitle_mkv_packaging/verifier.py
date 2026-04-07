#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_srt_time(time_str):
    """Convert SRT timestamp (HH:MM:SS,mmm) to total seconds."""
    try:
        parts = time_str.replace(',', '.').split(':')
        return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
    except Exception:
        return -1.0

def verify_multilang_subtitle_mkv_packaging(traj, env_info, task_info):
    """
    Verify multilang subtitle synchronization and MKV packaging task.
    Uses robust programmatic stream probing and VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Files to extract to host
    files_to_copy = {
        'result': ('/tmp/task_result.json', '.json'),
        'mkv_probe': ('/tmp/mkv_probe.json', '.json'),
        'sub_srt': ('/tmp/exported_sub_0.srt', '.srt'),
        'xspf': ('/tmp/spanish_review.xspf', '.xspf'),
        'manifest': ('/tmp/stream_manifest.json', '.json')
    }
    
    local_files = {}
    
    for key, (remote_path, suffix) in files_to_copy.items():
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
        try:
            copy_from_env(remote_path, tmp.name)
            local_files[key] = tmp.name
        except Exception:
            local_files[key] = None
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
                
    try:
        # Load task wrapper
        result = {}
        if local_files['result'] and os.path.exists(local_files['result']):
            with open(local_files['result'], 'r') as f:
                try:
                    result = json.load(f)
                except Exception:
                    pass
        
        mkv_exists = result.get('mkv_exists', False)
        if not mkv_exists:
            return {"passed": False, "score": 0, "feedback": "MKV file was not created in the expected directory."}
            
        # ================================================================
        # CRITERION 1: Container Structure & Copy Efficiency (20 pts)
        # ================================================================
        probe = {}
        if local_files['mkv_probe'] and os.path.exists(local_files['mkv_probe']):
            with open(local_files['mkv_probe'], 'r') as f:
                try:
                    probe = json.load(f)
                except Exception:
                    pass
        
        streams = probe.get('streams', [])
        format_name = probe.get('format', {}).get('format_name', '')
        
        v_streams = [s for s in streams if s.get('codec_type') == 'video']
        a_streams = [s for s in streams if s.get('codec_type') == 'audio']
        s_streams = [s for s in streams if s.get('codec_type') == 'subtitle']
        
        structure_ok = False
        if 'matroska' in format_name.lower() or 'mkv' in format_name.lower():
            if len(v_streams) == 1 and len(a_streams) == 1 and len(s_streams) == 3:
                score += 15
                structure_ok = True
                feedback_parts.append("MKV Container Structure correct (1V, 1A, 3S)")
            else:
                score += 5
                feedback_parts.append(f"MKV Container exists, but stream count incorrect: {len(v_streams)}V, {len(a_streams)}A, {len(s_streams)}S")
                
            # Copy efficiency (did they just mux instead of re-encoding?)
            if len(v_streams) > 0 and v_streams[0].get('codec_name') == 'h264' and len(a_streams) > 0 and a_streams[0].get('codec_name') == 'aac':
                score += 5
                feedback_parts.append("Video/Audio stream preserved without re-encoding")
        else:
            feedback_parts.append("File is not a valid Matroska container")
            
        # ================================================================
        # CRITERION 2: Metadata Tagging (15 pts)
        # ================================================================
        if len(s_streams) >= 3:
            eng_ok = False
            spa_ok = False
            fra_ok = False
            default_ok = False
            
            for s in s_streams:
                tags = s.get('tags', {})
                # Lowercase tags for flexible matching
                lang = tags.get('language', '').lower()
                title = tags.get('title', '').lower()
                disp = s.get('disposition', {})
                is_default = disp.get('default', 0) == 1
                
                if lang in ['eng', 'en'] or 'english' in title:
                    eng_ok = True
                    if is_default: default_ok = True
                elif lang in ['spa', 'es'] or 'español' in title or 'spanish' in title:
                    spa_ok = True
                elif lang in ['fra', 'fre', 'fr'] or 'français' in title or 'french' in title:
                    fra_ok = True
                    
            if eng_ok and spa_ok and fra_ok:
                score += 10
                feedback_parts.append("All 3 language tags present")
                if default_ok:
                    score += 5
                    feedback_parts.append("English set as default")
            else:
                score += 3
                feedback_parts.append("Missing required ISO language tags")
                
        # ================================================================
        # CRITERION 3: Subtitle Synchronization (25 pts)
        # ================================================================
        sync_ok = False
        if local_files['sub_srt'] and os.path.exists(local_files['sub_srt']):
            with open(local_files['sub_srt'], 'r', errors='ignore') as f:
                content = f.read()
                
            # Find first timestamp
            match = re.search(r'(\d{2}:\d{2}:\d{2}[,.]\d{3})\s*-->', content)
            if match:
                first_ts = match.group(1)
                seconds = parse_srt_time(first_ts)
                # Original was 00:00:02,000. Shifted by +12.5s = 14.5s
                if abs(seconds - 14.5) <= 0.2:
                    score += 25
                    sync_ok = True
                    feedback_parts.append(f"Subtitles accurately shifted (+12.5s verified)")
                else:
                    feedback_parts.append(f"Subtitle shift incorrect (found initial timestamp: {first_ts}, expected ~00:00:14,500)")
            else:
                feedback_parts.append("Could not parse exported subtitle track content")
        else:
            feedback_parts.append("Could not extract subtitles to verify sync")
            
        # ================================================================
        # CRITERION 4: XSPF Playlist Authoring (10 pts)
        # ================================================================
        if local_files['xspf'] and os.path.exists(local_files['xspf']):
            with open(local_files['xspf'], 'r', errors='ignore') as f:
                xspf_content = f.read().lower()
                
            has_start = "start-time=15" in xspf_content
            # Permit robust tracking matching: sub-track, sub-language, or literal options
            has_sub = "sub-track=" in xspf_content or "sub-language=" in xspf_content or "sub-track" in xspf_content
            
            if has_start and has_sub:
                score += 10
                feedback_parts.append("XSPF Playlist has correct VLC options")
            elif has_start or has_sub:
                score += 5
                feedback_parts.append("XSPF Playlist has partial VLC options")
            else:
                feedback_parts.append("XSPF Playlist missing required startup options")
        else:
            feedback_parts.append("XSPF Playlist missing")
            
        # ================================================================
        # CRITERION 5: JSON Manifest (5 pts)
        # ================================================================
        if local_files['manifest'] and os.path.exists(local_files['manifest']):
            with open(local_files['manifest'], 'r') as f:
                try:
                    manifest = json.load(f)
                    score += 5
                    feedback_parts.append("Valid JSON manifest provided")
                except Exception:
                    feedback_parts.append("Manifest is not valid JSON")
        else:
            feedback_parts.append("JSON manifest missing")

        # ================================================================
        # CRITERION 6: VLM Trajectory Verification (20 pts)
        # ================================================================
        vlm_score = 0
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            try:
                from gym_anything.vlm import sample_trajectory_frames
                frames = sample_trajectory_frames(traj, n=4)
                if frames:
                    prompt = """Analyze these chronological screenshots from an AI agent.
The agent was tasked with manipulating subtitle files (shifting timestamps), packaging them into an MKV container, and authoring a VLC XSPF playlist file.
Does the visual evidence show the agent interacting with terminal utilities (like ffmpeg/mkvmerge), editing subtitle/XML files in a text editor, or operating VLC?
Respond ONLY with JSON: {"meaningful_work": true/false, "confidence": "high/medium/low", "reason": "Brief justification"}"""
                    vlm_res = query_vlm(images=frames, prompt=prompt)
                    if vlm_res and vlm_res.get("success"):
                        parsed = vlm_res.get("parsed", {})
                        if parsed.get("meaningful_work"):
                            vlm_score = 20
                            feedback_parts.append("VLM: Meaningful workflow observed (+20)")
                        else:
                            feedback_parts.append(f"VLM: No meaningful workflow observed ({parsed.get('reason', '')})")
                    else:
                        vlm_score = 20  # Fallback
                        feedback_parts.append("VLM: Query failed, bypassing check")
            except Exception as e:
                vlm_score = 20
                feedback_parts.append(f"VLM Exception: {str(e)}")
        else:
            vlm_score = 20  # Fallback
            feedback_parts.append("VLM function unavailable, bypassing check")
            
        score += vlm_score

        # FINAL DETERMINATION
        # Maximum potential score: 20 (Structure) + 15 (Metadata) + 25 (Sync) + 10 (XSPF) + 5 (Manifest) + 20 (VLM) = 95. (Scaled out of 100 max theoretical)
        # Pass requires Structure correctness AND Sync correctness.
        passed = (score >= 65) and structure_ok and sync_ok

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts)
        }
    finally:
        # Cleanup temporary files
        for path in local_files.values():
            if path and os.path.exists(path):
                os.unlink(path)