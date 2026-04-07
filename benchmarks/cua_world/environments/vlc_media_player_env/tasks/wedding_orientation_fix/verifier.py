#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from utils.vlc_verification_utils import get_video_info


def _get_rotation_metadata(filepath):
    """Check if the video has 'rotate' stream tags or 'displaymatrix' side data."""
    try:
        cmd = [
            'ffprobe', '-v', 'error',
            '-select_streams', 'v:0',
            '-show_entries', 'stream_tags=rotate',
            '-show_entries', 'side_data=rotation',
            '-of', 'json', filepath
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            streams = data.get('streams', [])
            if streams:
                # Check tags
                tags = streams[0].get('tags', {})
                if 'rotate' in tags:
                    return True
                # Check side data
                side_data_list = streams[0].get('side_data_list', [])
                for sd in side_data_list:
                    if 'rotation' in sd:
                        return True
    except Exception as e:
        logger.warning(f"Error checking rotation metadata: {e}")
    return False


def verify_wedding_orientation_fix(traj, env_info, task_info):
    """
    Verify wedding_orientation_fix task.

    Criteria (100 points total, pass threshold = 55):
    - 6 Corrected Clips (48 points total, 8 points each):
      - Exists & Playable: 2 pts
      - Resolution exactly 1280x720: 3 pts
      - No rotation metadata: 1 pt
      - Duration preserved (~10s ±1.5s): 2 pts
    - Highlight Reel (26 points):
      - Exists & valid H.264 MP4: 4 pts
      - Resolution 1280x720: 6 pts
      - Duration approx sum (~60s ±4s): 8 pts
      - Contains audio track: 4 pts
      - Created after task start: 4 pts
    - Shot Correction Log (26 points):
      - File exists: 4 pts
      - Valid JSON: 6 pts
      - Contains 6 entries: 6 pts
      - Entries have required fields: 10 pts
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0.0
    temp_dirs = []

    expected_clips = [
        'clip_ceremony_01.mp4',
        'clip_vows_02.mp4',
        'clip_dance_03.mp4',
        'clip_toast_04.mp4',
        'clip_cake_05.mp4',
        'clip_exit_06.mp4'
    ]

    try:
        # 1. Evaluate Corrected Clips (48 pts)
        clips_dir = tempfile.mkdtemp(prefix='vlc_verify_clips_')
        temp_dirs.append(clips_dir)
        
        valid_clip_count = 0
        total_clip_duration = 0.0

        for clip_name in expected_clips:
            local_path = os.path.join(clips_dir, clip_name)
            try:
                copy_from_env(f'/tmp/wedding_corrected/{clip_name}', local_path)
            except Exception:
                feedback.append(f"x {clip_name}: Not found in corrected directory")
                continue

            if not os.path.exists(local_path) or os.path.getsize(local_path) < 1000:
                feedback.append(f"x {clip_name}: Missing or empty")
                continue

            info = get_video_info(local_path)
            if 'error' in info:
                feedback.append(f"x {clip_name}: Invalid media file")
                continue

            score += 2.0  # Exists and playable
            valid_clip_count += 1
            clip_fb = [f"+ {clip_name}: Valid file"]

            # Resolution check
            w = info.get('width', 0)
            h = info.get('height', 0)
            if w == 1280 and h == 720:
                score += 3.0
                clip_fb.append("1280x720")
            else:
                clip_fb.append(f"Res {w}x{h} (fail)")

            # Metadata check
            has_rot_metadata = _get_rotation_metadata(local_path)
            if not has_rot_metadata:
                score += 1.0
                clip_fb.append("No rot metadata")
            else:
                clip_fb.append("Has rot metadata (fail)")

            # Duration check (~10s expected)
            dur = info.get('duration', 0.0)
            total_clip_duration += dur
            if 8.5 <= dur <= 11.5:
                score += 2.0
                clip_fb.append(f"{dur:.1f}s")
            else:
                clip_fb.append(f"Dur {dur:.1f}s (fail)")

            feedback.append(" | ".join(clip_fb))

        # 2. Evaluate Highlight Reel (26 pts)
        export_dir = tempfile.mkdtemp(prefix='vlc_verify_export_')
        temp_dirs.append(export_dir)
        reel_path = os.path.join(export_dir, 'wedding_highlight.mp4')
        meta_path = os.path.join(export_dir, 'meta.json')
        
        try:
            copy_from_env('/tmp/wedding_export/wedding_highlight.mp4', reel_path)
            copy_from_env('/tmp/wedding_export/meta.json', meta_path)
        except Exception:
            pass

        if os.path.exists(reel_path) and os.path.getsize(reel_path) > 1000:
            info = get_video_info(reel_path)
            if 'error' not in info:
                score += 4.0  # Exists & playable
                
                # Check resolution
                if info.get('width') == 1280 and info.get('height') == 720:
                    score += 6.0
                    feedback.append("+ Reel: 1280x720 resolution")
                else:
                    feedback.append(f"x Reel: Wrong resolution ({info.get('width')}x{info.get('height')})")
                
                # Check duration (approx sum of the 6 clips, ~60s)
                dur = info.get('duration', 0.0)
                if 56.0 <= dur <= 64.0:
                    score += 8.0
                    feedback.append(f"+ Reel: Duration correct ({dur:.1f}s)")
                else:
                    feedback.append(f"x Reel: Duration incorrect ({dur:.1f}s, expected ~60s)")

                # Check audio (using ffprobe)
                try:
                    res = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'a', '-show_entries', 'stream=codec_type', '-of', 'json', reel_path], capture_output=True, text=True)
                    if 'codec_type' in res.stdout:
                        score += 4.0
                        feedback.append("+ Reel: Contains audio track")
                    else:
                        feedback.append("x Reel: Missing audio track")
                except:
                    feedback.append("x Reel: Audio check failed")

                # Anti-gaming: Check if newly created
                if os.path.exists(meta_path):
                    with open(meta_path, 'r') as mf:
                        meta = json.load(mf)
                        if meta.get('reel_newly_created', False):
                            score += 4.0
                            feedback.append("+ Reel: Created during task timeline")
                        else:
                            feedback.append("x Reel: Existed before task (anti-gaming)")
            else:
                feedback.append("x Reel: File invalid or corrupted")
        else:
            feedback.append("x Reel: File missing or empty")

        # 3. Evaluate Shot Correction Log (26 pts)
        log_path = os.path.join(export_dir, 'shot_correction_log.json')
        try:
            copy_from_env('/tmp/wedding_export/shot_correction_log.json', log_path)
        except Exception:
            pass

        if os.path.exists(log_path) and os.path.getsize(log_path) > 5:
            score += 4.0
            feedback.append("+ Log: File exists")
            try:
                with open(log_path, 'r', encoding='utf-8') as lf:
                    log_data = json.load(lf)
                
                score += 6.0
                feedback.append("+ Log: Valid JSON format")
                
                # Handle possible formats: list of dicts, or dict of dicts
                entries = log_data if isinstance(log_data, list) else list(log_data.values()) if isinstance(log_data, dict) else []
                
                if len(entries) >= 6:
                    score += 6.0
                    feedback.append("+ Log: Contains >= 6 entries")
                else:
                    feedback.append(f"x Log: Contains only {len(entries)} entries")
                
                # Check required fields
                required_keys = {'filename', 'original_resolution', 'issue', 'correction', 'output_resolution'}
                all_have_keys = True
                valid_entries = 0
                for entry in entries:
                    if isinstance(entry, dict):
                        keys_lower = {k.lower() for k in entry.keys()}
                        # allow some flexibility in naming like 'original_res'
                        matched = sum(1 for req in required_keys if any(req in k or k in req for k in keys_lower))
                        if matched >= 4:
                            valid_entries += 1
                        else:
                            all_have_keys = False
                
                if valid_entries >= 6:
                    score += 10.0
                    feedback.append("+ Log: Entries contain required structural fields")
                elif valid_entries > 0:
                    score += 5.0
                    feedback.append(f"~ Log: Only {valid_entries} entries have required fields")
                else:
                    feedback.append("x Log: Entries missing required structural fields")

            except json.JSONDecodeError:
                feedback.append("x Log: Invalid JSON format")
        else:
            feedback.append("x Log: File missing or empty")

    finally:
        for d in temp_dirs:
            if os.path.exists(d):
                try:
                    subprocess.run(['rm', '-rf', d])
                except Exception as e:
                    logger.warning(f"Failed to clean up temp dir {d}: {e}")

    passed = score >= 55.0
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }