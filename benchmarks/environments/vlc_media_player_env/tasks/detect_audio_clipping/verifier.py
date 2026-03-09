#!/usr/bin/env python3
"""
Verifier for Detect Audio Clipping task

Checks if agent correctly analyzed audio file for clipping and documented findings.
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


def verify_detect_audio_clipping(traj, env_info, task_info):
    """
    Verify detect audio clipping task completion.
    
    Checks:
    1. Analysis file exists
    2. Clipping detection is correct (YES - there is clipping)
    3. Timestamp information is provided
    4. Peak level information is mentioned
    5. Recommendation is provided and appropriate
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Copy ground truth
    temp_ground_truth = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vlc_clipping_ground_truth.json", temp_ground_truth.name)
        with open(temp_ground_truth.name, 'r') as f:
            ground_truth = json.load(f)
        os.unlink(temp_ground_truth.name)
    except Exception as e:
        logger.error(f"Could not load ground truth: {e}")
        ground_truth = {
            "has_clipping": True,
            "expected_answer": "YES",
            "expected_recommendation": "NEEDS RE-RECORDING"
        }
    
    # Copy and read analysis file
    temp_analysis = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env("/tmp/vlc_clipping_analysis.txt", temp_analysis.name)
        
        with open(temp_analysis.name, 'r') as f:
            analysis_content = f.read()
        
        # Check if file has actual content (not just error message)
        if "ERROR: No analysis file created" in analysis_content:
            feedback_parts.append("❌ Analysis file not created")
            os.unlink(temp_analysis.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Analysis file created")
        
        # Convert to lowercase for case-insensitive matching
        analysis_lower = analysis_content.lower()
        
        logger.info(f"Analysis content:\n{analysis_content}")
        
        # Criterion 2: Check if clipping was correctly identified
        clipping_detected = False
        
        # Look for explicit YES or clear indicators of clipping
        yes_indicators = ["yes", "detected", "present", "found", "clipping occurs", 
                         "is clipping", "has clipping", "clipping detected"]
        no_indicators = ["no clipping", "no clip", "not detected", "clean signal"]
        
        # Check for YES indicators
        for indicator in yes_indicators:
            if indicator in analysis_lower:
                clipping_detected = True
                break
        
        # Check for NO indicators (should override if found)
        for indicator in no_indicators:
            if indicator in analysis_lower:
                clipping_detected = False
                break
        
        # Ground truth: there IS clipping in the file
        correct_detection = clipping_detected == ground_truth["has_clipping"]
        
        if correct_detection:
            criteria_met += 1
            feedback_parts.append("✅ Clipping detection correct: YES")
        else:
            if clipping_detected:
                feedback_parts.append("⚠️ Clipping detection: YES (correct), but unclear")
            else:
                feedback_parts.append("❌ Clipping detection incorrect: Expected YES, got NO")
        
        # Criterion 3: Check if timestamp information is provided
        has_timestamps = False
        timestamp_patterns = [
            r'\d{1,2}:\d{2}',           # MM:SS format
            r'\d+\s*(?:sec|second)',    # N seconds/sec
            r'\d+s\b',                   # Ns format
            r'(?:0:)?1[0-5]',           # 10-15 or 0:10-0:15
            r'around\s+\d+',            # around N seconds
            r'at\s+\d+',                # at N seconds
            r'between\s+\d+',           # between N and M
            r'from\s+\d+',              # from N to M
        ]
        
        for pattern in timestamp_patterns:
            if re.search(pattern, analysis_lower):
                has_timestamps = True
                break
        
        if has_timestamps:
            criteria_met += 1
            feedback_parts.append("✅ Timestamp information provided")
        else:
            feedback_parts.append("⚠️ Timestamp information missing")
        
        # Criterion 4: Check if peak level is mentioned
        has_peak_level = False
        peak_indicators = [
            "0 dbfs", "0dbfs", "0 db", "0db",
            "peak", "full scale", 
            "-3 db", "-6 db", "dbfs",
            "level", "amplitude",
            "maximum", "max level"
        ]
        
        for indicator in peak_indicators:
            if indicator in analysis_lower:
                has_peak_level = True
                break
        
        if has_peak_level:
            criteria_met += 1
            feedback_parts.append("✅ Peak level information included")
        else:
            feedback_parts.append("⚠️ Peak level information missing")
        
        # Criterion 5: Check if recommendation is provided
        has_recommendation = False
        correct_recommendation = False
        
        recommendation_indicators = [
            "re-record", "rerecord", "needs recording", 
            "safe to mix", "safe for mix", "needs re-recording",
            "recommendation", "recommend", "should",
            "redo", "unusable", "usable", "needs work",
            "do not mix", "don't mix"
        ]
        
        for indicator in recommendation_indicators:
            if indicator in analysis_lower:
                has_recommendation = True
                break
        
        if has_recommendation:
            # Check if recommendation is appropriate (should recommend re-recording)
            negative_rec = ["re-record", "rerecord", "needs recording", "redo", 
                           "unusable", "needs work", "do not mix", "don't mix", 
                           "not safe", "needs re-recording"]
            
            for neg in negative_rec:
                if neg in analysis_lower:
                    correct_recommendation = True
                    break
            
            if correct_recommendation:
                criteria_met += 1
                feedback_parts.append("✅ Recommendation appropriate: NEEDS RE-RECORDING")
            else:
                # Partial credit for having a recommendation even if not ideal
                criteria_met += 0.5
                feedback_parts.append("⚠️ Recommendation provided but may be incorrect")
        else:
            feedback_parts.append("⚠️ Recommendation missing")
        
        os.unlink(temp_analysis.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Error reading analysis file: {str(e)}"
        }
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_clipping_completed.txt", temp_marker.name)
        os.unlink(temp_marker.name)
    except Exception:
        logger.warning("Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Verification result: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }