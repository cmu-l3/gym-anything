#!/usr/bin/env python3
"""
Verifier for split_segment_scissors task.

VERIFICATION STRATEGY:
1. Multiple segments exist (25 points) - at least 2 liver-related segments
2. Reasonable split ratio (25 points) - each segment is 20-80% of combined volume
3. Volume conservation (20 points) - combined volume ≈ original (within 20%)
4. Minimal overlap (15 points) - segment intersection is minimal
5. Visual confirmation (10 points) - VLM confirms two distinct liver portions visible
6. Proper naming (5 points) - segments have descriptive names

Pass threshold: 65 points with multiple_segments AND reasonable_split criteria met

CRITICAL: Uses copy_from_env (NOT exec_in_env) and trajectory frames for VLM.
"""

import json
import os
import tempfile
import logging
from typing import Tuple, Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_split_segment_scissors(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify the split segment scissors task.
    
    Args:
        traj: Trajectory data with screenshots
        env_info: Environment info with copy_from_env function
        task_info: Task metadata
    
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Framework error: copy_from_env not available"
        }
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    min_split = metadata.get('min_split_ratio', 0.20)
    max_split = metadata.get('max_split_ratio', 0.80)
    conservation_min = metadata.get('volume_conservation_min', 0.80)
    conservation_max = metadata.get('volume_conservation_max', 1.20)
    max_overlap = metadata.get('max_overlap_fraction', 0.10)
    
    weights = metadata.get('scoring_weights', {
        'multiple_segments': 25,
        'reasonable_split': 25,
        'volume_conservation': 20,
        'minimal_overlap': 15,
        'visual_confirmation': 10,
        'proper_naming': 5
    })
    
    score = 0
    feedback_parts = []
    details = {
        "criteria": {},
        "errors": [],
        "warnings": []
    }
    
    # ================================================================
    # COPY RESULT JSON FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    
    try:
        copy_from_env("/tmp/scissors_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export script may have failed",
            "details": {"error": "No result file"}
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result: {e}",
            "details": {"error": str(e)}
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CHECK BASIC STATE
    # ================================================================
    if not result.get('slicer_running', False):
        details["errors"].append("Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: 3D Slicer was not running",
            "details": details
        }
    
    if not result.get('segmentation_found', False):
        details["errors"].append("No segmentation node found")
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: No segmentation found in scene",
            "details": details
        }
    
    # Store segment info
    segments = result.get('segments', [])
    liver_segment_count = result.get('liver_segment_count', 0)
    details["segment_count"] = result.get('segment_count', 0)
    details["liver_segment_count"] = liver_segment_count
    details["segments"] = segments
    
    # ================================================================
    # CRITERION 1: Multiple Segments Exist (25 points)
    # ================================================================
    w_multiple = weights.get('multiple_segments', 25)
    
    if liver_segment_count >= 2:
        score += w_multiple
        details["criteria"]["multiple_segments"] = {
            "passed": True,
            "points": w_multiple,
            "message": f"Found {liver_segment_count} liver segments"
        }
        feedback_parts.append(f"✓ Multiple segments: {liver_segment_count} liver segments (+{w_multiple})")
    elif liver_segment_count == 1:
        # Partial credit if there are multiple segments but only one named liver
        total_segments = result.get('segment_count', 0)
        if total_segments >= 2:
            partial = w_multiple // 2
            score += partial
            details["criteria"]["multiple_segments"] = {
                "passed": "partial",
                "points": partial,
                "message": f"Found {total_segments} segments but only {liver_segment_count} named as liver"
            }
            feedback_parts.append(f"~ Partial: {total_segments} segments exist but naming unclear (+{partial})")
        else:
            details["criteria"]["multiple_segments"] = {
                "passed": False,
                "points": 0,
                "message": "Only 1 liver segment found, need at least 2"
            }
            feedback_parts.append("✗ Multiple segments: Only 1 liver segment found")
    else:
        details["criteria"]["multiple_segments"] = {
            "passed": False,
            "points": 0,
            "message": f"No liver segments found (total segments: {result.get('segment_count', 0)})"
        }
        feedback_parts.append("✗ Multiple segments: No liver segments found")
        details["errors"].append("No liver segments created")
    
    # ================================================================
    # CRITERION 2: Reasonable Split Ratio (25 points)
    # ================================================================
    w_split = weights.get('reasonable_split', 25)
    split_ratio = result.get('split_ratio', 0)
    details["split_ratio"] = split_ratio
    
    # split_ratio is smaller_volume / total_volume, so range is 0.0 to 0.5
    # A good split would be 0.25-0.50 (meaning 25-50% for smaller piece)
    # We accept 0.20-0.50 (allowing some asymmetry)
    
    if 0.20 <= split_ratio <= 0.50:
        score += w_split
        pct = split_ratio * 100
        details["criteria"]["reasonable_split"] = {
            "passed": True,
            "points": w_split,
            "message": f"Split ratio {pct:.1f}% / {100-pct:.1f}% is acceptable"
        }
        feedback_parts.append(f"✓ Reasonable split: {pct:.1f}% / {100-pct:.1f}% (+{w_split})")
    elif 0.10 <= split_ratio < 0.20 or 0.50 < split_ratio <= 0.60:
        # Marginal split - partial credit
        partial = w_split // 2
        score += partial
        pct = split_ratio * 100
        details["criteria"]["reasonable_split"] = {
            "passed": "partial",
            "points": partial,
            "message": f"Split ratio {pct:.1f}% is marginal"
        }
        feedback_parts.append(f"~ Marginal split: {pct:.1f}% (+{partial})")
    else:
        pct = split_ratio * 100 if split_ratio > 0 else 0
        details["criteria"]["reasonable_split"] = {
            "passed": False,
            "points": 0,
            "message": f"Split ratio {pct:.1f}% is outside acceptable range (20-50%)"
        }
        feedback_parts.append(f"✗ Uneven split: {pct:.1f}%")
    
    # ================================================================
    # CRITERION 3: Volume Conservation (20 points)
    # ================================================================
    w_conservation = weights.get('volume_conservation', 20)
    conservation_ratio = result.get('volume_conservation_ratio', 0)
    original_vol = result.get('original_liver_volume_cm3', 0)
    total_vol = result.get('total_liver_volume_cm3', 0)
    
    details["original_volume_cm3"] = original_vol
    details["total_volume_cm3"] = total_vol
    details["conservation_ratio"] = conservation_ratio
    
    if conservation_min <= conservation_ratio <= conservation_max:
        score += w_conservation
        details["criteria"]["volume_conservation"] = {
            "passed": True,
            "points": w_conservation,
            "message": f"Volume conservation: {conservation_ratio*100:.1f}%"
        }
        feedback_parts.append(f"✓ Volume conserved: {conservation_ratio*100:.1f}% (+{w_conservation})")
    elif 0.65 <= conservation_ratio < conservation_min or conservation_max < conservation_ratio <= 1.40:
        # Marginal conservation
        partial = w_conservation // 2
        score += partial
        details["criteria"]["volume_conservation"] = {
            "passed": "partial",
            "points": partial,
            "message": f"Volume conservation: {conservation_ratio*100:.1f}% is marginal"
        }
        feedback_parts.append(f"~ Volume partially conserved: {conservation_ratio*100:.1f}% (+{partial})")
    else:
        details["criteria"]["volume_conservation"] = {
            "passed": False,
            "points": 0,
            "message": f"Volume conservation: {conservation_ratio*100:.1f}% outside range"
        }
        if conservation_ratio > 0:
            feedback_parts.append(f"✗ Volume not conserved: {conservation_ratio*100:.1f}%")
        else:
            feedback_parts.append("✗ Volume conservation: Could not calculate")
    
    # ================================================================
    # CRITERION 4: Minimal Overlap (15 points)
    # ================================================================
    w_overlap = weights.get('minimal_overlap', 15)
    overlap_fraction = result.get('overlap_fraction', 0)
    details["overlap_fraction"] = overlap_fraction
    
    if overlap_fraction < 0.05:
        score += w_overlap
        details["criteria"]["minimal_overlap"] = {
            "passed": True,
            "points": w_overlap,
            "message": f"Overlap: {overlap_fraction*100:.1f}% (acceptable: <5%)"
        }
        feedback_parts.append(f"✓ Minimal overlap: {overlap_fraction*100:.1f}% (+{w_overlap})")
    elif overlap_fraction < max_overlap:
        partial = int(w_overlap * 0.6)
        score += partial
        details["criteria"]["minimal_overlap"] = {
            "passed": "partial",
            "points": partial,
            "message": f"Overlap: {overlap_fraction*100:.1f}% is moderate"
        }
        feedback_parts.append(f"~ Moderate overlap: {overlap_fraction*100:.1f}% (+{partial})")
    else:
        details["criteria"]["minimal_overlap"] = {
            "passed": False,
            "points": 0,
            "message": f"Overlap: {overlap_fraction*100:.1f}% exceeds {max_overlap*100:.0f}%"
        }
        feedback_parts.append(f"✗ Excessive overlap: {overlap_fraction*100:.1f}%")
    
    # ================================================================
    # CRITERION 5: Visual Confirmation via VLM (10 points)
    # ================================================================
    w_visual = weights.get('visual_confirmation', 10)
    
    # Try to use VLM on trajectory frames
    vlm_query = env_info.get('vlm_query')
    
    if vlm_query and traj:
        try:
            # Get trajectory frames (sample across trajectory)
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                vlm_prompt = """Analyze these 3D Slicer screenshots showing a liver segmentation task.

The agent was asked to SPLIT a liver segmentation into TWO separate segments using the Scissors tool.

Look at the trajectory and final state:
1. Are there TWO DISTINCT colored liver regions visible in the 3D view?
2. Does the segmentation appear to have been SPLIT (not just one solid liver)?
3. Is there evidence the Scissors tool was used (segment editor, cutting action)?

Respond in JSON format:
{
    "two_liver_portions_visible": true/false,
    "split_appears_complete": true/false,
    "scissors_tool_evidence": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                
                images_to_check = (frames or []) + ([final_frame] if final_frame else [])
                vlm_result = vlm_query(prompt=vlm_prompt, images=images_to_check)
                
                details["vlm_response"] = vlm_result
                
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    two_visible = parsed.get("two_liver_portions_visible", False)
                    split_complete = parsed.get("split_appears_complete", False)
                    confidence = parsed.get("confidence", "low")
                    
                    if two_visible and split_complete:
                        points = w_visual if confidence == "high" else int(w_visual * 0.7)
                        score += points
                        details["criteria"]["visual_confirmation"] = {
                            "passed": True,
                            "points": points,
                            "message": f"VLM confirms split visible ({confidence} confidence)"
                        }
                        feedback_parts.append(f"✓ VLM confirms split visible (+{points})")
                    elif two_visible or split_complete:
                        partial = int(w_visual * 0.5)
                        score += partial
                        details["criteria"]["visual_confirmation"] = {
                            "passed": "partial",
                            "points": partial,
                            "message": "VLM partially confirms split"
                        }
                        feedback_parts.append(f"~ VLM partial confirmation (+{partial})")
                    else:
                        details["criteria"]["visual_confirmation"] = {
                            "passed": False,
                            "points": 0,
                            "message": "VLM did not confirm split"
                        }
                        feedback_parts.append("✗ VLM did not confirm split visible")
                else:
                    # VLM query failed
                    details["warnings"].append("VLM query did not return valid result")
                    # Give partial credit if other criteria passed
                    if liver_segment_count >= 2 and split_ratio >= 0.15:
                        partial = int(w_visual * 0.3)
                        score += partial
                        details["criteria"]["visual_confirmation"] = {
                            "passed": "partial",
                            "points": partial,
                            "message": "VLM unavailable, partial credit from other criteria"
                        }
                        feedback_parts.append(f"~ VLM unavailable, partial credit (+{partial})")
                    else:
                        details["criteria"]["visual_confirmation"] = {
                            "passed": False,
                            "points": 0,
                            "message": "VLM unavailable"
                        }
            else:
                details["warnings"].append("No trajectory frames available")
                details["criteria"]["visual_confirmation"] = {
                    "passed": False,
                    "points": 0,
                    "message": "No screenshots available for VLM"
                }
                
        except ImportError:
            # VLM module not available - give partial credit if other criteria pass
            if liver_segment_count >= 2 and split_ratio >= 0.15:
                partial = int(w_visual * 0.4)
                score += partial
                details["criteria"]["visual_confirmation"] = {
                    "passed": "partial",
                    "points": partial,
                    "message": "VLM not available, partial credit"
                }
                feedback_parts.append(f"~ VLM module unavailable (+{partial})")
            else:
                details["criteria"]["visual_confirmation"] = {
                    "passed": False,
                    "points": 0,
                    "message": "VLM module not available"
                }
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            details["warnings"].append(f"VLM error: {str(e)}")
            details["criteria"]["visual_confirmation"] = {
                "passed": False,
                "points": 0,
                "message": f"VLM error: {str(e)}"
            }
    else:
        # No VLM available - give partial credit if programmatic criteria pass
        if liver_segment_count >= 2 and split_ratio >= 0.15:
            partial = int(w_visual * 0.4)
            score += partial
            details["criteria"]["visual_confirmation"] = {
                "passed": "partial",
                "points": partial,
                "message": "VLM unavailable, partial credit from metrics"
            }
            feedback_parts.append(f"~ VLM unavailable, partial credit (+{partial})")
        else:
            details["criteria"]["visual_confirmation"] = {
                "passed": False,
                "points": 0,
                "message": "VLM not available"
            }
    
    # ================================================================
    # CRITERION 6: Proper Naming (5 points)
    # ================================================================
    w_naming = weights.get('proper_naming', 5)
    
    descriptive_names = False
    liver_segments = [s for s in segments if 'liver' in s.get('name', '').lower()]
    
    for seg in liver_segments:
        name = seg.get('name', '').lower()
        # Check for descriptive terms
        if any(term in name for term in ['right', 'left', 'lobe', 'portion', 'part', 'half', 'segment']):
            descriptive_names = True
            break
    
    # Also accept if segments are numbered distinctly
    if not descriptive_names and len(liver_segments) >= 2:
        names = [s.get('name', '') for s in liver_segments]
        if len(set(names)) >= 2:  # At least 2 unique names
            descriptive_names = True
    
    if descriptive_names:
        score += w_naming
        details["criteria"]["proper_naming"] = {
            "passed": True,
            "points": w_naming,
            "message": "Segments have descriptive names"
        }
        feedback_parts.append(f"✓ Descriptive segment names (+{w_naming})")
    else:
        details["criteria"]["proper_naming"] = {
            "passed": False,
            "points": 0,
            "message": "Segments do not have descriptive names"
        }
        feedback_parts.append("✗ Segments not descriptively named")
    
    # ================================================================
    # FINAL ASSESSMENT
    # ================================================================
    details["final_score"] = score
    
    # Determine pass/fail
    # Must have: multiple_segments passed AND reasonable_split passed (at least partial)
    multiple_passed = details["criteria"].get("multiple_segments", {}).get("passed", False)
    split_passed = details["criteria"].get("reasonable_split", {}).get("passed", False)
    
    key_criteria_met = (multiple_passed in [True, "partial"]) and (split_passed in [True, "partial"])
    passed = score >= 65 and key_criteria_met
    
    details["passed"] = passed
    details["key_criteria_met"] = key_criteria_met
    
    # Build feedback string
    if passed:
        feedback_parts.insert(0, f"PASS: Score {score}/100")
    else:
        if not key_criteria_met:
            feedback_parts.insert(0, f"FAIL: Score {score}/100 (key criteria not met)")
        else:
            feedback_parts.insert(0, f"FAIL: Score {score}/100 (need 65+)")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }


def main():
    """Test the verifier locally with mock data."""
    # Mock copy function for testing
    def mock_copy(src, dst):
        import shutil
        if os.path.exists(src):
            shutil.copy(src, dst)
        else:
            raise FileNotFoundError(f"Source not found: {src}")
    
    # Create mock result for testing
    mock_result = {
        "slicer_running": True,
        "segmentation_found": True,
        "segment_count": 2,
        "liver_segment_count": 2,
        "segments": [
            {"id": "seg1", "name": "Liver_Right", "volume_cm3": 800},
            {"id": "seg2", "name": "Liver_Left", "volume_cm3": 600}
        ],
        "total_liver_volume_cm3": 1400,
        "original_liver_volume_cm3": 1350,
        "volume_conservation_ratio": 1.037,
        "split_ratio": 0.428,  # 600 / 1400
        "overlap_fraction": 0.02
    }
    
    os.makedirs("/tmp", exist_ok=True)
    with open("/tmp/scissors_task_result.json", "w") as f:
        json.dump(mock_result, f)
    
    result = verify_split_segment_scissors(
        traj=None,
        env_info={"copy_from_env": mock_copy},
        task_info={"metadata": {}}
    )
    
    print(f"Score: {result['score']}")
    print(f"Passed: {result['passed']}")
    print(f"Feedback:\n{result['feedback']}")
    print(f"\nDetails: {json.dumps(result['details'], indent=2)}")


if __name__ == "__main__":
    main()