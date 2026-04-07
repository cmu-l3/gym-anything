#!/usr/bin/env python3
"""Verifier for multilang_documentary_mastering_pipeline task."""

import json
import os
import subprocess
import sys


def run_ffprobe(filepath):
    """Run ffprobe and return parsed JSON output."""
    cmd = [
        "ffprobe", "-v", "quiet", "-print_format", "json",
        "-show_format", "-show_streams", filepath
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            return None
        return json.loads(result.stdout)
    except Exception:
        return None


def verify_multilang_documentary_mastering_pipeline(task_data):
    """
    Verify the multilang documentary mastering pipeline outputs.
    Returns a dict with 'score' (0.0-1.0) and 'feedback' (str).
    """
    metadata = task_data.get("metadata", {})
    gt = metadata.get("ground_truth", {})
    deliverables = metadata.get("deliverables", {})

    checks = []
    total_points = 0
    earned_points = 0

    def add_check(name, passed, points=1, detail=""):
        nonlocal total_points, earned_points
        total_points += points
        if passed:
            earned_points += points
        checks.append({
            "name": name,
            "passed": passed,
            "points": points,
            "detail": detail
        })

    # == 1. File existence checks (6 files x 1 point each) ==
    file_checks = [
        ("master_mkv", "Master MKV"),
        ("dist_english", "Distribution English MP4"),
        ("dist_spanish", "Distribution Spanish MP4"),
        ("dist_audio", "Distribution Audio M4A"),
        ("proof_sheet", "QA Proof Sheet PNG"),
        ("report", "Mastering Report JSON"),
    ]

    for key, label in file_checks:
        path = deliverables.get(key, "")
        exists = os.path.isfile(path)
        add_check(f"{label} exists", exists, points=1,
                  detail=f"{path} {'found' if exists else 'MISSING'}")

    # == 2. Master MKV stream inventory (8 points) ==
    master_path = deliverables.get("master_mkv", "")
    if os.path.isfile(master_path):
        probe = run_ffprobe(master_path)
        if probe:
            streams = probe.get("streams", [])
            video_streams = [s for s in streams if s["codec_type"] == "video"]
            audio_streams = [s for s in streams if s["codec_type"] == "audio"]
            sub_streams = [s for s in streams if s["codec_type"] == "subtitle"]

            # Video checks
            add_check("Master has 1 video stream",
                      len(video_streams) == 1, points=1)

            if video_streams:
                vs = video_streams[0]
                add_check("Master video is H.264",
                          vs.get("codec_name") == "h264", points=1,
                          detail=f"codec={vs.get('codec_name')}")

                w = int(vs.get("width", 0))
                h = int(vs.get("height", 0))
                add_check("Master video is 1920x1080",
                          w == 1920 and h == 1080, points=1,
                          detail=f"{w}x{h}")

            # Audio checks
            add_check("Master has 3 audio tracks",
                      len(audio_streams) == 3, points=2,
                      detail=f"found {len(audio_streams)} audio streams")

            # Check language tags
            if len(audio_streams) >= 3:
                lang_tags = []
                for a in audio_streams:
                    tags = a.get("tags", {})
                    lang = tags.get("language", "und")
                    lang_tags.append(lang)
                has_eng = "eng" in lang_tags
                has_spa = "spa" in lang_tags
                add_check("Master audio has eng+spa language tags",
                          has_eng and has_spa, points=1,
                          detail=f"language tags: {lang_tags}")

            # Subtitle checks
            add_check("Master has 2 subtitle tracks",
                      len(sub_streams) == 2, points=1,
                      detail=f"found {len(sub_streams)} subtitle streams")

            if len(sub_streams) >= 2:
                sub_langs = []
                for s in sub_streams:
                    tags = s.get("tags", {})
                    lang = tags.get("language", "und")
                    sub_langs.append(lang)
                has_eng_sub = "eng" in sub_langs
                has_spa_sub = "spa" in sub_langs
                add_check("Master subtitles have eng+spa tags",
                          has_eng_sub and has_spa_sub, points=1,
                          detail=f"subtitle languages: {sub_langs}")

    # == 3. Distribution English checks (4 points) ==
    dist_en_path = deliverables.get("dist_english", "")
    if os.path.isfile(dist_en_path):
        probe = run_ffprobe(dist_en_path)
        if probe:
            streams = probe.get("streams", [])
            video_streams = [s for s in streams if s["codec_type"] == "video"]
            audio_streams = [s for s in streams if s["codec_type"] == "audio"]
            sub_streams = [s for s in streams if s["codec_type"] == "subtitle"]

            if video_streams:
                vs = video_streams[0]
                w = int(vs.get("width", 0))
                h = int(vs.get("height", 0))
                add_check("Dist EN is 1280x720",
                          w == 1280 and h == 720, points=1,
                          detail=f"{w}x{h}")

            add_check("Dist EN has 1 audio track",
                      len(audio_streams) == 1, points=1,
                      detail=f"found {len(audio_streams)} audio streams")

            add_check("Dist EN has 0 subtitle streams (hardburned)",
                      len(sub_streams) == 0, points=2,
                      detail=f"found {len(sub_streams)} subtitle streams")

    # == 4. Distribution Spanish checks (4 points) ==
    dist_es_path = deliverables.get("dist_spanish", "")
    if os.path.isfile(dist_es_path):
        probe = run_ffprobe(dist_es_path)
        if probe:
            streams = probe.get("streams", [])
            video_streams = [s for s in streams if s["codec_type"] == "video"]
            audio_streams = [s for s in streams if s["codec_type"] == "audio"]
            sub_streams = [s for s in streams if s["codec_type"] == "subtitle"]

            if video_streams:
                vs = video_streams[0]
                w = int(vs.get("width", 0))
                h = int(vs.get("height", 0))
                add_check("Dist ES is 1280x720",
                          w == 1280 and h == 720, points=1,
                          detail=f"{w}x{h}")

            add_check("Dist ES has 1 audio track",
                      len(audio_streams) == 1, points=1,
                      detail=f"found {len(audio_streams)} audio streams")

            add_check("Dist ES has 0 subtitle streams (hardburned)",
                      len(sub_streams) == 0, points=2,
                      detail=f"found {len(sub_streams)} subtitle streams")

    # == 5. Distribution audio checks (3 points) ==
    dist_audio_path = deliverables.get("dist_audio", "")
    if os.path.isfile(dist_audio_path):
        probe = run_ffprobe(dist_audio_path)
        if probe:
            streams = probe.get("streams", [])
            video_streams = [s for s in streams if s["codec_type"] == "video"]
            audio_streams = [s for s in streams if s["codec_type"] == "audio"]

            add_check("Dist audio has 0 video streams",
                      len(video_streams) == 0, points=1,
                      detail=f"found {len(video_streams)} video streams")

            add_check("Dist audio has 1 audio stream",
                      len(audio_streams) == 1, points=1,
                      detail=f"found {len(audio_streams)} audio streams")

            if audio_streams:
                codec = audio_streams[0].get("codec_name", "")
                add_check("Dist audio is AAC",
                          codec == "aac", points=1,
                          detail=f"codec={codec}")

    # == 6. Proof sheet checks (2 points) ==
    proof_path = deliverables.get("proof_sheet", "")
    if os.path.isfile(proof_path):
        try:
            from PIL import Image
            img = Image.open(proof_path)
            w, h = img.size
            # Expected: 960x360 (3x2 grid of 320x180)
            # Allow some tolerance
            w_ok = 800 <= w <= 1200
            h_ok = 280 <= h <= 500
            add_check("Proof sheet dimensions reasonable",
                      w_ok and h_ok, points=2,
                      detail=f"{w}x{h} (expected ~960x360)")
        except Exception as e:
            add_check("Proof sheet readable as image",
                      False, points=2, detail=str(e))

    # == 7. Report checks (4 points) ==
    report_path = deliverables.get("report", "")
    if os.path.isfile(report_path):
        try:
            with open(report_path, "r") as f:
                report = json.load(f)

            add_check("Report is valid JSON", True, points=1)

            has_sync = "sync_analysis" in report
            has_subs = "subtitle_corrections" in report
            has_deliverables = "deliverables" in report
            add_check("Report has required sections",
                      has_sync and has_subs and has_deliverables, points=1,
                      detail=f"sync={has_sync}, subs={has_subs}, deliverables={has_deliverables}")

            # Check reported sync values against ground truth
            if has_sync:
                sync = report["sync_analysis"]
                # Check EN offset
                reported_en_offset = None
                for key in ["applied_offset_en_sec", "en_offset_sec", "english_offset_sec"]:
                    if key in sync:
                        reported_en_offset = float(sync[key])
                        break

                if reported_en_offset is not None:
                    expected_en = gt.get("en_offset_sec", 3.5)
                    en_close = abs(abs(reported_en_offset) - expected_en) < 0.5
                    add_check("Report EN offset within tolerance",
                              en_close, points=1,
                              detail=f"reported={reported_en_offset}, expected=~{expected_en}")

                # Check ES offset
                reported_es_offset = None
                for key in ["applied_offset_es_sec", "es_offset_sec", "spanish_offset_sec"]:
                    if key in sync:
                        reported_es_offset = float(sync[key])
                        break

                if reported_es_offset is not None:
                    expected_es = gt.get("es_offset_sec", 1.8)
                    es_close = abs(abs(reported_es_offset) - expected_es) < 0.5
                    add_check("Report ES offset within tolerance",
                              es_close, points=1,
                              detail=f"reported={reported_es_offset}, expected=~{expected_es}")
        except json.JSONDecodeError:
            add_check("Report is valid JSON", False, points=1, detail="Invalid JSON")
        except Exception as e:
            add_check("Report readable", False, points=1, detail=str(e))

    # == Calculate final score ==
    score = earned_points / total_points if total_points > 0 else 0.0

    feedback_lines = []
    for c in checks:
        status = "PASS" if c["passed"] else "FAIL"
        line = f"[{status}] {c['name']} ({c['points']}pt)"
        if c["detail"]:
            line += f" -- {c['detail']}"
        feedback_lines.append(line)

    feedback_lines.append(f"\nScore: {earned_points}/{total_points} = {score:.2f}")

    return {
        "score": round(score, 4),
        "feedback": "\n".join(feedback_lines)
    }
