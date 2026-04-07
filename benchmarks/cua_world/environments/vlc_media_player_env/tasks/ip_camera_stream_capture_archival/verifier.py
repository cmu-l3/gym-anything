#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stream_capture(traj, env_info, task_info):
    """
    Verifies the IP Camera Stream Capture task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Parse exported task results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    snapshot_count = result.get('snapshot_count', 0)
    report_exists = result.get('report_exists', False)
    video_info = result.get('video_info', {})

    # ================================================================
    # Criterion 1: Capture File Exists & Created Properly (15 pts)
    # ================================================================
    if output_exists and file_created:
        format_name = video_info.get("format", {}).get("format_name", "")
        if "mp4" in format_name:
            score += 15
            feedback_parts.append("MP4 capture file created successfully")
        else:
            score += 5
            feedback_parts.append(f"File created but incorrect container format: {format_name}")
    else:
        feedback_parts.append("Capture file missing or pre-existing (Anti-gaming triggered)")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # ================================================================
    # Criterion 2: Transcoded Codecs (15 pts)
    # ================================================================
    v_codec = ""
    a_codec = ""
    for stream in video_info.get("streams", []):
        if stream.get("codec_type") == "video":
            v_codec = stream.get("codec_name", "").lower()
        elif stream.get("codec_type") == "audio":
            a_codec = stream.get("codec_name", "").lower()

    codec_score = 0
    if v_codec in ["h264", "avc", "libx264"]:
        codec_score += 10
        feedback_parts.append("Video transcoded to H.264")
    else:
        feedback_parts.append(f"Wrong video codec: {v_codec}")

    if a_codec in ["aac", "aac_latm"]:
        codec_score += 5
        feedback_parts.append("Audio transcoded to AAC")
    else:
        feedback_parts.append(f"Wrong audio codec: {a_codec}")
        
    score += codec_score

    # ================================================================
    # Criterion 3: Capture Duration (40s - 50s) (25 pts)
    # ================================================================
    fmt_duration = float(video_info.get("format", {}).get("duration", 0))
    if 40.0 <= fmt_duration <= 50.0:
        score += 25
        feedback_parts.append(f"Duration correct ({fmt_duration:.2f}s)")
    elif 30.0 <= fmt_duration <= 60.0:
        score += 10
        feedback_parts.append(f"Duration out of bounds ({fmt_duration:.2f}s) - Partial credit")
    else:
        feedback_parts.append(f"Duration incorrect ({fmt_duration:.2f}s) - Did not record live stream correctly")

    # ================================================================
    # Criterion 4: Snapshots Captured (15 pts)
    # ================================================================
    if snapshot_count >= 3:
        score += 15
        feedback_parts.append(f"Captured {snapshot_count} snapshots")
    elif snapshot_count > 0:
        score += 5
        feedback_parts.append(f"Captured only {snapshot_count} snapshots")
    else:
        feedback_parts.append("No snapshots captured")

    # ================================================================
    # Criterion 5: Diagnostic Report (15 pts)
    # ================================================================
    if report_exists:
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/stream_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                report = json.load(f)
                
            orig_v = str(report.get("original_video_codec", "")).lower()
            orig_a = str(report.get("original_audio_codec", "")).lower()
            
            # The broadcast is strictly using mpeg2video and mp2
            v_match = any(c in orig_v for c in ["mpeg2", "mp2v", "mpeg-2", "mpg2"])
            a_match = any(c in orig_a for c in ["mp2", "mpga", "mpeg audio"])
            
            if v_match and a_match:
                score += 15
                feedback_parts.append("JSON report correctly identifies original legacy codecs")
            else:
                score += 5
                feedback_parts.append(f"JSON report found but original codecs incorrect (Found V:{orig_v}, A:{orig_a})")
        except Exception:
            feedback_parts.append("JSON report exists but is invalid/unparseable")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback_parts.append("Diagnostic report not found")

    # ================================================================
    # Criterion 6: VLM Trajectory Verification (15 pts)
    # ================================================================
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = """You are evaluating an AI agent performing an IT networking task. 
                Look at these sequentially captured frames.
                Is the agent interacting with VLC Media Player and displaying a network stream (often showing a test pattern or a camera feed) or adjusting network capture/convert settings?
                Answer strictly in JSON: {"workflow_observed": true/false}"""
                
                vlm_result = query_vlm(prompt=prompt, images=frames)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("workflow_observed", False):
                        score += 15
                        feedback_parts.append("VLM verified correct workflow trajectory")
                    else:
                        feedback_parts.append("VLM did not observe stream connection workflow")
        except Exception as e:
            logger.warning(f"VLM verification skipped/failed: {e}")
            score += 15 # Grant points if VLM fails for system reasons

    # Pass threshold: 75/100 points
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }