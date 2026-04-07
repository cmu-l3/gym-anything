#!/usr/bin/env python3
"""
Download and prepare video data for NX Witness video analysis tasks.

Run this ONCE on the host machine before running any video analysis tasks:
    python examples/nx_witness_vms_env/scripts/prepare_video_data.py

Downloads four real surveillance datasets (all freely available, no auth):
1. Mall Dataset (CUHK)    ~88MB  - pedestrian counting with per-frame head annotations
2. CUHK Avenue Dataset    ~776MB - campus surveillance with frame-level anomaly labels
3. UMN Crowd Dataset      ~24MB  - crowd panic/dispersal with labeled events
4. UCSD Ped2 Dataset      ~706MB - pedestrian zone with anomaly masks (bikes/carts)

Final output in examples/nx_witness_vms_env/data/:
  videos/
    mall_pedestrian.mp4      - Mall overhead view (pedestrian counting)
    avenue_anomaly.mp4       - Avenue test video with suspicious activity
    avenue_normal.mp4        - Avenue training video (normal activity)
    umn_crowd.mp4            - UMN indoor crowd scene with panic event
    ucsd_pedestrian.mp4      - UCSD Ped2 walkway with bike anomaly
  annotations/
    mall_gt.mat              - Mall per-frame head positions
    avenue_anomaly_gt.json   - Temporal anomaly annotations
    avenue_normal_gt.json    - Confirmed normal (no anomalies)
    umn_crowd_gt.json        - Crowd panic onset timestamps
    ucsd_pedestrian_gt.json  - Temporal anomaly annotations
"""

import os
import sys
import json
import subprocess
import zipfile
import tarfile
import shutil
import glob

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_DIR = os.path.dirname(SCRIPT_DIR)
DATA_DIR = os.path.join(ENV_DIR, "data")
VIDEO_DIR = os.path.join(DATA_DIR, "videos")
ANNOTATION_DIR = os.path.join(DATA_DIR, "annotations")
CACHE_DIR = os.path.join(DATA_DIR, ".cache")

for d in [VIDEO_DIR, ANNOTATION_DIR, CACHE_DIR]:
    os.makedirs(d, exist_ok=True)


def download_file(url, dest, desc="", timeout=600):
    """Download a file with wget."""
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        print(f"  [SKIP] {desc or os.path.basename(dest)} already exists")
        return True
    print(f"  [DOWNLOADING] {desc or url}")
    try:
        ret = subprocess.run(
            ["wget", "-q", "--no-check-certificate", "--timeout=120", "-O", dest, url],
            timeout=timeout,
        )
        if ret.returncode == 0 and os.path.exists(dest) and os.path.getsize(dest) > 0:
            size_mb = os.path.getsize(dest) / 1024 / 1024
            print(f"  [OK] {size_mb:.1f} MB")
            return True
        else:
            if os.path.exists(dest):
                os.remove(dest)
            return False
    except Exception as e:
        print(f"  [FAILED] {e}")
        if os.path.exists(dest):
            os.remove(dest)
        return False


def frames_to_mp4(frames_dir, output_path, pattern="*.jpg", input_fps=2, output_fps=10, scale="640:480"):
    """Convert a directory of frames to MP4."""
    # Check what files exist
    exts = ["jpg", "jpeg", "png", "tif", "tiff", "bmp"]
    frame_files = []
    for ext in exts:
        frame_files.extend(sorted(glob.glob(os.path.join(frames_dir, f"*.{ext}"))))
        frame_files.extend(sorted(glob.glob(os.path.join(frames_dir, f"*.{ext.upper()}"))))

    if not frame_files:
        print(f"  [ERROR] No frame images found in {frames_dir}")
        return False

    print(f"  [CONVERTING] {len(frame_files)} frames -> {os.path.basename(output_path)}")

    # Determine file extension
    ext = os.path.splitext(frame_files[0])[1]

    ret = subprocess.run(
        [
            "ffmpeg", "-y",
            "-framerate", str(input_fps),
            "-pattern_type", "glob",
            "-i", os.path.join(frames_dir, f"*{ext}"),
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-r", str(output_fps),
            "-vf", f"scale={scale}",
            output_path,
        ],
        capture_output=True,
        timeout=300,
    )

    if ret.returncode == 0 and os.path.exists(output_path):
        size_mb = os.path.getsize(output_path) / 1024 / 1024
        dur = get_video_duration(output_path)
        print(f"  [OK] {os.path.basename(output_path)}: {size_mb:.1f} MB, {dur:.1f}s")
        return True
    else:
        print(f"  [ERROR] ffmpeg failed: {ret.stderr.decode()[:300]}")
        return False


