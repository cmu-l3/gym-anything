#!/usr/bin/env python3
"""
Verifier for audiobook_chapter_export task.
Occupation: Audio and Video Technician
Industry: Publishing / Audiobook Production

Checks:
1. Track renamed to match "Ch05 - The Awakening" convention
2. Point markers at correct timeline positions
3. Range marker "Retail Sample" with correct boundaries
4. Full chapter WAV exported (newly created)
5. Retail sample WAV exported (newly created)
"""

import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_session_xml(filepath):
    """Parse the Ardour session XML file."""
    try:
        tree = ET.parse(filepath)
        return tree.getroot()
    except Exception as e:
        logger.error(f"Failed to parse session XML: {e}")
        return None


def get_audio_routes(root):
    """Get audio route elements (excluding Master/Monitor)."""
    routes = []
    for route in root.iter("Route"):
        name = route.get("name", "").lower()
        if name in ("master", "monitor", "auditioner"):
            continue
        default_type = route.get("default-type", "")
        if default_type == "audio" or not default_type:
            routes.append(route)
    return routes


def check_track_name(root):
    """Check if any audio track is renamed to match the spec."""
    routes = get_audio_routes(root)
    score = 0
    details = []

    if not routes:
        return 0, ["No audio tracks found in session"]

    for route in routes:
        name = route.get("name", "")
        name_lower = name.lower()
        
        has_chapter = any(kw in name_lower for kw in ["ch05", "ch 05", "chapter 5", "chapter 05"])
        has_awakening = "awakening" in name_lower

        if has_chapter and has_awakening:
            score = 15
            details.append(f"✓ Track '{name}' matches full spec (chapter + awakening)")
            break
        elif has_chapter or has_awakening:
            score = max(score, 7)
            details.append(f"~ Track '{name}' partially matches spec")
        elif name_lower not in ("audio 1", "audio 2", "audio", ""):
            score = max(score, 3)
            details.append(f"~ Track renamed to '{name}' but doesn't match spec")

    if score == 0:
        details.append("✗ Track not renamed appropriately")

    return score, details


def check_point_markers(root, expected_positions, tolerance):
    """Check for point markers at correct positions."""
    score = 0
    details = []
    matched = 0

    locations = list(root.iter("Location"))
    
    # Collect point markers (filter out range/system markers)
    point_markers = []
    for loc in locations:
        name = loc.get("name", "")
        flags = loc.get("flags", "")
        start = int(loc.get("start", "0"))
        end = int(loc.get("end", "0"))

        if "IsSessionRange" in flags or name.lower() in ("session", "punch", "loop"):
            continue
        if start != end or "IsRangeMarker" in flags:
            continue
            
        point_markers.append((name, start))

    # Match against expected
    for expected_pos in expected_positions:
        found = False
        for m_name, m_pos in point_markers:
            if abs(m_pos - expected_pos) <= tolerance:
                found = True
                matched += 1
                details.append(f"✓ Point marker at {expected_pos} matched by '{m_name}' (delta={abs(m_pos - expected_pos)})")
                break
        if not found:
            details.append(f"✗ Missing point marker near {expected_pos}")

    score = min(matched * 5, 25)  # 5 points per marker, max 25
    return score, details


