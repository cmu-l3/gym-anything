#!/usr/bin/env python3
"""
Verifier for Verify DVD Compatibility task

This verifier checks:
1. Report file exists with substantial content
2. Report has required structure
3. Technical specifications are accurately reported
4. Pass/fail assessments are correct
5. Recommendations are appropriate
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_number_from_text(text, pattern):
    """Extract number from text using regex pattern."""
    match = re.search(pattern, text, re.IGNORECASE)
    if match:
        try:
            return float(match.group(1))
        except:
            return None
    return None


def extract_codec_from_text(text, codec_list):
    """Check if any codec name appears in text."""
    text_lower = text.lower()
    for codec in codec_list:
        if codec.lower() in text_lower:
            return codec
    return None


def check_pass_fail_logic(report_content, param_name, should_pass):
    """
    Check if report correctly marks parameter as PASS or FAIL.
    
    Args:
        report_content: Full report text
        param_name: Parameter to check (e.g., "Resolution", "Codec")
        should_pass: Whether parameter should be marked PASS
    
    Returns:
        bool: True if logic is correct
    """
    # Find the section with this parameter
    # Look for lines containing param_name followed by PASS or FAIL
    pattern = rf'{param_name}[^\n]*?→\s*(PASS|FAIL)'
    match = re.search(pattern, report_content, re.IGNORECASE)
    
    if match:
        result = match.group(1).upper()
        if should_pass:
            return result == "PASS"
        else:
            return result == "FAIL"
    
    # Alternative patterns
    # Check for param_name followed by "PASS" or "FAIL" within 100 chars
    param_pos = report_content.lower().find(param_name.lower())
    if param_pos != -1:
        context = report_content[param_pos:param_pos+150]
        if should_pass:
            return "pass" in context.lower() and "fail" not in context.lower()
        else:
            return "fail" in context.lower()
    
    return False


def verify_dvd_compatibility(traj, env_info, task_info):
    """
    Verify DVD compatibility report task completion.
    
    Checks:
    1. Report created with substantial content (200+ chars)
    2. Structure present (VIDEO, AUDIO, DURATION, OVERALL sections)
    3. Accurate resolution reported
    4. Accurate codec reported
    5. Accurate duration reported
    6. Correct pass/fail assessments
    7. Valid recommendations if incompatible
    
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 7
    feedback_parts = []
    
    # Copy report file
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/dvd_compatibility_report.txt", temp_report.name)
    except Exception as e:
        logger.error(f"Error copying report: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Report file not found: {str(e)}"}
    
    # Read report content
    try:
        with open(temp_report.name, 'r') as f:
            report_content = f.read()
    except Exception as e:
        os.unlink(temp_report.name)
        return {"passed": False, "score": 0, "feedback": f"Cannot read report: {str(e)}"}
    
    # Criterion 1: Report has substantial content (200+ chars)
    if len(report_content) >= 200:
        criteria_met += 1
        feedback_parts.append(f"✅ Report created ({len(report_content)} chars)")
    else:
        feedback_parts.append(f"❌ Report too short ({len(report_content)} chars, need 200+)")
        os.unlink(temp_report.name)
        return {
            "passed": False,
            "score": int((criteria_met / total_criteria) * 100),
            "feedback": " | ".join(feedback_parts)
        }
    
    # Criterion 2: Check structure present
    required_sections = ["VIDEO", "AUDIO", "DURATION", "OVERALL"]
    sections_found = []
    for section in required_sections:
        if section in report_content.upper():
            sections_found.append(section)
    
    if len(sections_found) >= 3:  # At least 3 of 4 sections
        criteria_met += 1
        feedback_parts.append(f"✅ Structure present ({len(sections_found)}/4 sections)")
    else:
        feedback_parts.append(f"❌ Missing sections (found {len(sections_found)}/4)")
    
    # Get actual video properties
    temp_props = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
    
    try:
        copy_from_env("/tmp/actual_video_properties.json", temp_props.name)
        
        with open(temp_props.name, 'r') as f:
            actual_props = json.load(f)
        
        if 'error' in actual_props:
            feedback_parts.append("⚠️ Cannot verify accuracy - video properties unavailable")
            os.unlink(temp_props.name)
            os.unlink(temp_report.name)
            
            # Still calculate score based on structure
            score = int((criteria_met / total_criteria) * 100)
            return {
                "passed": score >= 70,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Extract actual properties
        video_stream = None
        audio_stream = None
        
        for stream in actual_props.get('streams', []):
            if stream.get('codec_type') == 'video' and video_stream is None:
                video_stream = stream
            elif stream.get('codec_type') == 'audio' and audio_stream is None:
                audio_stream = stream
        
        if not video_stream or not audio_stream:
            feedback_parts.append("⚠️ Cannot extract stream properties")
            os.unlink(temp_props.name)
            os.unlink(temp_report.name)
            score = int((criteria_met / total_criteria) * 100)
            return {
                "passed": score >= 70,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        actual_width = int(video_stream.get('width', 0))
        actual_height = int(video_stream.get('height', 0))
        
        # Parse frame rate
        fps_str = video_stream.get('r_frame_rate', '0/1')
        if '/' in fps_str:
            num, den = map(int, fps_str.split('/'))
            actual_fps = num / den if den > 0 else 0
        else:
            actual_fps = float(fps_str)
        
        actual_video_codec = video_stream.get('codec_name', '').lower()
        actual_audio_codec = audio_stream.get('codec_name', '').lower()
        actual_duration = float(actual_props.get('format', {}).get('duration', 0))
        
        logger.info(f"Actual properties: {actual_width}x{actual_height}, {actual_fps}fps, "
                   f"v:{actual_video_codec}, a:{actual_audio_codec}, {actual_duration}s")
        
        # Criterion 3: Check resolution accuracy
        # Look for resolution in format "1920x1080" or "1920 x 1080"
        width_pattern = r'(\d{3,4})\s*[x×]\s*(\d{3,4})'
        res_match = re.search(width_pattern, report_content)
        
        if res_match:
            reported_width = int(res_match.group(1))
            reported_height = int(res_match.group(2))
            
            if (abs(reported_width - actual_width) <= 5 and 
                abs(reported_height - actual_height) <= 5):
                criteria_met += 1
                feedback_parts.append(f"✅ Resolution accurate ({reported_width}x{reported_height})")
            else:
                feedback_parts.append(f"❌ Resolution inaccurate (reported {reported_width}x{reported_height}, "
                                    f"actual {actual_width}x{actual_height})")
        else:
            feedback_parts.append("⚠️ Resolution not found in report")
        
        # Criterion 4: Check codec accuracy
        codec_found = False
        
        # Common codec name variations
        video_codec_names = {
            'h264': ['h264', 'h.264', 'avc', 'x264'],
            'hevc': ['hevc', 'h265', 'h.265', 'x265'],
            'mpeg2video': ['mpeg2', 'mpeg-2', 'mpg2'],
            'mpeg1video': ['mpeg1', 'mpeg-1'],
        }
        
        audio_codec_names = {
            'aac': ['aac', 'aac-lc'],
            'ac3': ['ac3', 'ac-3', 'dolby digital', 'dolby'],
            'mp2': ['mp2', 'mpeg-1 audio layer 2'],
            'mp3': ['mp3', 'mpeg-1 audio layer 3'],
        }
        
        # Check if actual video codec is mentioned
        for codec_key, codec_variants in video_codec_names.items():
            if actual_video_codec in codec_key or codec_key in actual_video_codec:
                for variant in codec_variants:
                    if variant in report_content.lower():
                        codec_found = True
                        break
                if codec_found:
                    break
        
        # Check audio codec
        audio_codec_found = False
        for codec_key, codec_variants in audio_codec_names.items():
            if actual_audio_codec in codec_key or codec_key in actual_audio_codec:
                for variant in codec_variants:
                    if variant in report_content.lower():
                        audio_codec_found = True
                        break
                if audio_codec_found:
                    break
        
        if codec_found and audio_codec_found:
            criteria_met += 1
            feedback_parts.append(f"✅ Codecs accurate (v:{actual_video_codec}, a:{actual_audio_codec})")
        elif codec_found or audio_codec_found:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Some codecs accurate")
        else:
            feedback_parts.append(f"❌ Codecs not accurately reported")
        
        # Criterion 5: Check duration accuracy
        # Look for duration in various formats: "30 seconds", "0:30", "30s", "30.0s"
        duration_patterns = [
            r'(\d+)\s*seconds',
            r'(\d+)\s*s\b',
            r'(\d+)\s*minutes',
            r'(\d+):(\d+)',  # MM:SS format
        ]
        
        duration_found = False
        for pattern in duration_patterns:
            match = re.search(pattern, report_content, re.IGNORECASE)
            if match:
                if 'minute' in pattern:
                    reported_duration = float(match.group(1)) * 60
                elif ':' in pattern:
                    minutes = int(match.group(1))
                    seconds = int(match.group(2))
                    reported_duration = minutes * 60 + seconds
                else:
                    reported_duration = float(match.group(1))
                
                if abs(reported_duration - actual_duration) <= 5:
                    criteria_met += 1
                    feedback_parts.append(f"✅ Duration accurate (~{reported_duration:.0f}s)")
                    duration_found = True
                    break
        
        if not duration_found:
            feedback_parts.append(f"⚠️ Duration not accurately reported (actual: {actual_duration:.0f}s)")
        
        # Criterion 6: Check pass/fail logic correctness
        # For the test video (H.264, 1920x1080, 30fps, AAC), ALL should FAIL
        
        # DVD standards for comparison
        dvd_resolutions = [(720, 480), (720, 576)]
        dvd_fps = [25, 29.97, 30]  # Allow 30 with tolerance
        dvd_video_codecs = ['mpeg2video', 'mpeg1video']
        dvd_audio_codecs = ['ac3', 'mp2', 'pcm_s16le', 'pcm_s24le']
        
        # Determine what should pass/fail
        resolution_should_pass = any(
            abs(actual_width - w) <= 5 and abs(actual_height - h) <= 5 
            for w, h in dvd_resolutions
        )
        
        fps_should_pass = any(abs(actual_fps - fps) <= 0.5 for fps in dvd_fps)
        
        video_codec_should_pass = actual_video_codec in dvd_video_codecs
        
        audio_codec_should_pass = actual_audio_codec in dvd_audio_codecs
        
        # Check if report correctly assesses these
        correct_assessments = 0
        total_assessments = 0
        
        # Check resolution assessment
        if check_pass_fail_logic(report_content, "Resolution", resolution_should_pass):
            correct_assessments += 1
        total_assessments += 1
        
        # Check frame rate assessment
        if check_pass_fail_logic(report_content, "Frame Rate", fps_should_pass) or \
           check_pass_fail_logic(report_content, "FPS", fps_should_pass):
            correct_assessments += 1
        total_assessments += 1
        
        # Check video codec assessment
        if check_pass_fail_logic(report_content, "Video Codec", video_codec_should_pass) or \
           check_pass_fail_logic(report_content, "Codec", video_codec_should_pass):
            correct_assessments += 1
        total_assessments += 1
        
        # Check audio codec assessment
        if check_pass_fail_logic(report_content, "Audio Codec", audio_codec_should_pass) or \
           check_pass_fail_logic(report_content, "Audio", audio_codec_should_pass):
            correct_assessments += 1
        total_assessments += 1
        
        # Check overall assessment
        overall_should_be_compatible = (resolution_should_pass and fps_should_pass and 
                                       video_codec_should_pass and audio_codec_should_pass)
        
        if overall_should_be_compatible:
            if "COMPATIBLE" in report_content.upper() and "NEEDS CONVERSION" not in report_content.upper():
                correct_assessments += 1
        else:
            if "NEEDS CONVERSION" in report_content.upper() or \
               ("INCOMPATIBLE" in report_content.upper() or "NOT COMPATIBLE" in report_content.upper()):
                correct_assessments += 1
        total_assessments += 1
        
        assessment_accuracy = correct_assessments / total_assessments
        
        if assessment_accuracy >= 0.8:  # At least 80% correct
            criteria_met += 1
            feedback_parts.append(f"✅ Pass/fail logic correct ({correct_assessments}/{total_assessments})")
        elif assessment_accuracy >= 0.6:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Pass/fail logic partially correct ({correct_assessments}/{total_assessments})")
        else:
            feedback_parts.append(f"❌ Pass/fail logic incorrect ({correct_assessments}/{total_assessments})")
        
        # Criterion 7: Check for recommendations if incompatible
        if not overall_should_be_compatible:
            # Should have recommendations
            recommendation_keywords = [
                'convert', 'transcode', 'change', 'resize', 'downscale',
                'mpeg-2', 'mpeg2', '720x480', '720x576', 'ac3', 'mp2'
            ]
            
            has_recommendations = any(kw in report_content.lower() for kw in recommendation_keywords)
            
            # Check if recommendations are specific (mention actual needed changes)
            specific_recommendations = 0
            
            if not resolution_should_pass and ('720' in report_content or 'resize' in report_content.lower()):
                specific_recommendations += 1
            
            if not video_codec_should_pass and ('mpeg' in report_content.lower()):
                specific_recommendations += 1
            
            if not audio_codec_should_pass and ('ac3' in report_content.lower() or 'mp2' in report_content.lower()):
                specific_recommendations += 1
            
            if has_recommendations and specific_recommendations >= 2:
                criteria_met += 1
                feedback_parts.append("✅ Specific recommendations provided")
            elif has_recommendations:
                criteria_met += 0.5
                feedback_parts.append("⚠️ Generic recommendations provided")
            else:
                feedback_parts.append("❌ No conversion recommendations")
        else:
            # File is compatible, should say "ready to burn" or similar
            if any(kw in report_content.lower() for kw in ['ready', 'no conversion', 'none']):
                criteria_met += 1
                feedback_parts.append("✅ Correctly states no conversion needed")
            else:
                criteria_met += 0.5
                feedback_parts.append("⚠️ Should explicitly state ready for DVD")
        
        os.unlink(temp_props.name)
        
    except Exception as e:
        logger.error(f"Error verifying accuracy: {e}", exc_info=True)
        feedback_parts.append(f"⚠️ Error checking accuracy: {str(e)}")
    
    os.unlink(temp_report.name)
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    feedback += f"\n\n📊 Criteria met: {criteria_met:.1f}/{total_criteria} ({score}%)"
    
    if passed:
        feedback += "\n✅ PASS - DVD compatibility report is accurate and complete"
    else:
        feedback += "\n❌ FAIL - Report needs improvement"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }