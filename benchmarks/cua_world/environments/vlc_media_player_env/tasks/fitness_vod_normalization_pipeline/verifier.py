#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import subprocess

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _probe_full(filepath):
    info = {}
    try:
        cmd = [
            'ffprobe', '-v', 'error',
            '-select_streams', 'v:0',
            '-show_entries', 'stream=codec_name,width,height,r_frame_rate',
            '-show_entries', 'format=duration',
            '-of', 'json', filepath
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            if 'streams' in data and data['streams']:
                s = data['streams'][0]
                info['video_codec'] = s.get('codec_name', '')
                info['width'] = int(s.get('width', 0))
                info['height'] = int(s.get('height', 0))
                fps_str = s.get('r_frame_rate', '0/1')
                if '/' in fps_str:
                    num, den = map(int, fps_str.split('/'))
                    info['fps'] = num / den if den > 0 else 0
                else:
                    info['fps'] = float(fps_str)
            if 'format' in data:
                dur = data['format'].get('duration')
                if dur:
                    info['duration'] = float(dur)
                    
        cmd_a = [
            'ffprobe', '-v', 'error',
            '-select_streams', 'a:0',
            '-show_entries', 'stream=codec_name,sample_rate,channels,bit_rate',
            '-of', 'json', filepath
        ]
        res_a = subprocess.run(cmd_a, capture_output=True, text=True, timeout=10)
        if res_a.returncode == 0:
            data_a = json.loads(res_a.stdout)
            if 'streams' in data_a and data_a['streams']:
                s = data_a['streams'][0]
                info['audio_codec'] = s.get('codec_name', '')
                info['audio_sample_rate'] = int(s.get('sample_rate', 0))
                info['audio_bitrate'] = int(s.get('bit_rate', 0)) if s.get('bit_rate') else 0
    except Exception as e:
        info['error'] = str(e)
    return info

def verify_fitness_vod_normalization_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0.0
    master_ok = False
    
    files_to_check = {
        '03_block_A.mp4': '/tmp/normalized/03_block_A.mp4',
        '06_cooldown.mp4': '/tmp/normalized/06_cooldown.mp4',
        'master_class.mp4': '/tmp/deliverables/master_class.mp4',
        'outdoor_audio.mp3': '/tmp/deliverables/outdoor_audio.mp3',
        'studio_playlist.m3u': '/tmp/deliverables/studio_playlist.m3u',
        'class_metadata.json': '/tmp/class_metadata.json'
    }
    
    local_paths = {}
    
    for key, path in files_to_check.items():
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(path)[1])
        temp_file.close()
        try:
            copy_from_env(path, temp_file.name)
            if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                local_paths[key] = temp_file.name
            else:
                local_paths[key] = None
        except Exception:
            local_paths[key] = None

    # Check 03_block_A.mp4
    path_03 = local_paths['03_block_A.mp4']
    if path_03 and os.path.getsize(path_03) > 1000:
        info = _probe_full(path_03)
        if info.get('width') == 1280 and info.get('height') == 720 and abs(info.get('fps', 0) - 30) < 1.0 and info.get('video_codec') == 'h264' and info.get('audio_codec') == 'aac' and info.get('audio_sample_rate') == 44100:
            score += 15
            feedback.append("+ File 03 normalized perfectly.")
        else:
            score += 5
            feedback.append(f"~ File 03 normalization partial: {info}")
    else:
        feedback.append("x File 03 not found or empty.")

    # Check 06_cooldown.mp4
    path_06 = local_paths['06_cooldown.mp4']
    if path_06 and os.path.getsize(path_06) > 1000:
        info = _probe_full(path_06)
        if info.get('width') == 1280 and info.get('height') == 720 and abs(info.get('fps', 0) - 30) < 1.0 and info.get('video_codec') == 'h264' and info.get('audio_codec') == 'aac' and info.get('audio_sample_rate') == 44100:
            score += 15
            feedback.append("+ File 06 normalized perfectly.")
        else:
            score += 5
            feedback.append(f"~ File 06 normalization partial: {info}")
    else:
        feedback.append("x File 06 not found or empty.")

    # Check master class
    path_master = local_paths['master_class.mp4']
    if path_master and os.path.getsize(path_master) > 1000:
        info = _probe_full(path_master)
        dur = info.get('duration', 0)
        if info.get('width') == 1280 and info.get('height') == 720 and info.get('video_codec') == 'h264' and abs(dur - 36.0) <= 2.5 and info.get('audio_codec'):
            score += 30
            master_ok = True
            feedback.append(f"+ Master class concatenated successfully (duration: {dur:.1f}s).")
        else:
            score += 10
            feedback.append(f"~ Master class has issues: duration={dur}, expected ~36s, info={info}")
    else:
        feedback.append("x Master class not found or empty.")

    # Check audio extraction
    path_audio = local_paths['outdoor_audio.mp3']
    if path_audio and os.path.getsize(path_audio) > 1000:
        info = _probe_full(path_audio)
        dur = info.get('duration', 0)
        if info.get('audio_codec') == 'mp3' and abs(dur - 36.0) <= 2.5:
            score += 15
            feedback.append("+ Audio extracted successfully.")
        else:
            score += 5
            feedback.append(f"~ Audio extraction has issues: {info}")
    else:
        feedback.append("x Audio extraction not found or empty.")

    # Check M3U playlist
    path_m3u = local_paths['studio_playlist.m3u']
    if path_m3u:
        with open(path_m3u, 'r') as f:
            content = f.read()
        paths = [line.strip() for line in content.splitlines() if line.strip() and not line.startswith('#')]
        if len(paths) == 6:
            score += 15
            feedback.append("+ M3U playlist valid.")
        else:
            score += 5
            feedback.append(f"~ M3U playlist invalid: found {len(paths)} entries.")
    else:
        feedback.append("x M3U playlist not found.")

    # Check JSON
    path_json = local_paths['class_metadata.json']
    if path_json:
        try:
            with open(path_json, 'r') as f:
                data = json.load(f)
            if 'total_duration_sec' in data and 'sequence' in data and len(data['sequence']) == 6:
                score += 10
                feedback.append("+ JSON manifest valid.")
            else:
                score += 5
                feedback.append("~ JSON manifest missing keys or sequence length wrong.")
        except Exception:
            feedback.append("x JSON manifest could not be parsed.")
    else:
        feedback.append("x JSON manifest not found.")

    # Clean up temp files
    for path in local_paths.values():
        if path and os.path.exists(path):
            os.unlink(path)

    passed = (score >= 70) and master_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }