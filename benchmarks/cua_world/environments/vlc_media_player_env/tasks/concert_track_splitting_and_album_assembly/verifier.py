#!/usr/bin/env python3
"""
Verifier for Concert Recording Track Splitting and Album Assembly.

Evaluates 5 tracks on:
- Audio Tracks (MP3 format, accurate duration)
- ID3 Tags (Title, Artist, Album, Track number)
- Thumbnails (Valid PNGs of sufficient size)
- Preview Clips (MP4 video+audio, ~8s duration)
- JSON Manifest (valid structure matching output)

Total 100 points, Pass threshold 60.
"""

import os
import json
import tempfile
import subprocess
import tarfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_ffprobe_info(filepath, is_audio_only=False):
    """Get multimedia info using ffprobe."""
    info = {"format": "", "duration": 0.0, "tags": {}, "has_video": False, "has_audio": False}
    try:
        cmd = [
            'ffprobe', '-v', 'error',
            '-show_entries', 'format=format_name,duration,tags',
            '-show_entries', 'stream=codec_type',
            '-of', 'json', filepath
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            fmt = data.get('format', {})
            info['format'] = fmt.get('format_name', '')
            info['duration'] = float(fmt.get('duration', 0.0))
            
            # Normalize ID3 tag keys to lowercase
            tags = fmt.get('tags', {})
            info['tags'] = {k.lower(): v for k, v in tags.items()}
            
            streams = data.get('streams', [])
            for s in streams:
                if s.get('codec_type') == 'video':
                    info['has_video'] = True
                if s.get('codec_type') == 'audio':
                    info['has_audio'] = True
    except Exception as e:
        logger.warning(f"ffprobe error on {filepath}: {e}")
    return info

def verify_concert_track_splitting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_album = metadata.get('expected_album', 'Venue Showcase 2024')
    track_data = metadata.get('track_data', [])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Read export manifest
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    if not export_result.get("output_dir_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output directory /home/ga/Music/album_output/ missing."}

    # 2. Extract tarball
    temp_tar = tempfile.NamedTemporaryFile(delete=False, suffix='.tar.gz')
    extract_dir = tempfile.mkdtemp()
    
    try:
        copy_from_env("/tmp/album_output.tar.gz", temp_tar.name)
        with tarfile.open(temp_tar.name, "r:gz") as tar:
            tar.extractall(path=extract_dir)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to extract outputs: {e}"}
    finally:
        if os.path.exists(temp_tar.name):
            os.unlink(temp_tar.name)

    base_dir = os.path.join(extract_dir, 'album_output')

    # Point Distribution:
    # Tracks (MP3, Dur): 5 * 6 = 30 pts
    # ID3 Tags: 5 * 4 = 20 pts
    # Thumbnails: 5 * 4 = 20 pts
    # Previews: 5 * 4 = 20 pts
    # Manifest: 10 pts
    
    # Check each track (1 to 5)
    for i in range(1, 6):
        idx = i - 1
        expected = track_data[idx] if idx < len(track_data) else {}
        expected_dur = expected.get("duration", 20)
        
        # --- Audio Tracks & ID3 ---
        mp3_path = os.path.join(base_dir, 'tracks', f'track_0{i}.mp3')
        if os.path.exists(mp3_path):
            info = get_ffprobe_info(mp3_path)
            
            # Format and Duration
            if 'mp3' in info['format'].lower():
                dur = info['duration']
                if abs(dur - expected_dur) <= 4.0:
                    score += 6
                    feedback_parts.append(f"Track {i} Audio: OK ({dur:.1f}s)")
                else:
                    score += 2 # Partial for having the file
                    feedback_parts.append(f"Track {i} Audio: Wrong duration ({dur:.1f}s, expected ~{expected_dur}s)")
            else:
                feedback_parts.append(f"Track {i} Audio: Not MP3")
                
            # ID3 Tags
            tags = info['tags']
            tags_matched = 0
            if expected.get('title', '').lower() in tags.get('title', '').lower() and expected.get('title') != "":
                tags_matched += 1
            if expected.get('artist', '').lower() in tags.get('artist', '').lower() and expected.get('artist') != "":
                tags_matched += 1
            if expected_album.lower() in tags.get('album', '').lower():
                tags_matched += 1
            if str(i) in str(tags.get('track', '')):
                tags_matched += 1
                
            tag_score = tags_matched * 1  # 4 checks * 1pt each
            score += tag_score
            if tag_score == 4:
                feedback_parts.append(f"Track {i} ID3: All Correct")
            else:
                feedback_parts.append(f"Track {i} ID3: {tags_matched}/4 tags correct")
        else:
            feedback_parts.append(f"Track {i} Audio: Missing")

        # --- Thumbnails ---
        png_path = os.path.join(base_dir, 'thumbnails', f'thumb_0{i}.png')
        if os.path.exists(png_path):
            size_kb = os.path.getsize(png_path) / 1024
            if size_kb > 5.0:
                score += 4
                feedback_parts.append(f"Track {i} Thumb: OK ({size_kb:.1f}KB)")
            else:
                score += 1
                feedback_parts.append(f"Track {i} Thumb: Too small ({size_kb:.1f}KB)")
        else:
            feedback_parts.append(f"Track {i} Thumb: Missing")

        # --- Preview Clips ---
        mp4_path = os.path.join(base_dir, 'previews', f'preview_0{i}.mp4')
        if os.path.exists(mp4_path):
            info = get_ffprobe_info(mp4_path)
            if info['has_video'] and info['has_audio']:
                dur = info['duration']
                if 2.0 <= dur <= 12.0:  # ~8s requested
                    score += 4
                    feedback_parts.append(f"Track {i} Preview: OK ({dur:.1f}s)")
                else:
                    score += 2
                    feedback_parts.append(f"Track {i} Preview: Wrong duration ({dur:.1f}s)")
            else:
                feedback_parts.append(f"Track {i} Preview: Missing A/V streams")
        else:
            feedback_parts.append(f"Track {i} Preview: Missing")

    # --- JSON Manifest ---
    manifest_path = os.path.join(base_dir, 'album_manifest.json')
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path, 'r') as f:
                manifest = json.load(f)
            
            # Allow manifest to be a list or a dict containing a list
            items = manifest if isinstance(manifest, list) else manifest.get('tracks', list(manifest.values()) if isinstance(manifest, dict) else [])
            
            if len(items) >= 5:
                # Check structure on first item
                first = items[0]
                has_fields = all(k in first for k in ['title', 'artist'])
                if has_fields:
                    score += 10
                    feedback_parts.append("Manifest: Valid")
                else:
                    score += 5
                    feedback_parts.append("Manifest: Missing fields")
            else:
                score += 3
                feedback_parts.append("Manifest: Incomplete entries")
        except Exception as e:
            feedback_parts.append(f"Manifest: Invalid JSON ({e})")
    else:
        feedback_parts.append("Manifest: Missing")

    # Final Decision
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }