import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from utils.vlc_verification_utils import get_audio_info


def _get_mp3_id3_tags(filepath):
    """Extract ID3 tags from MP3 file using ffprobe."""
    tags = {}
    try:
        cmd = [
            'ffprobe', '-v', 'error',
            '-show_entries', 'format_tags=title,artist,album,track',
            '-of', 'json', filepath
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            fmt_tags = data.get('format', {}).get('tags', {})
            # Normalize keys to lowercase
            tags = {k.lower(): v for k, v in fmt_tags.items()}
    except Exception:
        pass
    return tags


def _get_audio_duration(filepath):
    """Get audio duration using ffprobe."""
    try:
        cmd = [
            'ffprobe', '-v', 'error',
            '-show_entries', 'format=duration',
            '-of', 'json', filepath
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            dur = data.get('format', {}).get('duration')
            if dur:
                return float(dur)
    except Exception:
        pass
    return 0.0


def verify_podcast_episode_assembly_and_mastering(traj, env_info, task_info):
    copy_from_env = env_info["copy_from_env"]
    """
    Verify podcast episode assembly and mastering task.

    Criteria (22 points total, pass threshold = 55%):
    - Master WAV (6 points):
      - File exists and is WAV format: 1 point
      - Correct duration (~70s ±3s): 2 points
      - Stereo, 44.1kHz: 2 points
      - Not just a copy of episode_raw.wav (duration check): 1 point
    - Distribution MP3 (8 points):
      - File exists and is MP3: 1 point
      - Correct bitrate (~192kbps ±30): 1 point
      - Correct duration (~70s ±3s): 1 point
      - ID3 Title correct: 1.5 points
      - ID3 Artist correct: 1.5 points
      - ID3 Album correct: 1 point
      - ID3 Track correct: 1 point
    - Highlight clip (6 points):
      - File exists: 1 point
      - Correct duration (~15s ±2s): 2 points
      - Is MP3 format: 1 point
      - Not full episode (duration gate): 2 points
    - All files in correct directory: 2 points
    """
    feedback = []
    score = 0.0
    max_score = 22.0
    temp_dirs = []

    # Ground truth
    TOTAL_DURATION = 70.0  # 5 + 60 + 5
    EPISODE_DURATION = 60.0
    HIGHLIGHT_DURATION = 15.0
    DURATION_TOLERANCE = 3.0
    EXPECTED_BITRATE = 192000

    try:
        output_dir = tempfile.mkdtemp(prefix='vlc_verify_podcast_')
        temp_dirs.append(output_dir)

        # Expected filenames
        master_name = 'episode_47_master.wav'
        dist_name = 'episode_47_dist.mp3'
        highlight_name = 'episode_47_highlight.mp3'

        files_in_correct_dir = 0

        # --- Verify Master WAV ---
        master_path = os.path.join(output_dir, master_name)
        try:
            copy_from_env(f'/home/ga/Music/podcast_output/{master_name}', master_path)
            files_in_correct_dir += 1
        except Exception:
            # Try alternative names
            try:
                copy_from_env('/tmp/podcast_output/' + master_name, master_path)
            except Exception:
                feedback.append(f"x Master WAV: {master_name} not found in podcast_output/")
                master_path = None

        if master_path and os.path.exists(master_path) and os.path.getsize(master_path) > 1000:
            ainfo = get_audio_info(master_path)
            codec = ainfo.get('codec', '').lower()

            # Check format
            if codec in ('pcm_s16le', 'pcm_s24le', 'pcm_s32le', 'pcm_f32le', 'pcm_s16be'):
                score += 1.0
                feedback.append(f"+ Master WAV: Valid WAV format ({codec})")
            else:
                feedback.append(f"x Master WAV: Not WAV format (codec: {codec})")

            # Check duration (should be ~70s = intro 5 + episode 60 + outro 5)
            dur = _get_audio_duration(master_path)
            if abs(dur - TOTAL_DURATION) <= DURATION_TOLERANCE:
                score += 2.0
                feedback.append(f"+ Master WAV: Duration {dur:.1f}s (expected ~{TOTAL_DURATION}s)")
            elif abs(dur - EPISODE_DURATION) <= DURATION_TOLERANCE:
                # Agent only included episode, not concatenated
                score += 0.5
                feedback.append(f"~ Master WAV: Duration {dur:.1f}s (only episode, missing intro/outro)")
            else:
                feedback.append(f"x Master WAV: Duration {dur:.1f}s (expected ~{TOTAL_DURATION}s)")

            # Check stereo and sample rate
            channels = ainfo.get('channels', 0)
            sr = ainfo.get('sample_rate', 0)
            if channels == 2 and sr == 44100:
                score += 2.0
                feedback.append(f"+ Master WAV: Stereo, 44.1kHz")
            elif channels == 2 or sr == 44100:
                score += 1.0
                feedback.append(f"~ Master WAV: {channels}ch, {sr}Hz (expected stereo 44100)")
            else:
                feedback.append(f"x Master WAV: {channels}ch, {sr}Hz")

            # Not just a copy of raw episode (wrong-target gate)
            if abs(dur - TOTAL_DURATION) <= DURATION_TOLERANCE:
                score += 1.0
                feedback.append("+ Master WAV: Properly concatenated (not raw copy)")
        else:
            feedback.append(f"x Master WAV: File not found or empty")

        # --- Verify Distribution MP3 ---
        dist_path = os.path.join(output_dir, dist_name)
        try:
            copy_from_env(f'/home/ga/Music/podcast_output/{dist_name}', dist_path)
            files_in_correct_dir += 1
        except Exception:
            try:
                copy_from_env('/tmp/podcast_output/' + dist_name, dist_path)
            except Exception:
                feedback.append(f"x Distribution MP3: {dist_name} not found")
                dist_path = None

        if dist_path and os.path.exists(dist_path) and os.path.getsize(dist_path) > 1000:
            ainfo = get_audio_info(dist_path)
            codec = ainfo.get('codec', '').lower()

            # Check MP3 format
            if codec == 'mp3':
                score += 1.0
                feedback.append("+ Distribution MP3: Valid MP3 format")
            else:
                feedback.append(f"x Distribution MP3: Not MP3 (codec: {codec})")

            # Check bitrate (~192kbps)
            bitrate = ainfo.get('bitrate', 0)
            if 160000 <= bitrate <= 224000:
                score += 1.0
                feedback.append(f"+ Distribution MP3: Bitrate {bitrate//1000}kbps")
            else:
                feedback.append(f"x Distribution MP3: Bitrate {bitrate//1000}kbps (expected ~192kbps)")

            # Check duration
            dur = _get_audio_duration(dist_path)
            if abs(dur - TOTAL_DURATION) <= DURATION_TOLERANCE:
                score += 1.0
                feedback.append(f"+ Distribution MP3: Duration {dur:.1f}s")
            else:
                feedback.append(f"x Distribution MP3: Duration {dur:.1f}s (expected ~{TOTAL_DURATION}s)")

            # Check ID3 tags
            tags = _get_mp3_id3_tags(dist_path)

            # Title
            title = tags.get('title', '')
            if 'episode 47' in title.lower() and 'market' in title.lower():
                score += 1.5
                feedback.append(f"+ ID3 Title: '{title}'")
            elif 'episode' in title.lower() or '47' in title:
                score += 0.5
                feedback.append(f"~ ID3 Title: '{title}' (partial match)")
            else:
                feedback.append(f"x ID3 Title: '{title}' (expected 'Episode 47: Market Analysis')")

            # Artist
            artist = tags.get('artist', '')
            if 'finance hour' in artist.lower():
                score += 1.5
                feedback.append(f"+ ID3 Artist: '{artist}'")
            elif artist:
                score += 0.5
                feedback.append(f"~ ID3 Artist: '{artist}' (expected 'The Finance Hour')")
            else:
                feedback.append("x ID3 Artist: Missing")

            # Album
            album = tags.get('album', '')
            if 'season 3' in album.lower():
                score += 1.0
                feedback.append(f"+ ID3 Album: '{album}'")
            elif album:
                score += 0.5
                feedback.append(f"~ ID3 Album: '{album}' (expected 'Season 3')")
            else:
                feedback.append("x ID3 Album: Missing")

            # Track
            track = tags.get('track', '')
            if '47' in str(track):
                score += 1.0
                feedback.append(f"+ ID3 Track: {track}")
            else:
                feedback.append(f"x ID3 Track: '{track}' (expected 47)")
        else:
            feedback.append("x Distribution MP3: File not found or empty")

        # --- Verify Highlight Clip ---
        highlight_path = os.path.join(output_dir, highlight_name)
        try:
            copy_from_env(f'/home/ga/Music/podcast_output/{highlight_name}', highlight_path)
            files_in_correct_dir += 1
        except Exception:
            try:
                copy_from_env('/tmp/podcast_output/' + highlight_name, highlight_path)
            except Exception:
                feedback.append(f"x Highlight clip: {highlight_name} not found")
                highlight_path = None

        if highlight_path and os.path.exists(highlight_path) and os.path.getsize(highlight_path) > 500:
            score += 1.0
            feedback.append("+ Highlight clip: File exists")

            # Check duration (~15s)
            dur = _get_audio_duration(highlight_path)
            if abs(dur - HIGHLIGHT_DURATION) <= 2.0:
                score += 2.0
                feedback.append(f"+ Highlight clip: Duration {dur:.1f}s (expected ~{HIGHLIGHT_DURATION}s)")
            elif 10.0 <= dur <= 20.0:
                score += 1.0
                feedback.append(f"~ Highlight clip: Duration {dur:.1f}s (acceptable range)")
            else:
                feedback.append(f"x Highlight clip: Duration {dur:.1f}s (expected ~{HIGHLIGHT_DURATION}s)")

            # Check MP3 format
            ainfo = get_audio_info(highlight_path)
            if ainfo.get('codec', '').lower() == 'mp3':
                score += 1.0
                feedback.append("+ Highlight clip: MP3 format")

            # Wrong-target gate: not the full episode
            if dur > 50:
                score -= 2.0
                feedback.append("!! Highlight clip: Duration suggests full episode, not excerpt")
            else:
                score += 2.0
                feedback.append("+ Highlight clip: Correct length (not full episode)")
        else:
            feedback.append("x Highlight clip: File not found or empty")

        # --- Check correct directory ---
        if files_in_correct_dir >= 3:
            score += 2.0
            feedback.append("+ Output directory: All files in /home/ga/Music/podcast_output/")
        elif files_in_correct_dir >= 1:
            score += 1.0
            feedback.append(f"~ Output directory: {files_in_correct_dir}/3 files in correct location")

        # --- Calculate final result ---
        score = max(0, score)  # Floor at 0
        pct = int(score / max_score * 100)
        passed = pct >= 55

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