def check_range_marker(root, expected_start, expected_end, tolerance):
    """Check for a Retail Sample range marker with correct boundaries."""
    score = 0
    details = []

    locations = list(root.iter("Location"))
    range_markers = []

    for loc in locations:
        name = loc.get("name", "")
        flags = loc.get("flags", "")
        start = int(loc.get("start", "0"))
        end = int(loc.get("end", "0"))

        if start != end or "IsRangeMarker" in flags:
            if "IsSessionRange" not in flags and name.lower() not in ("session", "punch", "loop"):
                range_markers.append((name, start, end))

    best_match = None
    for rname, rstart, rend in range_markers:
        rname_lower = rname.lower()
        if "retail" in rname_lower or "sample" in rname_lower:
            best_match = (rname, rstart, rend)
            break

    if not best_match:
        # Check if any range marker exists at the right position regardless of name
        for rname, rstart, rend in range_markers:
            if abs(rstart - expected_start) <= tolerance and abs(rend - expected_end) <= tolerance:
                score = 10
                details.append(f"~ Range marker '{rname}' has correct boundaries but wrong name")
                return score, details
                
        details.append("✗ No 'Retail Sample' range marker found")
        return 0, details

    rname, rstart, rend = best_match
    start_ok = abs(rstart - expected_start) <= tolerance
    end_ok = abs(rend - expected_end) <= tolerance

    if start_ok and end_ok:
        score = 20
        details.append(f"✓ Range marker '{rname}' has correct boundaries")
    elif start_ok or end_ok:
        score = 10
        details.append(f"~ Range marker '{rname}' has partially correct boundaries")
    else:
        score = 5
        details.append(f"✗ Range marker '{rname}' boundaries incorrect (start: {rstart}, end: {rend})")

    return score, details


def verify_audiobook_chapter_export(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_point_markers = metadata.get('expected_point_markers', [0, 88200, 441000, 793800, 1234800])
    expected_range_start = metadata.get('expected_range_start', 220500)
    expected_range_end = metadata.get('expected_range_end', 882000)
    tolerance = metadata.get('tolerance_samples', 66150)
    pass_threshold = metadata.get('pass_threshold', 55)

    total_score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Parse session XML
    # ---------------------------------------------------------
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()
    
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    try:
        copy_from_env(session_remote, tmp_xml.name)
        root = parse_session_xml(tmp_xml.name)
    except Exception as e:
        root = None
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    if root is not None:
        # Criterion 1: Track rename (15 pts)
        score1, details1 = check_track_name(root)
        total_score += score1
        feedback_parts.extend(details1)

        # Criterion 2: Point markers (25 pts)
        score2, details2 = check_point_markers(root, expected_point_markers, tolerance)
        total_score += score2
        feedback_parts.extend(details2)

        # Criterion 3: Range marker (20 pts)
        score3, details3 = check_range_marker(root, expected_range_start, expected_range_end, tolerance)
        total_score += score3
        feedback_parts.extend(details3)
    else:
        feedback_parts.append("✗ Could not parse Ardour session file")

    # ---------------------------------------------------------
    # 2. Check exported files
    # ---------------------------------------------------------
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    task_start = result_data.get("task_start", 0)
    exports = result_data.get("exports", [])
    
    chapter_exported = False
    retail_exported = False
    
    for f in exports:
        fname = f['filename'].lower()
        fsize = f['size_bytes']
        fmtime = f['mtime']
        fpath = f['path']
        
        # Must be valid audio file (> 1KB) and created during task
        if fsize > 1024 and fmtime >= task_start:
            is_delivery_dir = "audiobook_delivery" in fpath.lower()
            
            # Criterion 4: Full chapter (20 pts)
            if "chapter" in fname and not chapter_exported:
                chapter_exported = True
                score = 20 if is_delivery_dir else 10  # Partial if in wrong dir
                total_score += score
                feedback_parts.append(f"✓ Chapter export found: {fname} ({int(fsize/1024)} KB)")
                
            # Criterion 5: Retail sample (20 pts)
            if ("retail" in fname or "sample" in fname) and not retail_exported:
                retail_exported = True
                score = 20 if is_delivery_dir else 10
                total_score += score
                feedback_parts.append(f"✓ Retail export found: {fname} ({int(fsize/1024)} KB)")

    if not chapter_exported:
        feedback_parts.append("✗ Missing or invalid full chapter export")
    if not retail_exported:
        feedback_parts.append("✗ Missing or invalid retail sample export")

    # ---------------------------------------------------------
    # 3. Final Evaluation
    # ---------------------------------------------------------
    passed = total_score >= pass_threshold
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }

if __name__ == "__main__":
    # Test block
    print("Verifier is meant to be called programmatically via verify_audiobook_chapter_export()")