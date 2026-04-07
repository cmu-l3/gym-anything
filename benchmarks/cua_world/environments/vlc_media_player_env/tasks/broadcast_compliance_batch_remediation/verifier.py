import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from utils.vlc_verification_utils import get_video_info, get_audio_info


def _probe_full(filepath):
    """Get both video and audio stream info from a file."""
    vinfo = get_video_info(filepath)
    # Get audio info separately
    try:
        cmd = [
            'ffprobe', '-v', 'error',
            '-select_streams', 'a:0',
            '-show_entries', 'stream=codec_name,sample_rate,channels',
            '-of', 'json', filepath
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            if 'streams' in data and len(data['streams']) > 0:
                s = data['streams'][0]
                vinfo['audio_codec'] = s.get('codec_name', '')
                vinfo['audio_channels'] = int(s.get('channels', 0))
                vinfo['audio_sample_rate'] = int(s.get('sample_rate', 0))
    except Exception:
        pass
    return vinfo


def verify_broadcast_compliance_batch_remediation(traj, env_info, task_info):
    """
    Verify broadcast compliance batch remediation task.

    Criteria (24 points total, pass threshold = 70%):
    - Per file (4 files x 4 points each = 16 points):
      - File exists and is valid video: 1 point
      - Correct resolution (1920x1080): 1 point
      - Correct framerate (25fps ±0.5): 1 point
      - Correct audio (stereo AAC 48kHz): 1 point
    - Compliance report: 8 points (GATE: report required for pass)
      - Valid JSON: 2 points
      - Contains all 4 file entries: 2 points
      - Correctly identifies violations: 4 points
    """
    copy_from_env = env_info["copy_from_env"]
    feedback = []
    score = 0.0
    max_score = 24.0
    temp_dirs = []

    expected_files = [
        'news_segment_01.mp4',
        'sports_highlight_02.mp4',
        'interview_03.mp4',
        'documentary_04.mp4',  # Agent should convert .mpg to .mp4
    ]

    try:
        # --- Copy ground truth ---
        gt_dir = tempfile.mkdtemp(prefix='vlc_verify_gt_')
        temp_dirs.append(gt_dir)
        gt_path = os.path.join(gt_dir, 'gt.json')
        try:
            copy_from_env('/tmp/.broadcast_ground_truth.json', gt_path)
            with open(gt_path, 'r') as f:
                ground_truth = json.load(f)
        except Exception:
            ground_truth = None
            feedback.append("! Could not load ground truth")

        # --- Verify each remediated file ---
        for fname in expected_files:
            td = tempfile.mkdtemp(prefix='vlc_verify_bc_')
            temp_dirs.append(td)
            local_path = os.path.join(td, fname)

            try:
                copy_from_env(f'/home/ga/Videos/broadcast_ready/{fname}', local_path)
            except Exception:
                feedback.append(f"x {fname}: File not found in broadcast_ready/")
                continue

            if not os.path.exists(local_path) or os.path.getsize(local_path) < 1000:
                feedback.append(f"x {fname}: File missing or too small")
                continue

            info = _probe_full(local_path)
            if 'error' in info:
                feedback.append(f"x {fname}: Invalid media file ({info['error']})")
                continue

            # File exists and is valid
            score += 1.0
            file_feedback = [f"+ {fname}: Valid media file"]

            # Check resolution
            w = info.get('width', 0)
            h = info.get('height', 0)
            if w == 1920 and h == 1080:
                score += 1.0
                file_feedback.append(f"  + Resolution: {w}x{h} (correct)")
            else:
                file_feedback.append(f"  x Resolution: {w}x{h} (expected 1920x1080)")

            # Check framerate
            fps = info.get('fps', 0)
            if abs(fps - 25.0) <= 0.5:
                score += 1.0
                file_feedback.append(f"  + Framerate: {fps:.1f}fps (correct)")
            else:
                file_feedback.append(f"  x Framerate: {fps:.1f}fps (expected 25fps)")

            # Check audio: stereo AAC 48kHz
            audio_ok = True
            audio_parts = []
            a_codec = info.get('audio_codec', '').lower()
            a_ch = info.get('audio_channels', 0)
            a_sr = info.get('audio_sample_rate', 0)

            if a_codec == 'aac':
                audio_parts.append(f"codec=AAC")
            else:
                audio_ok = False
                audio_parts.append(f"codec={a_codec} (expected AAC)")

            if a_ch == 2:
                audio_parts.append(f"channels=stereo")
            else:
                audio_ok = False
                audio_parts.append(f"channels={a_ch} (expected 2)")

            if a_sr == 48000:
                audio_parts.append(f"sample_rate=48kHz")
            else:
                audio_ok = False
                audio_parts.append(f"sample_rate={a_sr} (expected 48000)")

            if audio_ok:
                score += 1.0
                file_feedback.append(f"  + Audio: {', '.join(audio_parts)}")
            else:
                file_feedback.append(f"  x Audio: {', '.join(audio_parts)}")

            feedback.extend(file_feedback)

        # --- Verify compliance report ---
        report_dir = tempfile.mkdtemp(prefix='vlc_verify_rpt_')
        temp_dirs.append(report_dir)
        report_path = os.path.join(report_dir, 'compliance_report.json')

        try:
            copy_from_env('/home/ga/Documents/compliance_report.json', report_path)
        except Exception:
            feedback.append("x Compliance report: Not found")
            report_path = None

        if report_path and os.path.exists(report_path):
            try:
                with open(report_path, 'r') as f:
                    report = json.load(f)
                score += 2.0
                feedback.append("+ Compliance report: Valid JSON")

                # Check if report contains entries for all 4 files
                report_str = json.dumps(report).lower()
                found_files = 0
                for fname in ['news_segment', 'sports_highlight', 'interview', 'documentary']:
                    if fname in report_str:
                        found_files += 1

                if found_files >= 4:
                    score += 2.0
                    feedback.append(f"+ Compliance report: Contains all 4 file entries")
                elif found_files >= 2:
                    score += 1.0
                    feedback.append(f"~ Compliance report: {found_files}/4 file entries found")
                else:
                    feedback.append(f"x Compliance report: Only {found_files}/4 file entries found")

                # Check if report identifies violations correctly
                violation_keywords = {
                    'news_segment': ['framerate', 'fps', 'frame rate', 'frame_rate'],
                    'sports_highlight': ['resolution', 'size', 'dimension', '720x480', '720'],
                    'interview': ['mono', 'channel', 'audio', 'stereo'],
                    'documentary': ['codec', 'mpeg', 'container', 'mpg', 'format'],
                }

                violations_correct = 0
                for file_key, keywords in violation_keywords.items():
                    for kw in keywords:
                        if kw in report_str:
                            violations_correct += 1
                            break

                if violations_correct >= 4:
                    score += 4.0
                    feedback.append("+ Compliance report: All violations correctly identified")
                elif violations_correct >= 2:
                    score += 2.0
                    feedback.append(f"~ Compliance report: {violations_correct}/4 violations identified")
                else:
                    feedback.append(f"x Compliance report: Only {violations_correct}/4 violations identified")

            except json.JSONDecodeError:
                feedback.append("x Compliance report: Invalid JSON format")
            except Exception as e:
                feedback.append(f"x Compliance report: Error reading ({str(e)})")

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
