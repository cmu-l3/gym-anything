#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_audio_video_info(ffprobe_data):
    """Helper to extract video and audio streams info safely."""
    has_video = False
    has_audio = False
    duration = 0.0
    bitrate = 0
    channels = 0
    
    if not ffprobe_data:
        return has_video, has_audio, duration, bitrate, channels

    if 'format' in ffprobe_data:
        duration = float(ffprobe_data['format'].get('duration', 0.0))

    for stream in ffprobe_data.get('streams', []):
        if stream.get('codec_type') == 'video':
            has_video = True
        if stream.get('codec_type') == 'audio':
            has_audio = True
            channels = int(stream.get('channels', channels))
            # Bitrate might be defined in stream or format level
            stream_br = stream.get('bit_rate')
            if stream_br:
                bitrate = int(stream_br)
            elif 'format' in ffprobe_data and ffprobe_data['format'].get('bit_rate'):
                bitrate = int(ffprobe_data['format'].get('bit_rate'))

    return has_video, has_audio, duration, bitrate, channels

def verify_lecture_speed_variants_study_package(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0.0
    max_score = 30.0
    feedback = []

    # 1. Fetch Task Start Time
    start_time = 0.0
    try:
        temp_start = tempfile.NamedTemporaryFile(delete=False)
        temp_start.close()
        copy_from_env('/tmp/task_start_time.txt', temp_start.name)
        with open(temp_start.name, 'r') as f:
            start_time = float(f.read().strip())
    except Exception as e:
        logger.warning(f"Failed to read start time: {e}")
    finally:
        if os.path.exists(temp_start.name):
            os.unlink(temp_start.name)

    # 2. Fetch Export Metadata
    metadata = {}
    try:
        temp_meta = tempfile.NamedTemporaryFile(delete=False)
        temp_meta.close()
        copy_from_env('/tmp/export_metadata.json', temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            metadata = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read metadata: {e}")
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    # 3. Assess Speed Variants
    duration_075x = 0
    duration_150x = 0
    duration_200x = 0

    # Slow 0.75x
    if 'lecture_075x.mp4' in metadata:
        mtime = metadata['lecture_075x.mp4'].get('mtime', 0)
        if mtime < start_time:
            feedback.append("x Slow video created before task start (anti-gaming)")
        else:
            score += 1
            feedback.append("+ Slow video exists")
            has_video, has_audio, duration_075x, _, _ = get_audio_video_info(metadata['lecture_075x.mp4'].get('ffprobe'))
            if abs(duration_075x - 120.0) <= 5.0:
                score += 2
                feedback.append("+ Slow video duration correct (~120s)")
            else:
                feedback.append(f"x Slow video duration incorrect ({duration_075x:.1f}s)")
            if has_audio:
                score += 1
                feedback.append("+ Slow video contains audio track")
    else:
        feedback.append("x Slow video missing")

    # Fast 1.5x
    if 'lecture_150x.mp4' in metadata:
        mtime = metadata['lecture_150x.mp4'].get('mtime', 0)
        if mtime < start_time:
            feedback.append("x Fast video created before task start")
        else:
            score += 1
            feedback.append("+ Fast video exists")
            has_video, has_audio, duration_150x, _, _ = get_audio_video_info(metadata['lecture_150x.mp4'].get('ffprobe'))
            if abs(duration_150x - 60.0) <= 3.0:
                score += 2
                feedback.append("+ Fast video duration correct (~60s)")
            else:
                feedback.append(f"x Fast video duration incorrect ({duration_150x:.1f}s)")
            if has_audio:
                score += 1
                feedback.append("+ Fast video contains audio track")
    else:
        feedback.append("x Fast video missing")

    # Double 2.0x
    if 'lecture_200x.mp4' in metadata:
        mtime = metadata['lecture_200x.mp4'].get('mtime', 0)
        if mtime < start_time:
            feedback.append("x Double video created before task start")
        else:
            score += 1
            feedback.append("+ Double video exists")
            has_video, has_audio, duration_200x, _, _ = get_audio_video_info(metadata['lecture_200x.mp4'].get('ffprobe'))
            if abs(duration_200x - 45.0) <= 3.0:
                score += 2
                feedback.append("+ Double video duration correct (~45s)")
            else:
                feedback.append(f"x Double video duration incorrect ({duration_200x:.1f}s)")
            if has_audio:
                score += 1
                feedback.append("+ Double video contains audio track")
    else:
        feedback.append("x Double video missing")

    # Ordering logical check
    if duration_075x > 85.0 > duration_150x > duration_200x > 0:
        score += 1
        feedback.append("+ Video durations correctly ordered by speed")

    # 4. Assess Snapshots
    snapshot_files = [f for f in metadata.keys() if f.startswith('snapshots/') and f.endswith('.png')]
    if len(snapshot_files) > 0:
        score += 1
        feedback.append("+ Snapshots directory created")
    
    if len(snapshot_files) == 7:
        score += 2
        feedback.append("+ Correct snapshot count (7 images)")
    
    valid_snapshots = 0
    for sf in snapshot_files:
        if metadata[sf].get('size', 0) > 5000 and metadata[sf].get('mtime', 0) >= start_time:
            valid_snapshots += 1
            
    if valid_snapshots == 7:
        score += 2
        feedback.append("+ All snapshots are valid PNGs")
    elif valid_snapshots > 0:
        score += 1
        feedback.append(f"~ Partial valid snapshots ({valid_snapshots}/7)")

    # 5. Assess Audio-only Podcast
    if 'lecture_audio.mp3' in metadata:
        mtime = metadata['lecture_audio.mp3'].get('mtime', 0)
        if mtime < start_time:
            feedback.append("x Audio file created before task start")
        else:
            score += 1
            feedback.append("+ Audio file exists")
            has_video, has_audio, duration_aud, bitrate_aud, channels_aud = get_audio_video_info(metadata['lecture_audio.mp3'].get('ffprobe'))
            
            if abs(duration_aud - 90.0) <= 5.0:
                score += 2
                feedback.append("+ Audio duration correct (~90s)")
            
            # Allow ±50 kbps variance for VBR encoders near 192k target
            if abs(bitrate_aud - 192000) <= 50000:
                score += 1
                feedback.append(f"+ Audio bitrate correct (~{bitrate_aud//1000}kbps)")
                
            if channels_aud == 2:
                score += 1
                feedback.append("+ Audio is stereo")
    else:
        feedback.append("x Audio file missing")

    # 6. Assess Package Manifest
    if 'study_package.json' in metadata and metadata['study_package.json'].get('mtime', 0) >= start_time:
        temp_mf = tempfile.NamedTemporaryFile(delete=False)
        temp_mf.close()
        try:
            copy_from_env('/tmp/export_payload/study_package.json', temp_mf.name)
            with open(temp_mf.name, 'r') as f:
                mf_data = json.load(f)
            
            score += 1
            feedback.append("+ Manifest exists and is valid JSON")
            
            mf_str = json.dumps(mf_data).lower()
            if 'lecture_075x' in mf_str and 'lecture_150x' in mf_str and 'lecture_200x' in mf_str:
                score += 2
                feedback.append("+ Manifest lists all 3 speed variants")
            elif '075x' in mf_str or '150x' in mf_str or '200x' in mf_str:
                score += 1
                feedback.append("~ Manifest partially lists speed variants")
                
            if 'lecture_audio' in mf_str:
                score += 1
                feedback.append("+ Manifest lists audio podcast")
                
            if any(k in mf_str for k in ['duration', 'length', 'time']):
                score += 1
                feedback.append("+ Manifest includes duration metrics")
                
            if any(k in mf_str for k in ['size', 'bytes']):
                score += 1
                feedback.append("+ Manifest includes file size metrics")
                
        except Exception:
            feedback.append("x Manifest missing or invalid JSON content")
        finally:
            if os.path.exists(temp_mf.name):
                os.unlink(temp_mf.name)
    else:
        feedback.append("x Manifest missing")

    # Calculate final scaled score (0-100)
    passed = score >= 17.0
    final_score = int((score / max_score) * 100)
    
    return {
        "passed": passed, 
        "score": final_score, 
        "feedback": " | ".join(feedback)
    }