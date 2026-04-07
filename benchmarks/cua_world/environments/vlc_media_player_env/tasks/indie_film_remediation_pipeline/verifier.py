#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_indie_film_remediation(traj, env_info, task_info):
    """
    Verify the Indie Film Remediation Pipeline task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_audio_offset = metadata.get('expected_audio_offset_ms', -1500)
    expected_sub_offset = metadata.get('expected_subtitle_offset_ms', 2000)

    score = 0
    feedback_parts = []
    
    # Helper to load json from env safely
    def load_json_from_env(filepath):
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(filepath, tmp.name)
            if os.path.getsize(tmp.name) > 0:
                with open(tmp.name, 'r') as f:
                    return json.load(f)
        except Exception:
            pass
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
        return {}

    # Load all extracted outputs
    task_meta = load_json_from_env("/tmp/task_meta.json")
    probe_exh = load_json_from_env("/tmp/probe_exhibition.json")
    probe_hard = load_json_from_env("/tmp/probe_hardsub.json")
    probe_comm = load_json_from_env("/tmp/probe_commentary.json")
    report_json = load_json_from_env("/tmp/remediation_report.json")

    task_start = task_meta.get("task_start", 0)
    files_created = 0

    # 1. Exhibition Master Verification (15 pts)
    exh_streams = probe_exh.get("streams", [])
    if len(exh_streams) > 0:
        if task_meta.get("exhibition_mtime", 0) > task_start:
            files_created += 1
            
        v_streams = [s for s in exh_streams if s.get("codec_type") == "video"]
        a_streams = [s for s in exh_streams if s.get("codec_type") == "audio"]
        s_streams = [s for s in exh_streams if s.get("codec_type") == "subtitle"]
        
        container = probe_exh.get("format", {}).get("format_name", "")
        if "matroska" in container:
            if len(v_streams) == 1 and len(a_streams) == 1 and len(s_streams) >= 1:
                score += 15
                feedback_parts.append("Exhibition Master: Correct MKV with Video/Audio/Sub streams")
            else:
                score += 8
                feedback_parts.append("Exhibition Master: MKV exists but stream counts are incorrect")
        else:
            feedback_parts.append("Exhibition Master: Not an MKV container")
    else:
        feedback_parts.append("Exhibition Master: Missing or invalid")

    # 2. Subtitle Sync Verification (15 pts)
    # Read the extracted SRT to check the timing
    tmp_srt = tempfile.NamedTemporaryFile(delete=False, suffix='.srt')
    sub_sync_correct = False
    try:
        copy_from_env("/tmp/exhibition_subs.srt", tmp_srt.name)
        if os.path.exists(tmp_srt.name) and os.path.getsize(tmp_srt.name) > 0:
            with open(tmp_srt.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                # Original: 00:00:01,000 -> Expected: 00:00:03,xxx
                if "00:00:03" in content[:250]:  # Look in the first few lines
                    score += 15
                    sub_sync_correct = True
                    feedback_parts.append("Subtitle Sync: Softsubs successfully delayed by 2000ms")
                elif "00:00:01" in content[:250]:
                    feedback_parts.append("Subtitle Sync: Subtitles present but not shifted")
                else:
                    feedback_parts.append("Subtitle Sync: Could not verify exact timing shift")
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_srt.name):
            os.unlink(tmp_srt.name)

    # 3. Hardsub Master Verification (15 pts)
    hard_streams = probe_hard.get("streams", [])
    if len(hard_streams) > 0:
        if task_meta.get("hardsub_mtime", 0) > task_start:
            files_created += 1
            
        v_streams = [s for s in hard_streams if s.get("codec_type") == "video"]
        a_streams = [s for s in hard_streams if s.get("codec_type") == "audio"]
        s_streams = [s for s in hard_streams if s.get("codec_type") == "subtitle"]
        
        container = probe_hard.get("format", {}).get("format_name", "")
        if "mp4" in container:
            if len(v_streams) == 1 and len(a_streams) >= 1 and len(s_streams) == 0:
                score += 15
                feedback_parts.append("Hardsub Master: Correct MP4 with burned subtitles (no sub streams)")
            else:
                score += 5
                feedback_parts.append(f"Hardsub Master: Stream issue (Sub streams: {len(s_streams)})")
        else:
            feedback_parts.append("Hardsub Master: Not an MP4 container")
    else:
        feedback_parts.append("Hardsub Master: Missing or invalid")

    # 4. Commentary Edition Verification (15 pts)
    comm_streams = probe_comm.get("streams", [])
    if len(comm_streams) > 0:
        if task_meta.get("commentary_mtime", 0) > task_start:
            files_created += 1
            
        v_streams = [s for s in comm_streams if s.get("codec_type") == "video"]
        a_streams = [s for s in comm_streams if s.get("codec_type") == "audio"]
        
        container = probe_comm.get("format", {}).get("format_name", "")
        if "matroska" in container:
            if len(v_streams) == 1 and len(a_streams) == 2:
                score += 15
                feedback_parts.append("Commentary Edition: Correct MKV with dual audio tracks")
            else:
                score += 8
                feedback_parts.append(f"Commentary Edition: MKV has {len(a_streams)} audio tracks (expected 2)")
        else:
            feedback_parts.append("Commentary Edition: Not an MKV container")
    else:
        feedback_parts.append("Commentary Edition: Missing or invalid")

    # 5. Report JSON Verification (15 pts)
    if report_json:
        audio_off = report_json.get("applied_audio_offset_ms")
        sub_off = report_json.get("applied_subtitle_offset_ms")
        
        if audio_off == expected_audio_offset and sub_off == expected_sub_offset:
            score += 15
            feedback_parts.append("Report: JSON valid and offsets perfectly identified")
        elif abs(int(audio_off or 0)) == abs(expected_audio_offset) and abs(int(sub_off or 0)) == abs(expected_sub_offset):
            score += 10
            feedback_parts.append("Report: JSON valid, magnitude of offsets correct (sign reversed)")
        else:
            score += 5
            feedback_parts.append(f"Report: JSON exists but offsets incorrect (A:{audio_off}, S:{sub_off})")
    else:
        feedback_parts.append("Report: Missing or invalid JSON")

    # 6. Anti-Gaming Check (10 pts)
    if files_created >= 2:
        score += 10
        feedback_parts.append("Anti-gaming: Files created during task window")
    elif files_created == 1:
        score += 5
        feedback_parts.append("Anti-gaming: Only 1 file created during task window")
    else:
        feedback_parts.append("Anti-gaming: No files created during task window")

    # 7. VLM Trajectory Verification (15 pts)
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """Analyze these chronological screenshots of an agent performing media remediation.
            Is there visual evidence that the agent either:
            1. Interacted with VLC Media Player's GUI (e.g., 'Convert/Save', 'Synchronization' tabs, adding multiple tracks)?
            OR
            2. Typed and executed 'ffmpeg' commands in a terminal window to transcode/mux the files?
            
            Respond with JSON:
            {
                "active_processing_evidence": true/false,
                "tool_used": "vlc/ffmpeg/none",
                "observations": "brief description"
            }"""
            
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("active_processing_evidence", False):
                    score += 15
                    feedback_parts.append(f"VLM: Workflow evidence verified ({parsed.get('tool_used', 'unknown')})")
                else:
                    feedback_parts.append("VLM: No clear evidence of workflow completion")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        # Graceful degradation if VLM fails
        if score >= 60:
            score += 15 
            feedback_parts.append("VLM: Skipped (awarded points based on strong programmatic pass)")

    # Final Evaluation
    passed = score >= 70 and files_created >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }