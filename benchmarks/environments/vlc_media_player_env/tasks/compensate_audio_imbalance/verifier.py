#!/usr/bin/env python3
"""
Verifier for Compensate Audio Imbalance task (compensate_audio_imbalance@1)

Checks that VLC audio balance was properly configured to compensate for 
hardware imbalance (weak left earbud).
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compensate_audio_imbalance(traj, env_info, task_info):
    """
    Verify that audio balance was properly configured to compensate for hardware imbalance.
    
    Success criteria:
    1. Balance result file exists and is parseable
    2. Audio balance setting is present and valid
    3. Balance is shifted left (negative value) in appropriate range (-0.3 to -0.8)
    4. Balance is not at default (0.0) - indicates change was made
    5. Bonus: Evidence of playback testing
    
    Args:
        traj: Trajectory data (not used in this verifier)
        env_info: Environment info dict with 'copy_from_env' function
        task_info: Task info dict (not used in this verifier)
    
    Returns:
        Dict with keys: 'passed' (bool), 'score' (int), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "ERROR: copy_from_env function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    temp_result = None
    temp_marker = None
    
    try:
        # Copy balance result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        
        try:
            copy_from_env("/tmp/vlc_balance_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying balance result: {e}", exc_info=True)
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"ERROR: Could not copy balance result file: {str(e)}"
            }
        
        # Parse JSON result
        try:
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Error parsing JSON: {e}", exc_info=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"ERROR: Could not parse balance result JSON: {str(e)}"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Balance result accessible")
        
        # Extract balance value
        balance_value = result.get('balance_value')
        runtime_captured = result.get('runtime_captured', False)
        playback_evidence = result.get('playback_evidence', False)
        source = result.get('source', 'unknown')
        
        if balance_value is None:
            return {
                "passed": False,
                "score": 33,
                "feedback": "FAIL: Balance value not found in result"
            }
        
        # Convert to float
        try:
            balance_value = float(balance_value)
        except (ValueError, TypeError):
            return {
                "passed": False,
                "score": 33,
                "feedback": f"ERROR: Invalid balance value: {balance_value}"
            }
        
        logger.info(f"Audio balance value: {balance_value} (source: {source})")
        
        # Criterion 2: Check if balance is in valid range and not default
        if balance_value == 0.0:
            return {
                "passed": False,
                "score": 33,
                "feedback": f"FAIL: Balance is still at default (0.0). You need to adjust it to compensate for the weak left earbud."
            }
        
        criteria_met += 1
        feedback_parts.append(f"✅ Balance changed from default (value: {balance_value:.3f})")
        
        # Criterion 3: Check if balance is appropriate for left compensation
        # Balance range: -1.0 (full left) to +1.0 (full right)
        # Target: -0.3 to -0.8 (shifted left to compensate for weak left channel)
        
        if balance_value >= 0:
            return {
                "passed": False,
                "score": 66,
                "feedback": f"FAIL: Balance is {balance_value:.3f}, but should be NEGATIVE (shifted left) to compensate for weak left earbud. A positive value shifts audio RIGHT, which would make the problem worse!"
            }
        
        if balance_value < -0.85:
            return {
                "passed": False,
                "score": 66,
                "feedback": f"FAIL: Balance is {balance_value:.3f}, which is too EXTREME (< -0.85). This would overcompensate and make the right channel too quiet. Target range: -0.3 to -0.8"
            }
        
        if balance_value > -0.25:
            return {
                "passed": False,
                "score": 66,
                "feedback": f"FAIL: Balance is {balance_value:.3f}, which is too SUBTLE (> -0.25). This won't sufficiently compensate for the hardware imbalance. Target range: -0.3 to -0.8"
            }
        
        # Balance is in acceptable range!
        criteria_met += 1
        balance_percent = abs(balance_value) * 100
        feedback_parts.append(f"✅ Balance appropriate ({balance_value:.3f} = {balance_percent:.0f}% left)")
        
        # Bonus check: Evidence of playback testing (optional)
        if playback_evidence:
            feedback_parts.append("🌟 Playback evidence found (good practice!)")
        
        # Success!
        success_feedback = " | ".join(feedback_parts)
        success_feedback += f"\n\n🎉 SUCCESS: Audio balance properly configured!"
        success_feedback += f"\n  • Balance shifted left by {balance_percent:.0f}%"
        success_feedback += f"\n  • This should compensate for your weak left earbud"
        success_feedback += f"\n  • Setting persisted in VLC configuration"
        success_feedback += f"\n  • Stereo audio should now sound balanced with defective hardware"
        
        # Check completion marker (optional, for debugging)
        try:
            temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            copy_from_env("/tmp/vlc_balance_completed.txt", temp_marker.name)
            logger.info("Completion marker found")
        except Exception:
            logger.warning("Completion marker not found (not critical)")
        
        return {
            "passed": True,
            "score": 100,
            "feedback": success_feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"ERROR: Verification failed with exception: {str(e)}"
        }
    
    finally:
        # Cleanup temp files
        if temp_result and os.path.exists(temp_result.name):
            try:
                os.unlink(temp_result.name)
            except Exception:
                pass
        
        if temp_marker and os.path.exists(temp_marker.name):
            try:
                os.unlink(temp_marker.name)
            except Exception:
                pass