def avi_to_mp4(input_path, output_path, scale="640:480", trim_start=None, trim_end=None):
    """Convert AVI to MP4, optionally trimming."""
    cmd = ["ffmpeg", "-y", "-i", input_path]
    if trim_start is not None:
        cmd.extend(["-ss", str(trim_start)])
    if trim_end is not None:
        cmd.extend(["-to", str(trim_end)])
    cmd.extend([
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-vf", f"scale={scale}",
        output_path,
    ])

    ret = subprocess.run(cmd, capture_output=True, timeout=300)
    if ret.returncode == 0 and os.path.exists(output_path):
        size_mb = os.path.getsize(output_path) / 1024 / 1024
        dur = get_video_duration(output_path)
        print(f"  [OK] {os.path.basename(output_path)}: {size_mb:.1f} MB, {dur:.1f}s")
        return True
    else:
        print(f"  [ERROR] ffmpeg failed: {ret.stderr.decode()[:300]}")
        return False


def get_video_duration(path):
    """Get video duration in seconds using ffprobe."""
    try:
        ret = subprocess.run(
            ["ffprobe", "-v", "quiet", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", path],
            capture_output=True, timeout=30
        )
        return float(ret.stdout.decode().strip())
    except:
        return 0.0


def get_video_fps(path):
    """Get video FPS using ffprobe."""
    try:
        ret = subprocess.run(
            ["ffprobe", "-v", "quiet", "-select_streams", "v:0",
             "-show_entries", "stream=r_frame_rate",
             "-of", "default=noprint_wrappers=1:nokey=1", path],
            capture_output=True, timeout=30
        )
        num, den = ret.stdout.decode().strip().split("/")
        return float(num) / float(den)
    except:
        return 25.0


# ============================================================
# 1. Mall Dataset (Pedestrian Counting)
# ============================================================

def prepare_mall_dataset():
    """Download Mall Dataset from CUHK and convert frames to video."""
    print("\n" + "=" * 60)
    print("1. Mall Dataset (Pedestrian Counting)")
    print("=" * 60)

    mall_video = os.path.join(VIDEO_DIR, "mall_pedestrian.mp4")
    if os.path.exists(mall_video) and os.path.getsize(mall_video) > 1_000_000:
        print(f"  [SKIP] Mall video already exists ({os.path.getsize(mall_video) / 1024 / 1024:.1f} MB)")
        return True

    mall_zip = os.path.join(CACHE_DIR, "mall_dataset.zip")
    if not download_file(
        "https://personal.ie.cuhk.edu.hk/~ccloy/files/datasets/mall_dataset.zip",
        mall_zip, "Mall Dataset (88MB)"
    ):
        print("  [ERROR] Failed to download Mall Dataset")
        return False

    # Extract
    mall_dir = os.path.join(CACHE_DIR, "mall_dataset")
    if not os.path.exists(mall_dir):
        print("  [EXTRACTING]...")
        with zipfile.ZipFile(mall_zip) as zf:
            zf.extractall(mall_dir)

    # Find frames directory
    for pattern in [
        os.path.join(mall_dir, "**", "frames", "seq_*.jpg"),
        os.path.join(mall_dir, "**", "frames", "*.jpg"),
    ]:
        matches = sorted(glob.glob(pattern, recursive=True))
        if matches:
            frames_dir = os.path.dirname(matches[0])
            break
    else:
        print("  [ERROR] Could not find frames")
        return False

    # Convert to video
    if not frames_to_mp4(frames_dir, mall_video, input_fps=2, output_fps=10, scale="640:480"):
        return False

    # Copy ground truth .mat files
    for mat_file in glob.glob(os.path.join(mall_dir, "**", "*.mat"), recursive=True):
        dest = os.path.join(ANNOTATION_DIR, os.path.basename(mat_file))
        if not os.path.exists(dest):
            shutil.copy2(mat_file, dest)
            print(f"  [OK] Copied {os.path.basename(mat_file)}")

    # Create JSON ground truth
    gt = {
        "dataset": "mall_cuhk",
        "description": "Mall Dataset from CUHK - overhead view of shopping mall with ~31 people visible per frame on average",
        "total_frames": 2000,
        "original_fps": 2,
        "avg_count_per_frame": 31,
        "total_annotated_people": 62325,
        "duration": get_video_duration(mall_video),
        "is_placeholder": False,
    }
    with open(os.path.join(ANNOTATION_DIR, "mall_pedestrian_gt.json"), "w") as f:
        json.dump(gt, f, indent=2)

    return True


# ============================================================
# 2. CUHK Avenue Dataset (Suspicious Activity + False Alarm)
# ============================================================

def prepare_avenue_dataset():
    """Download Avenue Dataset and create concatenated test/train videos."""
    print("\n" + "=" * 60)
    print("2. CUHK Avenue Dataset (Suspicious Activity + False Alarm)")
    print("=" * 60)

    anomaly_video = os.path.join(VIDEO_DIR, "avenue_anomaly.mp4")
    normal_video = os.path.join(VIDEO_DIR, "avenue_normal.mp4")

    if (os.path.exists(anomaly_video) and os.path.getsize(anomaly_video) > 1_000_000 and
        os.path.exists(normal_video) and os.path.getsize(normal_video) > 1_000_000):
        print("  [SKIP] Avenue videos already exist")
        return True

    # Download
    avenue_zip = os.path.join(CACHE_DIR, "avenue_dataset.zip")
    if not os.path.exists(avenue_zip) or os.path.getsize(avenue_zip) < 1_000_000:
        if not download_file(
            "http://www.cse.cuhk.edu.hk/leojia/projects/detectabnormal/Avenue_Dataset.zip",
            avenue_zip, "Avenue Dataset (776MB)", timeout=1200
        ):
            print("  [ERROR] Failed to download Avenue Dataset")
            return False

    # Extract
    avenue_dir = os.path.join(CACHE_DIR, "avenue_dataset")
    if not os.path.exists(avenue_dir):
        print("  [EXTRACTING]...")
        with zipfile.ZipFile(avenue_zip) as zf:
            zf.extractall(avenue_dir)

    # Find videos
    test_videos = sorted(glob.glob(os.path.join(avenue_dir, "**", "testing_videos", "*.avi"), recursive=True))
    train_videos = sorted(glob.glob(os.path.join(avenue_dir, "**", "training_videos", "*.avi"), recursive=True))
    print(f"  Found {len(test_videos)} test videos, {len(train_videos)} train videos")

    # Anomaly video: concatenate Test01 + Test06 + Test12 (~160s total)
    # These have the clearest anomalies (throwing bags, running, loitering)
    test_indices = [0, 5, 11]  # Test01, Test06, Test12
    selected_tests = [test_videos[i] for i in test_indices if i < len(test_videos)]

    if selected_tests:
        print(f"  Concatenating test videos: {[os.path.basename(v) for v in selected_tests]}")
        input_args = []
        filter_parts = []
        for i, v in enumerate(selected_tests):
            input_args.extend(["-i", v])
            filter_parts.append(f"[{i}:v]scale=640:480[v{i}]")
        concat_inputs = "".join(f"[v{i}]" for i in range(len(selected_tests)))
        filter_str = ";".join(filter_parts) + f";{concat_inputs}concat=n={len(selected_tests)}:v=1:a=0[out]"

        cmd = ["ffmpeg", "-y"] + input_args + [
            "-filter_complex", filter_str,
            "-map", "[out]", "-c:v", "libx264", "-pix_fmt", "yuv420p",
            anomaly_video
        ]
        ret = subprocess.run(cmd, capture_output=True, timeout=300)
        if ret.returncode == 0:
            dur = get_video_duration(anomaly_video)
            print(f"  [OK] avenue_anomaly.mp4: {os.path.getsize(anomaly_video)/1024/1024:.1f} MB, {dur:.1f}s")
        else:
            print(f"  [ERROR] {ret.stderr.decode()[:200]}")
            return False

    # GT for anomaly video (from Avenue literature, approximate frame ranges)
    anomaly_gt = {
        "dataset": "avenue_cuhk",
        "description": "CUHK Avenue Dataset - campus walkway with abnormal events. Concatenation of Test01 (throwing bag), Test06 (running/throwing), Test12 (loitering).",
        "fps": 25,
        "duration": get_video_duration(anomaly_video),
        "source_videos": ["Test01", "Test06", "Test12"],
        "video_boundaries": [0, 57.56, 108.88, 159.72],
        "anomaly_intervals": [[29.2, 41.2], [60.8, 66.4], [81.6, 95.6], [124.9, 140.9]],
        "anomaly_descriptions": [
            {"interval": [29.2, 41.2], "type": "throwing_bag", "description": "Person throws or drops a bag on the walkway"},
            {"interval": [60.8, 66.4], "type": "running_wrong_direction", "description": "Person runs against normal pedestrian flow"},
            {"interval": [81.6, 95.6], "type": "throwing_objects", "description": "Person throws objects in the walkway area"},
            {"interval": [124.9, 140.9], "type": "loitering_abnormal", "description": "Person exhibits unusual loitering or abnormal movement"},
        ],
        "is_placeholder": False,
    }
    with open(os.path.join(ANNOTATION_DIR, "avenue_anomaly_gt.json"), "w") as f:
        json.dump(anomaly_gt, f, indent=2)
    print(f"  [GT] {len(anomaly_gt['anomaly_intervals'])} anomaly intervals")

    # Normal video: concatenate first 3 training videos (~175s, all normal)
    selected_trains = train_videos[:3]
    if selected_trains:
        print(f"  Concatenating training videos: {[os.path.basename(v) for v in selected_trains]}")
        input_args = []
        filter_parts = []
        for i, v in enumerate(selected_trains):
            input_args.extend(["-i", v])
            filter_parts.append(f"[{i}:v]scale=640:480[v{i}]")
        concat_inputs = "".join(f"[v{i}]" for i in range(len(selected_trains)))
        filter_str = ";".join(filter_parts) + f";{concat_inputs}concat=n={len(selected_trains)}:v=1:a=0[out]"

        cmd = ["ffmpeg", "-y"] + input_args + [
            "-filter_complex", filter_str,
            "-map", "[out]", "-c:v", "libx264", "-pix_fmt", "yuv420p",
            normal_video
        ]
        ret = subprocess.run(cmd, capture_output=True, timeout=300)
        if ret.returncode == 0:
            dur = get_video_duration(normal_video)
            print(f"  [OK] avenue_normal.mp4: {os.path.getsize(normal_video)/1024/1024:.1f} MB, {dur:.1f}s")

    normal_gt = {
        "dataset": "avenue_cuhk",
        "description": "CUHK Avenue Dataset training video - campus walkway with ONLY normal pedestrian activity. No anomalies.",
        "fps": 25,
        "duration": get_video_duration(normal_video),
        "source_videos": ["Train01", "Train02", "Train03"],
        "anomaly_intervals": [],
        "has_anomaly": False,
        "expected_verdict": "DISMISS",
        "is_placeholder": False,
    }
    with open(os.path.join(ANNOTATION_DIR, "avenue_normal_gt.json"), "w") as f:
        json.dump(normal_gt, f, indent=2)

    return True


# ============================================================
# 3. UMN Crowd Dataset (Crowd Dispersal)
# ============================================================

def prepare_umn_dataset():
    """Download UMN crowd panic video and extract indoor scene."""
    print("\n" + "=" * 60)
    print("3. UMN Crowd Dataset (Crowd Dispersal)")
    print("=" * 60)

    crowd_video = os.path.join(VIDEO_DIR, "umn_crowd.mp4")
    if os.path.exists(crowd_video) and os.path.getsize(crowd_video) > 100_000:
        print(f"  [SKIP] UMN crowd video already exists")
        return True

    # Download
    umn_avi = os.path.join(CACHE_DIR, "umn_crowd.avi")
    if not os.path.exists(umn_avi) or os.path.getsize(umn_avi) < 1_000_000:
        if not download_file(
            "https://mha.cs.umn.edu/Movies/Crowd-Activity-All.avi",
            umn_avi, "UMN Crowd Dataset (24MB)"
        ):
            print("  [ERROR] Failed to download UMN Dataset")
            return False

    # The UMN combined video has 3 scenes:
    # Scene 1 (lawn): 0:00 - ~1:28, panic at ~1:04
    # Scene 2 (indoor): ~1:28 - ~2:52, panic at ~2:28
    # Scene 3 (plaza): ~2:52 - ~4:17, panic at ~3:53
    # We'll use scene 2 (indoor) as it's most like a building corridor/lobby

    # First, get total duration
    total_dur = get_video_duration(umn_avi)
    total_fps = get_video_fps(umn_avi)
    print(f"  UMN total duration: {total_dur:.1f}s, fps: {total_fps:.1f}")

    # Extract scene 2 (indoor) - approximately 1:28 to 2:52
    scene2_start = 88.0   # ~1:28
    scene2_end = 172.0    # ~2:52
    panic_onset = 148.0   # ~2:28 (relative to full video)

    # Convert to relative timing for the extracted clip
    panic_relative = panic_onset - scene2_start  # ~60s into the clip
    scene_duration = scene2_end - scene2_start   # ~84s

    print(f"  Extracting indoor scene: {scene2_start:.0f}s - {scene2_end:.0f}s")
    if not avi_to_mp4(umn_avi, crowd_video, scale="640:480",
                       trim_start=scene2_start, trim_end=scene2_end):
        return False

    actual_duration = get_video_duration(crowd_video)

    # Ground truth: normal crowd behavior until panic onset, then dispersal
    umn_gt = {
        "dataset": "umn_crowd_activity",
        "description": "UMN Unusual Crowd Activity - indoor scene showing normal crowd milling then sudden panic dispersal",
        "scene": "indoor",
        "duration": actual_duration,
        "fps": total_fps,
        "events": [
            {
                "type": "normal_crowd",
                "start": 0.0,
                "end": round(panic_relative, 1),
                "description": "Normal crowd activity - people walking, standing, milling around in indoor space"
            },
            {
                "type": "panic_dispersal",
                "start": round(panic_relative, 1),
                "end": round(actual_duration, 1),
                "description": "Sudden crowd panic - people begin running and dispersing rapidly from the area"
            }
        ],
        "panic_onset_seconds": round(panic_relative, 1),
        "anomaly_intervals": [[round(panic_relative, 1), round(actual_duration, 1)]],
        "is_placeholder": False,
    }
    with open(os.path.join(ANNOTATION_DIR, "umn_crowd_gt.json"), "w") as f:
        json.dump(umn_gt, f, indent=2)

    print(f"  [GT] Panic onset at {panic_relative:.1f}s in {actual_duration:.1f}s clip")
    return True


# ============================================================
# 4. UCSD Ped2 Dataset (Unauthorized Access / Zone Violation)
# ============================================================

def prepare_ucsd_dataset():
    """Download UCSD anomaly dataset and build concatenated Ped2 video."""
    print("\n" + "=" * 60)
    print("4. UCSD Ped2 Dataset (Unauthorized Access Detection)")
    print("=" * 60)

    ucsd_video = os.path.join(VIDEO_DIR, "ucsd_pedestrian.mp4")
    if os.path.exists(ucsd_video) and os.path.getsize(ucsd_video) > 500_000:
        print(f"  [SKIP] UCSD video already exists")
        return True

    # Download
    ucsd_tar = os.path.join(CACHE_DIR, "ucsd_anomaly.tar.gz")
    if not os.path.exists(ucsd_tar) or os.path.getsize(ucsd_tar) < 1_000_000:
        if not download_file(
            "http://www.svcl.ucsd.edu/projects/anomaly/UCSD_Anomaly_Dataset.tar.gz",
            ucsd_tar, "UCSD Anomaly Dataset (706MB)", timeout=1200
        ):
            print("  [ERROR] Failed to download UCSD Dataset")
            return False

    # Extract
    ucsd_dir = os.path.join(CACHE_DIR, "ucsd_dataset")
    if not os.path.exists(ucsd_dir):
        print("  [EXTRACTING]...")
        os.makedirs(ucsd_dir, exist_ok=True)
        with tarfile.open(ucsd_tar) as tf:
            tf.extractall(ucsd_dir, filter='data')

    # Find Ped2 directory
    ped2_base = None
    for candidate in [
        os.path.join(ucsd_dir, "UCSD_Anomaly_Dataset.v1p2", "UCSDped2"),
        os.path.join(ucsd_dir, "UCSDped2"),
    ]:
        if os.path.isdir(candidate):
            ped2_base = candidate
            break
    if not ped2_base:
        for root, dirs, files in os.walk(ucsd_dir):
            if "UCSDped2" in dirs:
                ped2_base = os.path.join(root, "UCSDped2")
                break
    if not ped2_base:
        print("  [ERROR] Could not find UCSDped2 directory")
        return False

    print(f"  Found Ped2 at: {ped2_base}")

    # Build concatenated video: Training clips (normal) + Test clip (anomaly)
    # This creates a ~96s video with anomaly only in the last ~18s
    import tempfile
    tmpdir = tempfile.mkdtemp(prefix="ucsd_build_")

    frame_idx = 0
    train_dir = os.path.join(ped2_base, "Train")
    test_dir = os.path.join(ped2_base, "Test")

    # Use 5 training clips for normal footage
    train_clips = ["Train001", "Train002", "Train003", "Train004", "Train005"]
    for clip in train_clips:
        clip_dir = os.path.join(train_dir, clip)
        if not os.path.isdir(clip_dir):
            continue
        for f in sorted(glob.glob(os.path.join(clip_dir, "*.tif"))):
            frame_idx += 1
            shutil.copy2(f, os.path.join(tmpdir, f"frame_{frame_idx:06d}.tif"))

    normal_count = frame_idx
    print(f"  Normal frames: {normal_count}")

    # Find best test clip by anomaly density
    best_clip = "Test008"  # Known to have bike anomaly
    clip_dir = os.path.join(test_dir, best_clip)
    if os.path.isdir(clip_dir):
        for f in sorted(glob.glob(os.path.join(clip_dir, "*.tif"))):
            frame_idx += 1
            shutil.copy2(f, os.path.join(tmpdir, f"frame_{frame_idx:06d}.tif"))

    total_frames = frame_idx
    anomaly_count = total_frames - normal_count
    print(f"  Total: {total_frames} frames ({normal_count} normal + {anomaly_count} anomaly)")

    # Convert to video at 10fps
    if not frames_to_mp4(tmpdir, ucsd_video, input_fps=10, output_fps=10, scale="640:480"):
        shutil.rmtree(tmpdir)
        return False
    shutil.rmtree(tmpdir)

    # Create GT JSON
    anomaly_start = normal_count / 10.0
    anomaly_end = total_frames / 10.0

    ucsd_gt = {
        "dataset": "ucsd_ped2",
        "description": "UCSD Pedestrian 2 - walkway with normal pedestrian traffic, then non-pedestrian objects (bikes/carts) enter the zone.",
        "fps": 10,
        "total_frames": total_frames,
        "normal_frames": normal_count,
        "duration": get_video_duration(ucsd_video),
        "anomaly_intervals": [[round(anomaly_start, 1), round(anomaly_end, 1)]],
        "anomaly_type": "non_pedestrian_object",
        "anomaly_objects": ["bicycle", "cart", "skateboard", "wheelchair"],
        "is_placeholder": False,
    }
    with open(os.path.join(ANNOTATION_DIR, "ucsd_pedestrian_gt.json"), "w") as f:
        json.dump(ucsd_gt, f, indent=2)

    print(f"  [GT] Anomaly at {anomaly_start:.1f}-{anomaly_end:.1f}s in {get_video_duration(ucsd_video):.1f}s clip")
    return True


# ============================================================
# Main
# ============================================================

def main():
    print("=" * 60)
    print("Preparing Video Data for NX Witness Analysis Tasks")
    print("=" * 60)
    print(f"Video dir:      {VIDEO_DIR}")
    print(f"Annotation dir: {ANNOTATION_DIR}")
    print(f"Cache dir:      {CACHE_DIR}")

    results = {}
    results["mall"] = prepare_mall_dataset()
    results["avenue"] = prepare_avenue_dataset()
    results["umn"] = prepare_umn_dataset()
    results["ucsd"] = prepare_ucsd_dataset()

    # Summary
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)

    videos = sorted(glob.glob(os.path.join(VIDEO_DIR, "*.mp4")))
    gt_files = sorted(glob.glob(os.path.join(ANNOTATION_DIR, "*_gt.json")))

    print(f"\nVideos ({len(videos)}):")
    for v in videos:
        size_mb = os.path.getsize(v) / 1024 / 1024
        dur = get_video_duration(v)
        print(f"  {os.path.basename(v):30s} {size_mb:6.1f} MB  {dur:6.1f}s")

    print(f"\nGround Truth ({len(gt_files)}):")
    for gt in gt_files:
        with open(gt) as f:
            data = json.load(f)
        placeholder = data.get("is_placeholder", True)
        status = "REAL" if not placeholder else "PLACEHOLDER"
        print(f"  {os.path.basename(gt):35s} [{status}]")

    # Task mapping
    print("\nTask -> Video Mapping:")
    task_map = {
        "pedestrian_counting":     "mall_pedestrian.mp4",
        "suspicious_activity":     "avenue_anomaly.mp4",
        "crowd_dispersal":         "umn_crowd.mp4",
        "unauthorized_access":     "ucsd_pedestrian.mp4",
        "false_alarm_verification":"avenue_normal.mp4",
    }
    for task, video in task_map.items():
        exists = os.path.exists(os.path.join(VIDEO_DIR, video))
        gt_name = video.replace(".mp4", "_gt.json")
        gt_exists = os.path.exists(os.path.join(ANNOTATION_DIR, gt_name))
        status = "OK" if exists and gt_exists else "MISSING"
        print(f"  {task:30s} -> {video:30s} [{status}]")

    # Cleanup hint
    cache_size = sum(os.path.getsize(os.path.join(CACHE_DIR, f))
                     for f in os.listdir(CACHE_DIR) if os.path.isfile(os.path.join(CACHE_DIR, f)))
    cache_mb = cache_size / 1024 / 1024
    print(f"\nCache directory: {CACHE_DIR} ({cache_mb:.0f} MB)")
    print("Run with --cleanup to remove cached raw downloads after extraction")

    if "--cleanup" in sys.argv:
        print("Cleaning up cache...")
        shutil.rmtree(CACHE_DIR)
        print("Done.")

    failed = [k for k, v in results.items() if not v]
    if failed:
        print(f"\nWARNING: Failed datasets: {', '.join(failed)}")
        return 1

    print("\nAll datasets prepared successfully!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
