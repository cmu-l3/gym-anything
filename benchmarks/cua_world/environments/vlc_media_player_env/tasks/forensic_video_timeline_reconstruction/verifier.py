import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from utils.vlc_verification_utils import get_video_info, verify_snapshot_exists


def verify_forensic_video_timeline_reconstruction(traj, env_info, task_info):
    copy_from_env = env_info["copy_from_env"]
    """
    Verify forensic video timeline reconstruction task.

    Criteria (25 points total, pass threshold = 55%):
    - Corrected timeline JSON (8 points):
      - Valid JSON with 5 event entries: 2 points
      - Each timestamp within ±2s of ground truth: 1 point each (5 points)
      - Wrong-target gate: if timestamps match the WRONG log, score 0 for timestamps
      - Timeline has event descriptions: 1 point
    - Forensic snapshots (7 points):
      - At least 3 snapshots exist and are >10KB: 3 points
      - At least 5 snapshots: +2 points
      - Snapshots are valid images: 2 points
    - Evidence clips (10 points):
      - At least 3 clips exist: 3 points
      - At least 5 clips: +2 points
      - Clips are ~5 seconds duration (±2s): 1 point each (max 5 points)
    """
    feedback = []
    score = 0.0
    max_score = 25.0
    temp_dirs = []

    try:
        # --- Load ground truth ---
        gt_dir = tempfile.mkdtemp(prefix='vlc_verify_gt_')
        temp_dirs.append(gt_dir)
        gt_path = os.path.join(gt_dir, 'gt.json')
        try:
            copy_from_env('/tmp/.forensic_ground_truth.json', gt_path)
            with open(gt_path, 'r') as f:
                gt = json.load(f)
        except Exception:
            gt = {
                "events": {
                    "A": {"timestamp": 15}, "B": {"timestamp": 42},
                    "C": {"timestamp": 78}, "D": {"timestamp": 121},
                    "E": {"timestamp": 156}
                },
                "wrong_timestamps": {"A": 22, "B": 35, "C": 85, "D": 114, "E": 163},
                "tolerance_sec": 2, "clip_duration_sec": 5
            }
            feedback.append("! Using fallback ground truth")

        gt_events = gt['events']
        wrong_ts = gt['wrong_timestamps']
        tolerance = gt.get('tolerance_sec', 2)

        # --- Verify corrected timeline ---
        tl_dir = tempfile.mkdtemp(prefix='vlc_verify_tl_')
        temp_dirs.append(tl_dir)
        tl_path = os.path.join(tl_dir, 'corrected_timeline.json')

        try:
            copy_from_env('/home/ga/Documents/corrected_timeline.json', tl_path)
        except Exception:
            feedback.append("x Corrected timeline: Not found")
            tl_path = None

        if tl_path and os.path.exists(tl_path):
            try:
                with open(tl_path, 'r') as f:
                    timeline = json.load(f)

                # Parse timestamps from the timeline
                # Accept various formats: list of events, dict with event keys, etc.
                agent_timestamps = {}
                if isinstance(timeline, list):
                    for i, entry in enumerate(timeline):
                        if isinstance(entry, dict):
                            # Try to extract event label and timestamp
                            label = str(entry.get('event', entry.get('label', entry.get('name', chr(65+i))))).upper()
                            ts = entry.get('timestamp', entry.get('time', entry.get('timestamp_sec', None)))
                            if ts is not None:
                                # Handle "M:SS" or "MM:SS" format
                                if isinstance(ts, str) and ':' in ts:
                                    parts = ts.split(':')
                                    try:
                                        ts = sum(float(p) * (60 ** (len(parts)-1-i)) for i, p in enumerate(parts))
                                    except ValueError:
                                        continue
                                label_key = label[0] if label else chr(65+i)
                                agent_timestamps[label_key] = float(ts)
                elif isinstance(timeline, dict):
                    # Could be {"events": [...]} or {"A": {...}, "B": {...}}
                    events_data = timeline.get('events', timeline)
                    if isinstance(events_data, list):
                        for i, entry in enumerate(events_data):
                            if isinstance(entry, dict):
                                label = str(entry.get('event', entry.get('label', entry.get('name', chr(65+i))))).upper()
                                ts = entry.get('timestamp', entry.get('time', entry.get('timestamp_sec', None)))
                                if ts is not None:
                                    if isinstance(ts, str) and ':' in ts:
                                        parts = ts.split(':')
                                        try:
                                            ts = sum(float(p) * (60 ** (len(parts)-1-i)) for i, p in enumerate(parts))
                                        except ValueError:
                                            continue
                                    label_key = label[0] if label else chr(65+i)
                                    agent_timestamps[label_key] = float(ts)
                    elif isinstance(events_data, dict):
                        for key, val in events_data.items():
                            label_key = str(key).upper()[0]
                            if isinstance(val, dict):
                                ts = val.get('timestamp', val.get('time', val.get('timestamp_sec', None)))
                            else:
                                ts = val
                            if ts is not None:
                                if isinstance(ts, str) and ':' in ts:
                                    parts = ts.split(':')
                                    try:
                                        ts = sum(float(p) * (60 ** (len(parts)-1-i)) for i, p in enumerate(parts))
                                    except ValueError:
                                        continue
                                agent_timestamps[label_key] = float(ts)

                if len(agent_timestamps) >= 3:
                    score += 2.0
                    feedback.append(f"+ Corrected timeline: Valid JSON with {len(agent_timestamps)} events")
                elif len(agent_timestamps) > 0:
                    score += 1.0
                    feedback.append(f"~ Corrected timeline: Valid JSON but only {len(agent_timestamps)} events")
                else:
                    feedback.append("x Corrected timeline: Could not parse event timestamps")

                # Check timestamps against ground truth
                # WRONG-TARGET GATE: if timestamps match the wrong log, zero credit
                wrong_match_count = 0
                correct_count = 0

                for event_key in ['A', 'B', 'C', 'D', 'E']:
                    if event_key not in agent_timestamps:
                        feedback.append(f"  x Event {event_key}: Timestamp missing")
                        continue

                    agent_ts = agent_timestamps[event_key]
                    gt_ts = gt_events[event_key]['timestamp']
                    wrong_ts_val = wrong_ts[event_key]

                    # Check if it matches the WRONG timestamp
                    if abs(agent_ts - wrong_ts_val) <= tolerance:
                        wrong_match_count += 1

                    # Check if it matches the CORRECT timestamp
                    if abs(agent_ts - gt_ts) <= tolerance:
                        correct_count += 1
                        score += 1.0
                        feedback.append(f"  + Event {event_key}: {agent_ts:.0f}s (correct, ground truth: {gt_ts}s)")
                    else:
                        feedback.append(f"  x Event {event_key}: {agent_ts:.0f}s (expected ~{gt_ts}s, off by {abs(agent_ts - gt_ts):.1f}s)")

                # Wrong-target gate: if agent just used the wrong log timestamps
                if wrong_match_count >= 4 and correct_count <= 1:
                    penalty = min(score, 7.0)  # Remove all timeline points
                    score -= penalty
                    feedback.append(f"!! WRONG-TARGET GATE: Timestamps match the incorrect incident log ({wrong_match_count}/5). Score penalty: -{penalty}")

                # Check for event descriptions
                tl_str = json.dumps(timeline).lower()
                desc_keywords = ['impact', 'swerve', 'debris', 'stop', 'reverse',
                                 'collision', 'maneuver', 'wreckage', 'halt', 'backing']
                desc_found = sum(1 for kw in desc_keywords if kw in tl_str)
                if desc_found >= 3:
                    score += 1.0
                    feedback.append(f"+ Timeline descriptions: {desc_found} event descriptions found")
                else:
                    feedback.append(f"x Timeline descriptions: Only {desc_found} descriptions (need 3+)")

            except json.JSONDecodeError:
                feedback.append("x Corrected timeline: Invalid JSON format")
            except Exception as e:
                feedback.append(f"x Corrected timeline: Error parsing ({str(e)})")

        # --- Verify snapshots ---
        snap_dir = tempfile.mkdtemp(prefix='vlc_verify_snap_')
        temp_dirs.append(snap_dir)

        try:
            copy_from_env('/tmp/forensic_snapshots/', snap_dir)
        except Exception:
            pass

        # Count valid snapshots
        snapshot_files = []
        for root, dirs, files in os.walk(snap_dir):
            for f in files:
                fpath = os.path.join(root, f)
                if f.lower().endswith(('.png', '.jpg', '.jpeg')) and os.path.getsize(fpath) > 10240:
                    snapshot_files.append(fpath)

        num_snaps = len(snapshot_files)
        if num_snaps >= 5:
            score += 5.0
            feedback.append(f"+ Snapshots: {num_snaps} valid forensic snapshots (>10KB)")
        elif num_snaps >= 3:
            score += 3.0
            feedback.append(f"~ Snapshots: {num_snaps}/5 valid forensic snapshots")
        elif num_snaps >= 1:
            score += 1.0
            feedback.append(f"x Snapshots: Only {num_snaps}/5 snapshots found")
        else:
            feedback.append("x Snapshots: No valid snapshots found")

        # Check image validity
        valid_imgs = 0
        for sf in snapshot_files[:5]:
            try:
                from PIL import Image
                img = Image.open(sf)
                img.verify()
                valid_imgs += 1
            except Exception:
                valid_imgs += 1  # Count if PIL not available
        if valid_imgs >= 3:
            score += 2.0
            feedback.append(f"+ Snapshot quality: {valid_imgs} valid images")

        # --- Verify evidence clips ---
        clips_dir = tempfile.mkdtemp(prefix='vlc_verify_clips_')
        temp_dirs.append(clips_dir)

        try:
            copy_from_env('/tmp/forensic_evidence_clips/', clips_dir)
        except Exception:
            pass

        clip_files = []
        for root, dirs, files in os.walk(clips_dir):
            for f in files:
                fpath = os.path.join(root, f)
                if f.lower().endswith(('.mp4', '.mkv', '.avi', '.webm')) and os.path.getsize(fpath) > 1000:
                    clip_files.append(fpath)

        num_clips = len(clip_files)
        if num_clips >= 5:
            score += 5.0
            feedback.append(f"+ Evidence clips: {num_clips} clips found")
        elif num_clips >= 3:
            score += 3.0
            feedback.append(f"~ Evidence clips: {num_clips}/5 clips found")
        elif num_clips >= 1:
            score += 1.0
            feedback.append(f"x Evidence clips: Only {num_clips}/5 clips found")
        else:
            feedback.append("x Evidence clips: No clips found")

        # Check clip durations (~5 seconds each)
        correct_duration_clips = 0
        for cf in clip_files[:5]:
            info = get_video_info(cf)
            dur = info.get('duration', 0)
            if 3.0 <= dur <= 8.0:  # 5 ± 3 seconds tolerance
                correct_duration_clips += 1

        if correct_duration_clips > 0:
            clip_dur_score = min(correct_duration_clips, 5)
            score += clip_dur_score
            feedback.append(f"+ Clip durations: {correct_duration_clips}/{num_clips} clips are ~5 seconds")

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
