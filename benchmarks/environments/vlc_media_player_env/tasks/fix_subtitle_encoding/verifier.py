#!/usr/bin/env python3
"""
Verifier for Fix Subtitle Encoding task
Checks if subtitle encoding issue was resolved via config OR file conversion
"""

import sys
import os
import logging
import tempfile
import json
import re

# Use relative path to utils folder (verifier runs on host)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fix_subtitle_encoding(traj, env_info, task_info):
    """
    Verify subtitle encoding fix task completion.
    
    Checks:
    1. VLC config has Shift-JIS encoding setting OR UTF-8 subtitle file exists
    2. If file conversion: file contains valid Japanese characters
    3. If file conversion: subtitle structure is preserved (5 entries)
    
    Returns:
        dict: {passed, score, feedback}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # ========================================
    # Load result summary
    # ========================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_subtitle_encoding_result.json", temp_result.name)
        
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        vlcrc_encoding = result.get('vlcrc_encoding', '')
        converted_file_found = result.get('converted_file_found', False)
        config_approach = result.get('config_approach', False)
        conversion_approach = result.get('conversion_approach', False)
        
        os.unlink(temp_result.name)
        
    except Exception as e:
        logger.error(f"Error reading result summary: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}
    
    # ========================================
    # Check Approach A: VLC Configuration
    # ========================================
    config_success = False
    
    if config_approach and vlcrc_encoding:
        # Check if encoding is set to Shift-JIS (various formats accepted)
        if re.search(r'shift[-_]?jis|sjis', vlcrc_encoding, re.IGNORECASE):
            config_success = True
            criteria_met += 3  # Award all points for config approach
            feedback_parts.append(f"✅ VLC configured to use {vlcrc_encoding} encoding")
            feedback_parts.append("✅ Subtitles will display correctly with this encoding")
        else:
            feedback_parts.append(f"⚠️ VLC encoding set to '{vlcrc_encoding}' (not Shift-JIS)")
    
    # ========================================
    # Check Approach B: File Conversion
    # ========================================
    conversion_success = False
    
    if conversion_approach and not config_success:
        # Copy and verify the converted file
        temp_srt = tempfile.NamedTemporaryFile(delete=False, suffix='.srt')
        
        try:
            copy_from_env("/tmp/vlc_subtitle_converted.srt", temp_srt.name)
            
            with open(temp_srt.name, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Criterion 1: File exists and is UTF-8
            criteria_met += 1
            feedback_parts.append("✅ UTF-8 subtitle file found")
            
            # Criterion 2: Contains valid Japanese characters
            # Check for hiragana, katakana, or kanji
            if re.search(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]', content):
                criteria_met += 1
                feedback_parts.append("✅ File contains valid Japanese characters")
                
                # Criterion 3: Subtitle structure preserved
                # Count subtitle entries (lines with just numbers)
                entry_count = len(re.findall(r'^\d+$', content, re.MULTILINE))
                
                if entry_count >= 4:  # Allow some tolerance (expected 5)
                    criteria_met += 1
                    feedback_parts.append(f"✅ Subtitle structure preserved ({entry_count} entries)")
                    conversion_success = True
                else:
                    feedback_parts.append(f"⚠️ Subtitle structure incomplete ({entry_count} entries, expected 5)")
            else:
                feedback_parts.append("❌ File missing Japanese characters (may still be garbled)")
            
            os.unlink(temp_srt.name)
            
        except UnicodeDecodeError:
            feedback_parts.append("❌ Converted file is not valid UTF-8")
            os.unlink(temp_srt.name)
        except Exception as e:
            logger.error(f"Error reading converted file: {e}", exc_info=True)
            feedback_parts.append(f"⚠️ Error reading converted file: {e}")
            if os.path.exists(temp_srt.name):
                os.unlink(temp_srt.name)
    
    # ========================================
    # Check encoding info file for additional context
    # ========================================
    temp_encoding_info = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_subtitle_encoding_info.txt", temp_encoding_info.name)
        
        with open(temp_encoding_info.name, 'r') as f:
            encoding_info = f.read()
        
        # Just for logging, not scoring
        logger.info(f"Encoding info: {encoding_info}")
        
        os.unlink(temp_encoding_info.name)
    except Exception:
        pass  # Optional file
    
    # ========================================
    # Final Decision
    # ========================================
    
    if config_success or conversion_success:
        success = True
        reward = 1.0
        
        if config_success and conversion_approach:
            approach_msg = "🎉 Excellent! Both VLC configuration AND file conversion approaches succeeded!"
        elif config_success:
            approach_msg = "🎯 VLC configuration approach succeeded!"
        else:
            approach_msg = "🎯 File conversion approach succeeded!"
        
        feedback = f"{approach_msg}\n\n" + "\n".join(feedback_parts)
        
    else:
        success = False
        reward = 0.0
        
        feedback = "❌ Subtitle encoding issue not resolved.\n\n"
        feedback += "Expected one of these solutions:\n"
        feedback += "1. Configure VLC to use Shift-JIS encoding:\n"
        feedback += "   Tools → Preferences → All → Input/Codecs → Subtitles → 'Subtitle text encoding' = Shift-JIS\n\n"
        feedback += "2. Convert subtitle file to UTF-8:\n"
        feedback += "   iconv -f SHIFT-JIS -t UTF-8 subtitles_broken.srt > subtitles_fixed.srt\n\n"
        
        if feedback_parts:
            feedback += "Observations:\n" + "\n".join(feedback_parts)
        else:
            feedback += "No evidence of attempted solution found."
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    
    return {
        "passed": success,
        "score": score,
        "feedback": feedback
    }
