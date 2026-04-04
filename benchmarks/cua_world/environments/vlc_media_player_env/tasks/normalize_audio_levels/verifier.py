#!/usr/bin/env python3
"""
Verifier for VLC audio normalization task.

This verifier checks if the user successfully configured VLC's audio
normalization or dynamic range compression features to handle videos
with drastically different volume levels.

Verification strategy:
1. Parse VLC config file (vlcrc)
2. Check for audio-filter settings (compressor, normvol, etc.)
3. Verify related configuration parameters
4. Accept multiple valid solution approaches
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path using relative path (verifier runs on host)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


def verify_audio_normalization(traj, env_info, task_info):
    """
    Verify that VLC audio normalization/compression has been properly configured.
    
    The task is successful if:
    - VLC config file contains audio filter settings
    - Audio filter includes compressor, normalizer, or related effects
    - Settings are properly configured (not just present but disabled)
    
    Args:
        traj: Agent trajectory (not used in this verification)
        env_info: Environment info with copy_from_env function
        task_info: Task information (not used)
        
    Returns:
        dict: Verification result with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    solution_details = []
    
    try:
        # Copy VLC config file
        temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        vlcrc_path = temp_vlcrc.name
        temp_vlcrc.close()
        
        try:
            copy_from_env("/tmp/vlc_audio_norm_vlcrc.txt", vlcrc_path)
            logger.info(f"✓ Copied VLC config file to {vlcrc_path}")
        except Exception as e:
            logger.error(f"Failed to copy VLC config: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"VLC config file not found or inaccessible: {str(e)}"
            }
        
        # Parse VLC configuration
        config = parse_vlc_config(vlcrc_path)
        
        if not config:
            logger.warning("VLC config is empty or failed to parse")
            os.unlink(vlcrc_path)
            return {
                "passed": False,
                "score": 0,
                "feedback": "VLC config file is empty or corrupted"
            }
        
        # Criterion 1: Config file is accessible and parseable
        criteria_met += 1
        feedback_parts.append(f"✅ Config accessible ({len(config)} entries)")
        logger.info(f"✓ Parsed VLC config with {len(config)} entries")
        
        # Check for audio normalization/compression settings
        # Multiple solution approaches are acceptable:
        
        # Solution 1: Compressor filter in audio-filter
        audio_filter = config.get('audio-filter', '')
        if audio_filter:
            logger.info(f"Found audio-filter setting: {audio_filter}")
            
            if 'compressor' in audio_filter.lower():
                solution_details.append("compressor_in_audio_filter")
                criteria_met += 1
                feedback_parts.append("✅ Compressor filter enabled")
                logger.info("✓ Solution: Compressor filter enabled in audio-filter")
            
            # Solution 2: Volume normalizer
            if 'normvol' in audio_filter.lower() or 'volnorm' in audio_filter.lower():
                solution_details.append("volume_normalizer_in_audio_filter")
                criteria_met += 1
                feedback_parts.append("✅ Volume normalizer enabled")
                logger.info("✓ Solution: Volume normalizer enabled in audio-filter")
            
            # Solution 3: Generic relevant filter
            if any(term in audio_filter.lower() for term in ['norm', 'compress', 'dynamic', 'limiter']):
                if not solution_details:  # Only count if no other solution found
                    solution_details.append("relevant_audio_filter")
                    criteria_met += 1
                    feedback_parts.append(f"✅ Audio filter enabled: {audio_filter}")
                    logger.info(f"✓ Solution: Relevant audio filter - {audio_filter}")
        
        # Solution 4: Check for standalone normalization settings
        if 'norm-max-level' in config:
            norm_level = config.get('norm-max-level')
            solution_details.append(f"norm_max_level={norm_level}")
            if criteria_met < 2:  # Give credit if not already awarded
                criteria_met += 1
            feedback_parts.append(f"✅ Norm max level configured: {norm_level}")
            logger.info(f"✓ Solution: Normalization max level set to {norm_level}")
        
        # Solution 5: Check for compressor-specific settings
        compressor_settings = []
        for key in ['compressor-rms-peak', 'compressor-attack', 'compressor-release', 
                    'compressor-threshold', 'compressor-ratio', 'compressor-knee',
                    'compressor-makeup-gain']:
            if key in config:
                compressor_settings.append(f"{key}={config[key]}")
        
        if compressor_settings:
            solution_details.append("compressor_configured")
            if criteria_met < 2:  # Give credit if not already awarded
                criteria_met += 1
            feedback_parts.append(f"✅ Compressor settings: {len(compressor_settings)} parameters")
            logger.info(f"✓ Solution: Compressor configured with {len(compressor_settings)} settings")
        
        # Solution 6: Check for audio time-stretch (related to normalization)
        if 'audio-time-stretch' in config:
            audio_stretch = config.get('audio-time-stretch')
            solution_details.append(f"audio_time_stretch={audio_stretch}")
            logger.info(f"Found audio-time-stretch: {audio_stretch}")
        
        # Final assessment: Did we find any valid solution?
        if solution_details:
            # At least one solution approach was found
            if criteria_met >= 2:
                # Strong evidence of proper configuration
                criteria_met = 3  # Award full marks
                feedback_parts.append(f"✅ Valid solution implemented ({len(solution_details)} indicators)")
                logger.info(f"✓ PASS: Valid audio normalization configured - {solution_details}")
            else:
                # Partial configuration
                feedback_parts.append(f"⚠️ Partial configuration detected")
                logger.warning(f"Partial solution: {solution_details}")
        else:
            # No audio normalization found
            if audio_filter:
                feedback_parts.append(f"❌ Audio filter present but not normalization-related: {audio_filter}")
            else:
                feedback_parts.append("❌ No audio normalization or compression configured")
            logger.warning("✗ FAIL: No audio normalization solution found")
        
        # Cleanup temp file
        os.unlink(vlcrc_path)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification exception: {str(e)}"
        }
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    # Add helpful hint if failed
    if not passed:
        feedback += " | Hint: Enable audio filter via Tools→Effects and Filters→Audio Effects→Compressor"
    
    result = {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
    
    # Add debug info
    if solution_details:
        result["solutions_found"] = solution_details
    
    logger.info(f"Final result: passed={passed}, score={score}")
    logger.info(f"Feedback: {feedback}")
    
    return result


def main():
    """
    Test the verifier locally with a sample config file.
    Usage: python verifier.py [path_to_vlcrc]
    """
    print("="*70)
    print("VLC Audio Normalization Task Verifier - Local Test Mode")
    print("="*70)
    
    # Mock env_info for local testing
    if len(sys.argv) > 1:
        test_file = sys.argv[1]
        print(f"\nTesting with config file: {test_file}")
        
        def mock_copy(src, dst):
            import shutil
            shutil.copy(test_file, dst)
        
        env_info = {'copy_from_env': mock_copy}
    else:
        print("\nNo test file provided. Creating mock config for demonstration...")
        
        # Create a temporary test config
        test_config = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt')
        test_config.write("# VLC Configuration\n")
        test_config.write("audio-filter=compressor\n")
        test_config.write("compressor-rms-peak=0.0\n")
        test_config.write("compressor-attack=1.4\n")
        test_config.write("compressor-release=400.0\n")
        test_config.write("compressor-threshold=-20.0\n")
        test_config.write("compressor-ratio=6.0\n")
        test_config.close()
        
        def mock_copy(src, dst):
            import shutil
            shutil.copy(test_config.name, dst)
        
        env_info = {'copy_from_env': mock_copy}
        print(f"Created test config: {test_config.name}")
    
    # Run verification
    result = verify_audio_normalization(None, env_info, None)
    
    print("\n" + "="*70)
    print("VERIFICATION RESULT")
    print("="*70)
    print(f"Passed: {result['passed']}")
    print(f"Score:  {result['score']}/100")
    print(f"Feedback: {result['feedback']}")
    
    if 'solutions_found' in result:
        print(f"Solutions: {result['solutions_found']}")
    
    print("="*70)
    
    sys.exit(0 if result['passed'] else 1)
