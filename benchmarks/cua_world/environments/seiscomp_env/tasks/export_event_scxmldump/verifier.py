#!/usr/bin/env python3
"""
Verifier for Export Earthquake Event Data task.
Validates the presence, temporal validity, and content of the exported SeisComP XML,
along with VLM trajectory verification to ensure terminal commands were used.
"""

import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_export_event(traj, env_info, task_info):
    """
    Verify the SeisComP XML export.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/noto_export.xml')
    
    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Read task execution metrics
    # ================================================================
    metrics_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", metrics_file.name)
        with open(metrics_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(metrics_file.name):
            os.unlink(metrics_file.name)

    output_exists = result.get('output_file_exists', False)
    
    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {expected_path}"
        }

    # Check size and time (Anti-gaming checks)
    file_size = result.get('output_file_size', 0)
    file_mtime = result.get('output_file_mtime', 0)
    task_start = result.get('task_start_time', 0)

    if file_size > metadata.get('min_file_size_bytes', 500):
        score += 15
        feedback_parts.append("File size is acceptable")
    else:
        feedback_parts.append("File is too small/empty")
        
    file_created_during_task = file_mtime >= task_start
    if file_created_during_task:
        score += 15
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("File predates task start (possible copy)")

    # ================================================================
    # 2. Analyze the XML File Content
    # ================================================================
    xml_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(expected_path, xml_file.name)
        
        # Read raw string for quick namespace checks
        with open(xml_file.name, 'r', encoding='utf-8', errors='ignore') as f:
            raw_xml = f.read()
            
        is_scml = "geofon.gfz-potsdam.de" in raw_xml or "seiscomp" in raw_xml.lower()
        is_quakeml = "quakeml.org/xmlns/bed" in raw_xml
        
        if is_scml and not is_quakeml:
            score += 15
            feedback_parts.append("Valid SeisComP format (not raw QuakeML)")
        else:
            feedback_parts.append("Format incorrect (possibly raw QuakeML copied)")

        # Parse XML properly, stripping namespaces for easy querying
        it = ET.iterparse(xml_file.name)
        for _, el in it:
            if '}' in el.tag:
                el.tag = el.tag.split('}', 1)[1]  # strip namespace
        root = it.root
        
        # Look for expected elements
        event_el = root.find('.//event')
        origin_el = root.find('.//origin')
        mag_el = root.find('.//magnitude')
        
        content_score = 0
        
        if event_el is not None:
            content_score += 5
            
        if origin_el is not None:
            try:
                lat = float(origin_el.find('.//latitude/value').text)
                lon = float(origin_el.find('.//longitude/value').text)
                if (metadata['expected_lat_min'] <= lat <= metadata['expected_lat_max'] and 
                    metadata['expected_lon_min'] <= lon <= metadata['expected_lon_max']):
                    content_score += 15
                    feedback_parts.append(f"Origin valid (Lat: {lat:.2f}, Lon: {lon:.2f})")
                else:
                    feedback_parts.append("Origin found but coordinates do not match Noto peninsula")
            except Exception:
                feedback_parts.append("Origin found but coordinates could not be parsed")
                
        if mag_el is not None:
            try:
                mag = float(mag_el.find('.//magnitude/value').text)
                if metadata['expected_mag_min'] <= mag <= metadata['expected_mag_max']:
                    content_score += 15
                    feedback_parts.append(f"Magnitude valid ({mag:.1f})")
                else:
                    feedback_parts.append("Magnitude found but value does not match expected")
            except Exception:
                feedback_parts.append("Magnitude found but could not be parsed")
                
        if content_score == 35:
            feedback_parts.append("All expected event data present")
            
        score += content_score

    except ET.ParseError:
        feedback_parts.append("Exported file is not valid XML")
    except Exception as e:
        feedback_parts.append(f"Error parsing XML: {e}")
    finally:
        if os.path.exists(xml_file.name):
            os.unlink(xml_file.name)

    # ================================================================
    # 3. VLM Verification of Trajectory
    # ================================================================
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        
        if frames and query_vlm:
            prompt = """You are evaluating an AI agent performing a terminal task.
            The agent is supposed to run SeisComP database tools: 'scevtls' and 'scxmldump'.
            Look at the provided trajectory frames (screenshots of the terminal over time).
            Do you see evidence that the agent typed and executed these commands in the terminal?
            Answer 'yes' if you clearly see either command in the terminal output, otherwise answer 'no'.
            Respond with ONLY 'yes' or 'no'."""
            
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and "yes" in vlm_response.lower():
                score += 20
                feedback_parts.append("VLM confirmed terminal usage")
            else:
                feedback_parts.append("VLM did not detect terminal command usage")
        else:
            # Grant fallback points if VLM is unavailable
            score += 20
            feedback_parts.append("VLM unavailable, auto-granting visual check points")
    except ImportError:
        # Fallback if gym_anything.vlm isn't fully installed/accessible
        score += 20
        feedback_parts.append("VLM unavailable, auto-granting visual check points")

    # ================================================================
    # 4. Final Verdict
    # ================================================================
    key_criteria_met = file_created_during_task and (content_score >= 30)
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }