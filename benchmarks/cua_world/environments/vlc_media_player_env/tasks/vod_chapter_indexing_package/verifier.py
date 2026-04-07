#!/usr/bin/env python3
"""
Verifier for VOD Chapter Indexing Package Task
Tests the robustness of the metadata extraction, structure, and integrity of media files.
"""

import json
import tempfile
import os
import logging
from difflib import SequenceMatcher

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def similar(a, b):
    """Returns ratio of similarity between two strings."""
    if not isinstance(a, str) or not isinstance(b, str):
        return 0.0
    return SequenceMatcher(None, a.lower().strip(), b.lower().strip()).ratio()


def verify_vod_chapter_indexing_package(traj, env_info, task_info):
    """
    Scoring logic utilizing exact parameters defined in the prompt.
    Max Score: 100. Pass threshold: 60.
    Gate criteria: Output video MUST possess 6 chapters.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vod_package_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []

    task_start = result.get('task_start_time', 0)
    video = result.get('video', {})
    thumbnails = result.get('thumbnails', [])
    index = result.get('chapter_index', {})
    sprite = result.get('sprite', {})

    expected_titles = [
        "Origins of Computing",
        "The Mainframe Era",
        "Personal Computing Revolution",
        "The Internet Age",
        "Mobile Computing",
        "Artificial Intelligence"
    ]

    # --- 1. Chaptered Video Evaluation (30 pts max) ---
    video_exists = video.get('exists', False)
    chapters_detected = False

    if video_exists:
        duration = video.get('duration', 0)
        if 88 <= duration <= 92:
            score += 5
            feedback_parts.append("Chaptered video exists with correct duration (~90s)")
        else:
            feedback_parts.append(f"Chaptered video duration anomaly ({duration}s)")

        chapters_list = video.get('chapters_data', {}).get('chapters', [])
        chapters_detected = (len(chapters_list) == 6)

        if chapters_detected:
            score += 10
            feedback_parts.append("Exactly 6 video chapters detected")

            correct_titles = 0
            correct_times = 0

            for i, ch in enumerate(chapters_list):
                if i >= 6: break

                tags = ch.get('tags', {})
                title = tags.get('title', '')
                if similar(title, expected_titles[i]) > 0.8:
                    correct_titles += 1

                start = float(ch.get('start_time', 0))
                end = float(ch.get('end_time', 0))
                expected_start = i * 15
                expected_end = (i + 1) * 15

                if abs(start - expected_start) <= 2 and abs(end - expected_end) <= 2:
                    correct_times += 1

            if correct_titles >= 4:
                score += 8
                feedback_parts.append(f"Chapter titles accurately embedded ({correct_titles}/6)")
            else:
                feedback_parts.append(f"Chapter titles mostly incorrect ({correct_titles}/6)")

            if correct_times >= 4:
                score += 7
                feedback_parts.append(f"Chapter timestamps accurate ({correct_times}/6)")
            else:
                feedback_parts.append(f"Chapter timestamps mostly inaccurate ({correct_times}/6)")
        else:
            feedback_parts.append(f"Detected {len(chapters_list)} chapters, required 6 (GATE FAILURE)")
    else:
        feedback_parts.append("Chaptered video delivery missing")


    # --- 2. Thumbnails Evaluation (18 pts max) ---
    thumbs_exist = sum(1 for t in thumbnails if t.get('exists'))
    if thumbs_exist == 6:
        large_thumbs = sum(1 for t in thumbnails if t.get('size', 0) > 10000)
        if large_thumbs == 6:
            score += 8
            feedback_parts.append("6 valid thumbnails > 10KB found")

            res_ok = sum(1 for t in thumbnails if t.get('width', 0) >= 320 and t.get('height', 0) >= 180)
            if res_ok == 6:
                score += 4
                feedback_parts.append("All thumbnails meet minimum resolution (320x180)")
            else:
                feedback_parts.append(f"Subpar thumbnail resolutions ({res_ok}/6 correct)")

            # Visual distinctness proxy check via differing file sizes 
            sizes = [t.get('size', 0) for t in thumbnails]
            unique_sizes = len(set([round(s/100) for s in sizes])) # unique inside 100 byte buckets
            if unique_sizes >= 4:
                score += 6
                feedback_parts.append("Thumbnails contain visually distinct frames")
            else:
                feedback_parts.append("Thumbnails are suspiciously identical in size")
        else:
            feedback_parts.append(f"{thumbs_exist} thumbnails generated but {6 - large_thumbs} are <10KB")
    else:
        feedback_parts.append(f"Incomplete thumbnail generation ({thumbs_exist}/6)")


    # --- 3. Chapter Index JSON (20 pts max) ---
    if index.get('exists'):
        content = index.get('content', {})
        if isinstance(content, list) and len(content) == 6:
            score += 6
            feedback_parts.append("Index structure is valid JSON containing 6 entries")

            idx_titles_correct = 0
            idx_times_correct = 0
            idx_metadata_complete = 0

            for i, ch_obj in enumerate(content):
                if not isinstance(ch_obj, dict): continue

                t = ch_obj.get('title', '')
                if similar(t, expected_titles[i]) > 0.8:
                    idx_titles_correct += 1

                try:
                    s = float(ch_obj.get('start_time_sec', -1))
                    e = float(ch_obj.get('end_time_sec', -1))
                    if abs(s - i*15) <= 2 and abs(e - (i+1)*15) <= 2:
                        idx_times_correct += 1
                except (ValueError, TypeError):
                    pass

                if 'description' in ch_obj and 'thumbnail_file' in ch_obj:
                    if len(str(ch_obj['description'])) > 5 and len(str(ch_obj['thumbnail_file'])) > 5:
                        idx_metadata_complete += 1

            if idx_titles_correct == 6:
                score += 5
                feedback_parts.append("JSON index titles are accurate")
            else:
                feedback_parts.append(f"JSON index titles mismatched ({idx_titles_correct}/6)")

            if idx_times_correct == 6:
                score += 5
                feedback_parts.append("JSON index timestamps are accurate")
            else:
                feedback_parts.append(f"JSON index timestamps anomalous ({idx_times_correct}/6)")

            if idx_metadata_complete == 6:
                score += 4
                feedback_parts.append("JSON metadata is complete")
            else:
                feedback_parts.append(f"JSON metadata incomplete ({idx_metadata_complete}/6)")
        else:
            feedback_parts.append("Chapter index JSON structure invalid or item count != 6")
    else:
        feedback_parts.append("Chapter index JSON missing")


    # --- 4. Scrub Preview Sprite Sheet (22 pts max) ---
    if sprite.get('exists'):
        if sprite.get('size', 0) > 20000:
            score += 6
            feedback_parts.append("Sprite sheet exists and file weight is plausible")

            w, h = sprite.get('width', 0), sprite.get('height', 0)
            if 860 <= w <= 1060 and 240 <= h <= 300:
                score += 8
                feedback_parts.append(f"Sprite sheet dimensions match expected grid ({w}x{h})")
            else:
                feedback_parts.append(f"Sprite sheet dimensions outside tolerances ({w}x{h})")

            # Solid color sheets weigh considerably less than grids with actual images.
            if sprite.get('size', 0) > 30000:
                score += 8
                feedback_parts.append("Sprite sheet exhibits appropriate visual variety (via file size proxy)")
            else:
                feedback_parts.append("Sprite sheet might lack visual variety (borderline file size)")
        else:
            feedback_parts.append("Sprite sheet file too small (< 20KB)")
    else:
        feedback_parts.append("Scrub preview sprite sheet missing")


    # --- 5. Anti-Gaming Metrics (10 pts max) ---
    valid_mtimes = 0
    if video_exists and video.get('mtime', 0) >= task_start: valid_mtimes += 1
    if index.get('exists') and index.get('mtime', 0) >= task_start: valid_mtimes += 1
    if sprite.get('exists') and sprite.get('mtime', 0) >= task_start: valid_mtimes += 1

    if valid_mtimes >= 2:
        score += 5
        feedback_parts.append("Deliverables synthesized during active task timeframe")
    else:
        feedback_parts.append("Deliverables appear pre-existing (Anti-gaming check triggered)")

    if video_exists:
        source_size = 2250000 # Appx fallback
        # If the size changed significantly or we successfully scraped new chapters
        if abs(video.get('size', 0) - source_size) > 5000 or chapters_detected:
            score += 5
            feedback_parts.append("Video file differs structurally from source media")
        else:
            feedback_parts.append("Video file identical to source media (Anti-gaming check triggered)")


    # Final Pass Logic
    passed = (score >= 60) and chapters_detected

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "chapters_detected": chapters_detected,
            "thumbnails_found": thumbs_exist
        }
    }