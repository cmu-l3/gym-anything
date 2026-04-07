#!/usr/bin/env python3
"""
Verifier for stock footage watermark catalog task.

Evaluation criteria (100 pts total, Pass = 55+):
- Preview Videos (30 pts): 3 videos exist (6), 1280x720 (9), ~15s (9), H.264 (6)
- Thumbnails (12 pts): 3 images exist/valid size (6), >=640px width (6)
- Watermark (15 pts): VLM detects text watermark on the 3 extracted frames (5/ea)
- Timecode (9 pts): VLM detects timecode on the 3 extracted frames (3/ea)
- Catalog JSON (19 pts): Array of 3 with all required keys (10), values match files (9)
- Directory (5 pts): Output files saved in correct directory
- Anti-gaming (10 pts): Output files created after task started
"""

import json
import os
import tarfile
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, image=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image)
        if result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None

def verify_stock_footage_watermark_catalog(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0.0
    feedback = []
    
    # 1. Copy and extract results tar archive from container
    temp_tar = tempfile.NamedTemporaryFile(delete=False, suffix='.tar.gz')
    extract_dir = tempfile.mkdtemp(prefix='vlc_verify_')
    try:
        copy_from_env("/tmp/task_result.tar.gz", temp_tar.name)
        with tarfile.open(temp_tar.name, "r:gz") as tar:
            tar.extractall(path=extract_dir)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to extract results: {e}"}
    finally:
        if os.path.exists(temp_tar.name):
            os.unlink(temp_tar.name)

    out_dir = os.path.join(extract_dir, 'previews_output')
    if not os.path.exists(out_dir):
        return {"passed": False, "score": 0, "feedback": "No output directory found. Did the agent save to /home/ga/Videos/previews/?"}

    # 2. Load pre-dumped media info and file statistics
    media_info = {}
    file_stats = {}
    try:
        with open(os.path.join(out_dir, 'media_info.json'), 'r') as f:
            media_info = json.load(f)
        with open(os.path.join(out_dir, 'file_stats.json'), 'r') as f:
            file_stats = json.load(f)
    except:
        pass

    task_start_time = file_stats.get('task_start_time', 0)
    all_created_during_task = True

    clips = [
        'aerial_landscape_001',
        'nature_wildlife_002',
        'urban_timelapse_003'
    ]

    # 3. Check Preview Videos (Max 30 pts)
    for clip in clips:
        pname = f'preview_{clip}.mp4'
        if pname in media_info and pname in file_stats:
            score += 2
            feedback.append(f"+ Video exists: {pname}")
            
            mtime = file_stats[pname].get('mtime', 0)
            if mtime <= task_start_time and task_start_time > 0:
                all_created_during_task = False
            
            info = media_info[pname]
            
            # Check Codec (H.264)
            streams = info.get('streams', [])
            if streams:
                codec = streams[0].get('codec_name', '').lower()
                if 'h264' in codec or 'avc' in codec:
                    score += 2
            
            # Check Resolution (1280x720)
            if streams:
                w = int(streams[0].get('width', 0))
                h = int(streams[0].get('height', 0))
                if w == 1280 and h == 720:
                    score += 3
                else:
                    feedback.append(f"  - Resolution incorrect for {pname}: {w}x{h}")

            # Check Duration (~15 seconds)
            fmt = info.get('format', {})
            duration = float(fmt.get('duration', 0))
            if 13 <= duration <= 17:
                score += 3
            else:
                feedback.append(f"  - Duration incorrect for {pname}: {duration:.1f}s")
        else:
            feedback.append(f"x Missing video: {pname}")
            all_created_during_task = False

    # 4. Check Thumbnails (Max 12 pts)
    for clip in clips:
        tname = f'thumb_{clip}.png'
        if tname in media_info and tname in file_stats:
            size = file_stats[tname].get('size', 0)
            if size > 5000:
                score += 2
                feedback.append(f"+ Thumbnail valid: {tname}")
            else:
                feedback.append(f"  - Thumbnail too small/corrupt: {tname}")
            
            info = media_info[tname]
            streams = info.get('streams', [])
            if streams:
                w = int(streams[0].get('width', 0))
                if w >= 640:
                    score += 2
        else:
            feedback.append(f"x Missing thumbnail: {tname}")

    # 5. VLM Verification for Watermark and Timecode on extracted frames (Max 24 pts)
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        prompt = """Analyze this frame extracted from a stock footage preview video.
1. Does it contain a visible text watermark overlay (e.g., the word 'PREVIEW' or similar prominent overlay text designed to protect the footage)?
2. Does it contain a timecode, timer, or running counter (typically numbers like HH:MM:SS, 00:00:05, or seconds visible in the frame, often in a corner)?

Respond strictly in JSON format:
{
    "has_watermark": true/false,
    "has_timecode": true/false,
    "confidence": "high/medium/low"
}"""
        for clip in clips:
            frame_name = f'frame_preview_{clip}.mp4.jpg'
            frame_path = os.path.join(out_dir, frame_name)
            if os.path.exists(frame_path):
                parsed = _vlm_query(query_vlm, prompt, image=frame_path)
                if parsed:
                    if parsed.get('has_watermark'):
                        score += 5
                        feedback.append(f"+ VLM: Watermark detected on {clip}")
                    else:
                        feedback.append(f"x VLM: No watermark on {clip}")
                        
                    if parsed.get('has_timecode'):
                        score += 3
                        feedback.append(f"+ VLM: Timecode detected on {clip}")
                    else:
                        feedback.append(f"x VLM: No timecode on {clip}")
            else:
                feedback.append(f"x VLM: Preview frame not extracted for {clip}")

    # 6. Check Catalog JSON (Max 19 pts)
    cat_path = os.path.join(out_dir, 'catalog.json')
    if os.path.exists(cat_path):
        try:
            with open(cat_path, 'r') as f:
                cat = json.load(f)
            
            if isinstance(cat, list) and len(cat) == 3:
                has_all_fields = True
                matches = 0
                req_fields = ['source_filename', 'preview_filename', 'thumbnail_filename', 
                              'source_duration_seconds', 'preview_duration_seconds', 
                              'preview_resolution', 'preview_file_size_bytes']
                for entry in cat:
                    if not all(k in entry for k in req_fields):
                        has_all_fields = False
                    
                    pname = entry.get('preview_filename', '')
                    if pname in file_stats:
                        actual_size = file_stats[pname].get('size', 0)
                        rep_size = entry.get('preview_file_size_bytes', 0)
                        if isinstance(rep_size, (int, float)) and actual_size > 0:
                            if abs(rep_size - actual_size) / actual_size < 0.2:
                                matches += 1
                
                if has_all_fields:
                    score += 10
                    feedback.append(f"+ Catalog structure valid (array of 3 with all keys)")
                else:
                    feedback.append(f"x Catalog missing required fields")
                
                if matches > 0:
                    points = matches * 3
                    score += points
                    feedback.append(f"+ Catalog metadata accuracy: ({matches}/3) file sizes matched reality")
            else:
                feedback.append(f"x Catalog is not an array of 3 items")
        except:
            feedback.append(f"x Catalog JSON invalid format")
    else:
        feedback.append(f"x Catalog JSON missing")

    # 7. Anti-gaming checks (Max 10 pts)
    if all_created_during_task:
        score += 10
        feedback.append(f"+ All outputs generated during task window")
    else:
        feedback.append(f"x Some files created before task start")
        
    # 8. Directory validation (Max 5 pts)
    files_in_dir = [f for f in os.listdir(out_dir) if f.startswith('preview_') or f.startswith('thumb_') or f == 'catalog.json']
    if len(files_in_dir) >= 7:
        score += 5
        feedback.append(f"+ Output directory correctly populated")

    passed = score >= 55.0

    return {
        "passed": passed,
        "score": min(100.0, score),
        "feedback": "\n".join(feedback)
    }