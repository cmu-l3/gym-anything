import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from utils.vlc_verification_utils import get_video_info, get_audio_info


def _get_full_info(filepath):
    """Get comprehensive file info including audio stream details."""
    info = get_video_info(filepath)
    try:
        cmd = [
            'ffprobe', '-v', 'error',
            '-select_streams', 'a:0',
            '-show_entries', 'stream=codec_name,sample_rate,channels,bit_rate',
            '-show_entries', 'format=duration',
            '-of', 'json', filepath
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            if 'streams' in data and data['streams']:
                s = data['streams'][0]
                info['audio_codec'] = s.get('codec_name', '')
                info['audio_channels'] = int(s.get('channels', 0))
                info['audio_sample_rate'] = int(s.get('sample_rate', 0))
                info['audio_bitrate'] = int(s.get('bit_rate', 0)) if s.get('bit_rate') else 0
            if 'format' in data and not info.get('duration'):
                dur = data['format'].get('duration')
                if dur:
                    info['duration'] = float(dur)
    except Exception:
        pass
    return info


def _is_audio_only(filepath):
    """Check if file has no video stream."""
    try:
        cmd = [
            'ffprobe', '-v', 'error',
            '-select_streams', 'v',
            '-show_entries', 'stream=codec_type',
            '-of', 'json', filepath
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            return len(data.get('streams', [])) == 0
    except Exception:
        pass
    return False


def verify_multi_platform_distribution_transcode(traj, env_info, task_info):
    copy_from_env = env_info["copy_from_env"]
    """
    Verify multi-platform distribution transcode task.

    Criteria (28 points total, pass threshold = 70%):
    - Per platform (4 platforms x 5 points = 20 points):
      - File exists with correct name: 1 point
      - Correct video codec (or audio-only): 1 point
      - Correct resolution: 1 point
      - Correct framerate: 1 point
      - Correct audio config: 1 point
    - Deliverables manifest: 8 points (GATE: report required)
      - Valid JSON: 2 points
      - Lists all 4 deliverables: 2 points
      - Properties are accurate: 4 points
    """
    feedback = []
    score = 0.0
    max_score = 28.0
    temp_dirs = []

    # Platform specs (ground truth)
    platforms = {
        'broadcast': {
            'filename': 'broadcast_delivery.mp4',
            'video_codec': 'h264', 'width': 1920, 'height': 1080,
            'fps': 25, 'audio_codec': 'aac', 'audio_channels': 2,
            'audio_sample_rate': 48000, 'audio_only': False
        },
        'mobile': {
            'filename': 'mobile_delivery.mp4',
            'video_codec': 'h264', 'width': 640, 'height': 360,
            'fps': 30, 'audio_codec': 'aac', 'audio_channels': 1,
            'audio_sample_rate': 44100, 'audio_only': False
        },
        'web_streaming': {
            'filename': 'web_delivery.mkv',
            'video_codec': 'h264', 'width': 1280, 'height': 720,
            'fps': 30, 'audio_codec': 'aac', 'audio_channels': 2,
            'audio_sample_rate': 44100, 'audio_only': False
        },
        'audio_only': {
            'filename': 'audio_extract.mp3',
            'video_codec': 'none', 'width': 0, 'height': 0,
            'fps': 0, 'audio_codec': 'mp3', 'audio_channels': 2,
            'audio_sample_rate': 44100, 'audio_only': True
        }
    }

    try:
        for platform_name, spec in platforms.items():
            fname = spec['filename']
            td = tempfile.mkdtemp(prefix=f'vlc_verify_{platform_name}_')
            temp_dirs.append(td)
            local_path = os.path.join(td, fname)

            try:
                copy_from_env(f'/home/ga/Videos/deliverables/{fname}', local_path)
            except Exception:
                feedback.append(f"x [{platform_name}] {fname}: File not found")
                continue

            if not os.path.exists(local_path) or os.path.getsize(local_path) < 500:
                feedback.append(f"x [{platform_name}] {fname}: File missing or empty")
                continue

            # File exists
            score += 1.0
            pfeedback = [f"+ [{platform_name}] {fname}: File exists"]

            if spec['audio_only']:
                # Audio-only verification
                is_ao = _is_audio_only(local_path)
                if is_ao:
                    score += 2.0  # codec + resolution points (no video = correct)
                    pfeedback.append(f"  + Audio-only: Correct (no video stream)")
                else:
                    pfeedback.append(f"  x Audio-only: File contains video stream")

                # Audio codec
                ainfo = get_audio_info(local_path)
                a_codec = ainfo.get('codec', '').lower()
                if a_codec == spec['audio_codec']:
                    score += 1.0
                    pfeedback.append(f"  + Audio codec: {a_codec}")
                else:
                    pfeedback.append(f"  x Audio codec: {a_codec} (expected {spec['audio_codec']})")

                # Audio channels + sample rate
                a_ch = ainfo.get('channels', 0)
                a_sr = ainfo.get('sample_rate', 0)
                audio_match = True
                if a_ch != spec['audio_channels']:
                    audio_match = False
                if a_sr != spec['audio_sample_rate']:
                    audio_match = False
                if audio_match:
                    score += 1.0
                    pfeedback.append(f"  + Audio config: {a_ch}ch, {a_sr}Hz")
                else:
                    pfeedback.append(f"  x Audio config: {a_ch}ch/{a_sr}Hz (expected {spec['audio_channels']}ch/{spec['audio_sample_rate']}Hz)")
            else:
                # Video file verification
                info = _get_full_info(local_path)
                if 'error' in info:
                    pfeedback.append(f"  x Cannot probe file: {info['error']}")
                    feedback.extend(pfeedback)
                    continue

                # Video codec
                v_codec = info.get('codec', '').lower()
                if v_codec == spec['video_codec']:
                    score += 1.0
                    pfeedback.append(f"  + Video codec: {v_codec}")
                else:
                    pfeedback.append(f"  x Video codec: {v_codec} (expected {spec['video_codec']})")

                # Resolution
                w = info.get('width', 0)
                h = info.get('height', 0)
                if w == spec['width'] and h == spec['height']:
                    score += 1.0
                    pfeedback.append(f"  + Resolution: {w}x{h}")
                else:
                    pfeedback.append(f"  x Resolution: {w}x{h} (expected {spec['width']}x{spec['height']})")

                # Framerate
                fps = info.get('fps', 0)
                if abs(fps - spec['fps']) <= 1.0:
                    score += 1.0
                    pfeedback.append(f"  + Framerate: {fps:.1f}fps")
                else:
                    pfeedback.append(f"  x Framerate: {fps:.1f}fps (expected {spec['fps']}fps)")

                # Audio
                a_codec = info.get('audio_codec', '').lower()
                a_ch = info.get('audio_channels', 0)
                a_sr = info.get('audio_sample_rate', 0)
                audio_ok = (a_codec == spec['audio_codec'] and
                           a_ch == spec['audio_channels'] and
                           a_sr == spec['audio_sample_rate'])
                if audio_ok:
                    score += 1.0
                    pfeedback.append(f"  + Audio: {a_codec}, {a_ch}ch, {a_sr}Hz")
                else:
                    pfeedback.append(f"  x Audio: {a_codec}/{a_ch}ch/{a_sr}Hz (expected {spec['audio_codec']}/{spec['audio_channels']}ch/{spec['audio_sample_rate']}Hz)")

            feedback.extend(pfeedback)

        # --- Verify deliverables manifest ---
        manifest_dir = tempfile.mkdtemp(prefix='vlc_verify_manifest_')
        temp_dirs.append(manifest_dir)
        manifest_path = os.path.join(manifest_dir, 'manifest.json')

        try:
            copy_from_env('/home/ga/Documents/deliverables_manifest.json', manifest_path)
        except Exception:
            feedback.append("x Deliverables manifest: Not found")
            manifest_path = None

        if manifest_path and os.path.exists(manifest_path):
            try:
                with open(manifest_path, 'r') as f:
                    manifest = json.load(f)
                score += 2.0
                feedback.append("+ Deliverables manifest: Valid JSON")

                # Check if manifest lists all 4 deliverables
                manifest_str = json.dumps(manifest).lower()
                found = 0
                for spec in platforms.values():
                    if spec['filename'].lower() in manifest_str:
                        found += 1

                if found >= 4:
                    score += 2.0
                    feedback.append(f"+ Manifest: Lists all 4 deliverables")
                elif found >= 2:
                    score += 1.0
                    feedback.append(f"~ Manifest: {found}/4 deliverables listed")
                else:
                    feedback.append(f"x Manifest: Only {found}/4 deliverables listed")

                # Check if properties are present
                props_found = 0
                for prop in ['codec', 'resolution', 'duration', 'size', 'bitrate', 'audio', 'format']:
                    if prop in manifest_str:
                        props_found += 1
                if props_found >= 3:
                    score += 4.0
                    feedback.append(f"+ Manifest: Contains technical properties ({props_found} property types)")
                elif props_found >= 1:
                    score += 2.0
                    feedback.append(f"~ Manifest: Limited properties ({props_found} types)")
                else:
                    feedback.append("x Manifest: No technical properties found")

            except json.JSONDecodeError:
                feedback.append("x Deliverables manifest: Invalid JSON")
            except Exception as e:
                feedback.append(f"x Deliverables manifest: Error ({str(e)})")

        # --- Calculate final result ---
        pct = int(score / max_score * 100)
        passed = pct >= 70

        feedback.insert(0, f"Score: {pct}% ({score}/{max_score} points)")
        feedback.insert(1, f"Result: {'PASSED' if passed else 'FAILED'}")
        feedback.insert(2, "---")

        return {
            "passed": passed,
            "score": pct,
            "feedback": "\n".join(feedback)
        }

    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        for td in temp_dirs:
            shutil.rmtree(td, ignore_errors=True)