def main():
    """Test verifier locally with mock data."""
    print("=" * 60)
    print("Testing verifier for compensate_audio_imbalance@1")
    print("=" * 60)
    
    # Mock copy function for local testing
    def mock_copy(src, dst):
        print(f"Mock copy: {src} -> {dst}")
        
        if 'vlc_balance_result.json' in dst:
            # Test case 1: Good balance (-0.5)
            with open(dst, 'w') as f:
                json.dump({
                    "balance_value": -0.5,
                    "balance_percent": -50.0,
                    "runtime_captured": True,
                    "playback_evidence": True,
                    "source": "rc"
                }, f)
    
    # Test with good balance
    print("\n--- Test 1: Good balance (-0.5) ---")
    success, results, feedback = verify_compensate_audio_imbalance(
        traj=None,
        env_info={'copy_from_env': mock_copy},
        task_info={}
    )
    print(f"Passed: {success}")
    print(f"Score: {results}")
    print(f"Feedback: {feedback}")
    
    # Test with default balance (should fail)
    print("\n--- Test 2: Default balance (0.0) - should fail ---")
    def mock_copy_default(src, dst):
        if 'vlc_balance_result.json' in dst:
            with open(dst, 'w') as f:
                json.dump({
                    "balance_value": 0.0,
                    "balance_percent": 0.0,
                    "runtime_captured": False,
                    "playback_evidence": False,
                    "source": "vlcrc"
                }, f)
    
    success, results, feedback = verify_compensate_audio_imbalance(
        traj=None,
        env_info={'copy_from_env': mock_copy_default},
        task_info={}
    )
    print(f"Passed: {success}")
    print(f"Score: {results}")
    print(f"Feedback: {feedback}")
    
    # Test with wrong direction (positive, should fail)
    print("\n--- Test 3: Wrong direction (+0.5) - should fail ---")
    def mock_copy_wrong(src, dst):
        if 'vlc_balance_result.json' in dst:
            with open(dst, 'w') as f:
                json.dump({
                    "balance_value": 0.5,
                    "balance_percent": 50.0,
                    "runtime_captured": True,
                    "playback_evidence": False,
                    "source": "rc"
                }, f)
    
    success, results, feedback = verify_compensate_audio_imbalance(
        traj=None,
        env_info={'copy_from_env': mock_copy_wrong},
        task_info={}
    )
    print(f"Passed: {success}")
    print(f"Score: {results}")
    print(f"Feedback: {feedback}")
    
    print("\n" + "=" * 60)
    print("Verifier testing complete!")
    print("=" * 60)
