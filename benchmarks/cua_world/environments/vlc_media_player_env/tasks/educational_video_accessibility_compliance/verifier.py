import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from utils.vlc_verification_utils import (
    get_video_info, verify_snapshot_exists, verify_image_quality
)


def _has_subtitle_stream(filepath):
    """Check if video file has a separate subtitle stream."""
    try:
        cmd = [
            'ffprobe', '-v', 'error',
            '-select_streams', 's',
            '-show_entries', 'stream=codec_type',
            '-of', 'json', filepath
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            return len(data.get('streams', [])) > 0
    except Exception:
        pass
    return False


def _validate_srt(filepath):
    """Validate SRT subtitle file and count entries."""
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()

        # SRT pattern: number, timestamp line, text
        # Pattern: digit(s) followed by timestamp line "HH:MM:SS,mmm --> HH:MM:SS,mmm"
        timestamp_pattern = r'\d+\s*\n\s*\d{1,2}:\d{2}:\d{2}[,\.]\d{2,3}\s*-->\s*\d{1,2}:\d{2}:\d{2}[,\.]\d{2,3}'
        entries = re.findall(timestamp_pattern, content)
        return len(entries)
    except Exception:
        return 0


def verify_educational_video_accessibility_compliance(traj, env_info, task_info):
    copy_from_env = env_info["copy_from_env"]
    """
    Verify educational video accessibility compliance task.

    Criteria (26 points total, pass threshold = 55%):
    - SRT caption file (5 points):
      - File exists: 1 point
      - Valid SRT format: 1 point
      - At least 12 entries: 1.5 points (16+ = 1.5, 8+ = 1.0, 4+ = 0.5)
      - Contains key lecture terms: 1.5 points
    - Hardsubbed video (6 points):
      - File exists and valid: 1 point
      - No separate subtitle stream: 2 points
      - Duration matches original (±3s): 2 points
      - Resolution 1920x1080: 1 point
    - Low-bandwidth version (5 points):
      - File exists: 1 point
      - Resolution ≤854x480: 2 points
      - File size smaller than original: 2 points
    - Section thumbnails (6 points):
      - At least 2 thumbnails: 2 points
      - All 4 thumbnails: +2 points
      - Thumbnails >10KB: 2 points
    - Deliverables manifest (4 points):
      - Valid JSON: 1 point
      - Lists all deliverable categories: 2 points
      - Contains file size info: 1 point
    """
    feedback = []
    score = 0.0
    max_score = 26.0
    temp_dirs = []

    ORIGINAL_DURATION = 90.0
    DURATION_TOLERANCE = 3.0

    try:
        output_dir = tempfile.mkdtemp(prefix='vlc_verify_acc_')
        temp_dirs.append(output_dir)

        # --- Verify SRT caption file ---
        srt_path = os.path.join(output_dir, 'lecture_captions.srt')
        try:
            copy_from_env('/home/ga/Videos/accessible_output/lecture_captions.srt', srt_path)
        except Exception:
            # Try /tmp fallback
            try:
                copy_from_env('/tmp/accessible_output/lecture_captions.srt', srt_path)
            except Exception:
                srt_path = None

        if srt_path and os.path.exists(srt_path) and os.path.getsize(srt_path) > 50:
            score += 1.0
            feedback.append("+ SRT captions: File exists")

            entry_count = _validate_srt(srt_path)
            if entry_count > 0:
                score += 1.0
                feedback.append(f"+ SRT format: Valid ({entry_count} entries)")

                if entry_count >= 16:
                    score += 1.5
                    feedback.append(f"+ Caption coverage: {entry_count} entries (comprehensive)")
                elif entry_count >= 8:
                    score += 1.0
                    feedback.append(f"~ Caption coverage: {entry_count} entries (adequate)")
                elif entry_count >= 4:
                    score += 0.5
                    feedback.append(f"x Caption coverage: Only {entry_count} entries (minimal)")
                else:
                    feedback.append(f"x Caption coverage: Only {entry_count} entries (insufficient)")
            else:
                feedback.append("x SRT format: Invalid or no entries found")

            # Check for lecture content keywords
            try:
                with open(srt_path, 'r', encoding='utf-8', errors='replace') as f:
                    srt_text = f.read().lower()
                keywords = ['data science', 'statistical', 'probability', 'hypothesis',
                           'confidence', 'regression', 'machine learning', 'distribution',
                           'lecture', 'welcome', 'chapter', 'textbook']
                found_kw = sum(1 for kw in keywords if kw in srt_text)
                if found_kw >= 4:
                    score += 1.5
                    feedback.append(f"+ Caption content: {found_kw} lecture terms found")
                elif found_kw >= 2:
                    score += 0.75
                    feedback.append(f"~ Caption content: {found_kw} lecture terms (partial)")
                else:
                    feedback.append(f"x Caption content: {found_kw} lecture terms found (expected 4+)")
            except Exception:
                feedback.append("x Caption content: Could not read SRT text")
        else:
            feedback.append("x SRT captions: Not found")

        # --- Verify hardsubbed video ---
        hs_path = os.path.join(output_dir, 'lecture_hardsubbed.mp4')
        try:
            copy_from_env('/home/ga/Videos/accessible_output/lecture_hardsubbed.mp4', hs_path)
        except Exception:
            try:
                copy_from_env('/tmp/accessible_output/lecture_hardsubbed.mp4', hs_path)
            except Exception:
                hs_path = None

        if hs_path and os.path.exists(hs_path) and os.path.getsize(hs_path) > 10000:
            score += 1.0
            feedback.append("+ Hardsubbed video: File exists")

            info = get_video_info(hs_path)

            # No separate subtitle stream (burned in)
            has_subs = _has_subtitle_stream(hs_path)
            if not has_subs:
                score += 2.0
                feedback.append("+ Hardsubbed video: No separate subtitle stream (properly burned)")
            else:
                feedback.append("x Hardsubbed video: Contains separate subtitle stream (not burned in)")

            # Duration check
            dur = info.get('duration', 0)
            if abs(dur - ORIGINAL_DURATION) <= DURATION_TOLERANCE:
                score += 2.0
                feedback.append(f"+ Hardsubbed video: Duration {dur:.1f}s (matches original)")
            else:
                feedback.append(f"x Hardsubbed video: Duration {dur:.1f}s (expected ~{ORIGINAL_DURATION}s)")

            # Resolution check
            w = info.get('width', 0)
            h = info.get('height', 0)
            if w == 1920 and h == 1080:
                score += 1.0
                feedback.append(f"+ Hardsubbed video: Resolution {w}x{h}")
            else:
                feedback.append(f"x Hardsubbed video: Resolution {w}x{h} (expected 1920x1080)")
        else:
            feedback.append("x Hardsubbed video: Not found")

        # --- Verify low-bandwidth version ---
        lb_path = os.path.join(output_dir, 'lecture_lowband.mp4')
        try:
            copy_from_env('/home/ga/Videos/accessible_output/lecture_lowband.mp4', lb_path)
        except Exception:
            try:
                copy_from_env('/tmp/accessible_output/lecture_lowband.mp4', lb_path)
            except Exception:
                lb_path = None

        if lb_path and os.path.exists(lb_path) and os.path.getsize(lb_path) > 5000:
            score += 1.0
            feedback.append("+ Low-bandwidth video: File exists")

            info = get_video_info(lb_path)
            w = info.get('width', 0)
            h = info.get('height', 0)

            if h <= 480 and w <= 854:
                score += 2.0
                feedback.append(f"+ Low-bandwidth: Resolution {w}x{h} (within 480p)")
            elif h <= 720:
                score += 1.0
                feedback.append(f"~ Low-bandwidth: Resolution {w}x{h} (reduced but not 480p)")
            else:
                feedback.append(f"x Low-bandwidth: Resolution {w}x{h} (expected ≤854x480)")

            # File size comparison
            lb_size = os.path.getsize(lb_path)
            # Get original size for comparison
            orig_td = tempfile.mkdtemp(prefix='vlc_verify_orig_')
            temp_dirs.append(orig_td)
            orig_path = os.path.join(orig_td, 'original.mp4')
            try:
                copy_from_env('/home/ga/Videos/lecture_recording.mp4', orig_path)
                if os.path.exists(orig_path):
                    orig_size = os.path.getsize(orig_path)
                    if lb_size < orig_size * 0.8:
                        score += 2.0
                        feedback.append(f"+ Low-bandwidth: {lb_size//1024}KB vs original {orig_size//1024}KB (smaller)")
                    elif lb_size < orig_size:
                        score += 1.0
                        feedback.append(f"~ Low-bandwidth: {lb_size//1024}KB vs original {orig_size//1024}KB (marginally smaller)")
                    else:
                        feedback.append(f"x Low-bandwidth: {lb_size//1024}KB >= original {orig_size//1024}KB")
            except Exception:
                # Can't compare, give partial credit for resolution
                score += 1.0
                feedback.append("~ Low-bandwidth: Could not compare file sizes")
        else:
            feedback.append("x Low-bandwidth video: Not found")

        # --- Verify section thumbnails ---
        thumb_count = 0
        thumb_valid = 0
        for i in range(1, 5):
            thumb_name = f'section_{i}.png'
            thumb_path = os.path.join(output_dir, thumb_name)
            try:
                copy_from_env(f'/home/ga/Videos/accessible_output/{thumb_name}', thumb_path)
            except Exception:
                # Try jpg
                thumb_name_jpg = f'section_{i}.jpg'
                try:
                    copy_from_env(f'/home/ga/Videos/accessible_output/{thumb_name_jpg}', thumb_path)
                except Exception:
                    try:
                        copy_from_env(f'/tmp/accessible_output/{thumb_name}', thumb_path)
                    except Exception:
                        continue

            if os.path.exists(thumb_path) and os.path.getsize(thumb_path) > 1000:
                thumb_count += 1
                if os.path.getsize(thumb_path) > 10240:
                    thumb_valid += 1

        if thumb_count >= 4:
            score += 4.0
            feedback.append(f"+ Thumbnails: All 4 section thumbnails found")
        elif thumb_count >= 2:
            score += 2.0
            feedback.append(f"~ Thumbnails: {thumb_count}/4 section thumbnails found")
        elif thumb_count >= 1:
            score += 1.0
            feedback.append(f"x Thumbnails: Only {thumb_count}/4 found")
        else:
            feedback.append("x Thumbnails: No section thumbnails found")

        if thumb_valid >= 2:
            score += 2.0
            feedback.append(f"+ Thumbnail quality: {thumb_valid} thumbnails >10KB")
        elif thumb_valid >= 1:
            score += 1.0
            feedback.append(f"~ Thumbnail quality: {thumb_valid} thumbnails >10KB")

        # --- Verify deliverables manifest ---
        manifest_path = os.path.join(output_dir, 'manifest.json')
        try:
            copy_from_env('/home/ga/Videos/accessible_output/manifest.json', manifest_path)
        except Exception:
            try:
                copy_from_env('/tmp/accessible_output/manifest.json', manifest_path)
            except Exception:
                manifest_path = None

        if manifest_path and os.path.exists(manifest_path):
            try:
                with open(manifest_path, 'r') as f:
                    manifest = json.load(f)
                score += 1.0
                feedback.append("+ Manifest: Valid JSON")

                # Check if it lists deliverable categories
                manifest_str = json.dumps(manifest).lower()
                categories_found = 0
                for cat_keyword in ['srt', 'caption', 'hardsubbed', 'burn', 'lowband', 'low-bandwidth',
                                    'mobile', '480', 'thumbnail', 'section']:
                    if cat_keyword in manifest_str:
                        categories_found += 1
                        break  # Count once per category group

                # More granular category check
                has_caption = any(kw in manifest_str for kw in ['srt', 'caption', 'subtitle'])
                has_hardsub = any(kw in manifest_str for kw in ['hardsubbed', 'burn', 'hardsub'])
                has_lowband = any(kw in manifest_str for kw in ['lowband', 'low-bandwidth', 'mobile', '480p'])
                has_thumb = any(kw in manifest_str for kw in ['thumbnail', 'section_', 'snapshot'])

                cat_count = sum([has_caption, has_hardsub, has_lowband, has_thumb])
                if cat_count >= 3:
                    score += 2.0
                    feedback.append(f"+ Manifest: Lists {cat_count}/4 deliverable categories")
                elif cat_count >= 2:
                    score += 1.0
                    feedback.append(f"~ Manifest: Lists {cat_count}/4 deliverable categories")
                else:
                    feedback.append(f"x Manifest: Only {cat_count}/4 categories found")

                # Check for file size info
                if 'size' in manifest_str or 'bytes' in manifest_str:
                    score += 1.0
                    feedback.append("+ Manifest: Contains file size information")
                else:
                    feedback.append("x Manifest: Missing file size information")

            except json.JSONDecodeError:
                feedback.append("x Manifest: Invalid JSON format")
        else:
            feedback.append("x Manifest: Not found")

        # --- Calculate final result ---
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
