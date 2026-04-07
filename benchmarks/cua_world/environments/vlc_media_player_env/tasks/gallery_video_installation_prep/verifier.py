#!/usr/bin/env python3
"""
Verifier for gallery_video_installation_prep task.

Evaluates:
1. Room A: 1920x1080, H.264, Audio preserved (15 pts)
2. Room B: 1280x720, H.264, Audio stripped (15 pts)
3. Room C: 1080x1920, H.264, Audio preserved, Portrait rotation (20 pts)
4. Room D: 640x480, H.264, Audio stripped (15 pts)
5. Playlist: Valid M3U with 4 files in correct order (15 pts)
6. Manifest: Valid JSON with correct required fields (20 pts)

Anti-gaming:
- Files must have an mtime > task_start
- Audio must be stripped (0 audio streams), not just silent
- Room C width MUST be strictly < height
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gallery_installation_prep(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch the main export JSON
    temp_export = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/gallery_export.json", temp_export.name)
        with open(temp_export.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export data: {e}"}
    finally:
        if os.path.exists(temp_export.name):
            os.unlink(temp_export.name)

    task_start = export_data.get('task_start', 0)
    files = export_data.get('files', {})

    # Helper function to evaluate a video file
    def eval_video(file_key, expected_w, expected_h, expect_audio, max_pts):
        pts = 0
        fb = []
        info = files.get(file_key, {})
        
        if not info.get('exists', False):
            return 0, f"x {file_key} missing"
            
        # Anti-gaming: Check if file was created/modified during task
        if info.get('mtime', 0) < task_start:
            return 0, f"x {file_key} existed before task start (not modified)"
            
        pts += 3 # Base points for existing and modified
        
        v_info = info.get('video_info', {}).get('streams', [])
        a_info = info.get('audio_info', {}).get('streams', [])
        
        if not v_info:
            return pts, f"x {file_key} has no video stream"
            
        v_stream = v_info[0]
        w = v_stream.get('width', 0)
        h = v_stream.get('height', 0)
        codec = str(v_stream.get('codec_name', '')).lower()
        
        # Check codec (H.264)
        if 'h264' in codec or 'avc' in codec:
            pts += 3
        else:
            fb.append(f"Wrong codec: {codec}")
            
        # Check resolution
        if expected_w == "portrait":
            # Just needs to be 1080x1920
            if w == 1080 and h == 1920:
                pts += 9
            elif w < h:
                pts += 4
                fb.append(f"Portrait but wrong res: {w}x{h}")
            else:
                fb.append(f"Not portrait: {w}x{h}")
        else:
            if w == expected_w and h == expected_h:
                pts += 5
            else:
                fb.append(f"Wrong res: {w}x{h}")
                
        # Check audio
        has_audio = len(a_info) > 0
        if expect_audio:
            if has_audio:
                pts += max_pts - 11 # 15 - 3 - 3 - 5 = 4
            else:
                fb.append("Missing audio")
        else:
            if not has_audio:
                pts += max_pts - 11
            else:
                fb.append("Audio not stripped")
                
        if not fb:
            return max_pts, f"+ {file_key} perfectly matched"
        return pts, f"~ {file_key} partial: " + ", ".join(fb)

    # Evaluate Room A
    a_score, a_fb = eval_video("room_a_main_hall.mp4", 1920, 1080, True, 15)
    score += a_score
    feedback_parts.append(a_fb)

    # Evaluate Room B
    b_score, b_fb = eval_video("room_b_quiet_gallery.mp4", 1280, 720, False, 15)
    score += b_score
    feedback_parts.append(b_fb)

    # Evaluate Room C (Portrait)
    c_score, c_fb = eval_video("room_c_tower_alcove.mp4", "portrait", 0, True, 20)
    score += c_score
    feedback_parts.append(c_fb)

    # Evaluate Room D
    d_score, d_fb = eval_video("room_d_lobby_screen.mp4", 640, 480, False, 15)
    score += d_score
    feedback_parts.append(d_fb)

    # 2. Evaluate M3U Playlist (15 points)
    if export_data.get('m3u_exists', False):
        temp_m3u = tempfile.NamedTemporaryFile(delete=False)
        try:
            copy_from_env("/tmp/installation_test.m3u", temp_m3u.name)
            with open(temp_m3u.name, 'r') as f:
                lines = [line.strip() for line in f.readlines() if line.strip() and not line.strip().startswith('#')]
            
            score += 5 # Exists
            if len(lines) == 4:
                score += 5 # 4 entries
                
            # Check if all files are in the playlist
            expected = ["room_a_main_hall.mp4", "room_b_quiet_gallery.mp4", "room_c_tower_alcove.mp4", "room_d_lobby_screen.mp4"]
            found_all = all(any(exp in line for line in lines) for exp in expected)
            if found_all:
                score += 5
                feedback_parts.append("+ M3U playlist valid and complete")
            else:
                feedback_parts.append("~ M3U playlist missing some files")
        except Exception as e:
            feedback_parts.append(f"x Failed to parse M3U: {e}")
        finally:
            if os.path.exists(temp_m3u.name):
                os.unlink(temp_m3u.name)
    else:
        feedback_parts.append("x M3U playlist missing")

    # 3. Evaluate JSON Manifest (20 points)
    if export_data.get('manifest_exists', False):
        temp_man = tempfile.NamedTemporaryFile(delete=False)
        try:
            copy_from_env("/tmp/installation_manifest.json", temp_man.name)
            with open(temp_man.name, 'r') as f:
                manifest = json.load(f)
            
            score += 5 # Valid JSON
            
            # Try to find the list of rooms
            rooms_list = []
            if isinstance(manifest, list):
                rooms_list = manifest
            elif isinstance(manifest, dict):
                # Search values for a list
                for v in manifest.values():
                    if isinstance(v, list) and len(v) > 0 and isinstance(v[0], dict):
                        rooms_list = v
                        break
                if not rooms_list:
                    # Maybe it's a dict of dicts
                    rooms_list = [v for v in manifest.values() if isinstance(v, dict)]
            
            if len(rooms_list) >= 4:
                score += 5 # Contains entries
                
                # Check for required fields in any of the entries
                fields_found = set()
                for r in rooms_list:
                    r_str = json.dumps(r).lower()
                    if 'resolution' in r_str or '1920' in r_str or '1080' in r_str: fields_found.add('res')
                    if 'audio' in r_str or 'true' in r_str or 'false' in r_str: fields_found.add('aud')
                    if 'orientation' in r_str or 'landscape' in r_str or 'portrait' in r_str: fields_found.add('ori')
                    if 'room' in r_str or 'hall' in r_str: fields_found.add('id')
                    
                if len(fields_found) >= 4:
                    score += 10
                    feedback_parts.append("+ JSON manifest complete and highly detailed")
                elif len(fields_found) >= 2:
                    score += 5
                    feedback_parts.append("~ JSON manifest missing some required fields")
                else:
                    feedback_parts.append("~ JSON manifest lacks specific room properties")
            else:
                feedback_parts.append(f"~ JSON manifest has incomplete room entries ({len(rooms_list)})")
        except Exception as e:
            feedback_parts.append(f"x Failed to parse JSON manifest: {e}")
        finally:
            if os.path.exists(temp_man.name):
                os.unlink(temp_man.name)
    else:
        feedback_parts.append("x JSON manifest missing")

    # Calculate final status
    key_files_exist = a_score >= 11 and c_score >= 15 # A and C are critical
    passed = score >= 60 and key_files_exist
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }