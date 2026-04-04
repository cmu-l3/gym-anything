#!/usr/bin/env python3
"""
Verifier for load_sample_data task.

HYBRID VERIFICATION: Combines programmatic checks with VLM-based visual verification.

Programmatic checks:
- Slicer running
- Sample file exists
- Volume loaded via Slicer API

VLM checks:
- Brain scan visible in slice views
- Slicer UI in normal state (no error dialogs)
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)



def build_brain_scan_prompt():
    """Build VLM prompt to verify brain scan is visible in 3D Slicer."""
    return """Examine this 3D Slicer screenshot carefully.

Task: Verify that a brain MRI scan (MRHead) has been loaded and is visible.

Check for these indicators:

1. SLICE VIEWS: Are there 2D slice views showing grayscale medical imaging data?
   - Look for axial, sagittal, or coronal views (typically in red, green, yellow bordered panels)
   - Brain tissue should appear as varying shades of gray
   - Empty slice views are pure black with only axis markers

2. DATA VISIBILITY: Is actual brain scan data visible?
   - You should see brain tissue structure (gray/white matter)
   - NOT just an empty welcome screen
   - NOT just the Slicer UI without data

3. APPLICATION STATE: Is 3D Slicer in a functional state?
   - No error dialogs blocking the view
   - Main window visible (not minimized)

Respond in JSON format:
{
    "brain_scan_visible": true/false,
    "slice_views_show_data": true/false,
    "slicer_functional": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see in the screenshot"
}
"""


def verify_with_vlm(screenshot_path: str, query_vlm=None) -> dict:
    """Use VLM to verify brain scan is visible in slice views."""
    if not query_vlm:
        return {
            "success": False,
            "error": "VLM not available",
            "brain_scan_visible": None,
            "slice_views_show_data": None,
            "slicer_functional": None,
        }

    if not screenshot_path or not os.path.exists(screenshot_path):
        return {
            "success": False,
            "error": f"Screenshot not found: {screenshot_path}",
            "brain_scan_visible": None,
            "slice_views_show_data": None,
            "slicer_functional": None,
        }

    prompt = build_brain_scan_prompt()
    vlm_result = query_vlm(prompt=prompt, image=screenshot_path)

    if not vlm_result.get("success"):
        return {
            "success": False,
            "error": vlm_result.get("error", "VLM query failed"),
            "brain_scan_visible": None,
            "slice_views_show_data": None,
            "slicer_functional": None,
        }

    parsed = vlm_result.get("parsed", {})
    return {
        "success": True,
        "brain_scan_visible": parsed.get("brain_scan_visible", False),
        "slice_views_show_data": parsed.get("slice_views_show_data", False),
        "slicer_functional": parsed.get("slicer_functional", True),
        "confidence": parsed.get("confidence", "low"),
        "observations": parsed.get("observations", ""),
        "raw_response": vlm_result.get("response", "")[:500],
    }


def verify_load_sample_data(traj, env_info, task_info):
    """
    Verify that MRHead.nrrd sample data was loaded into 3D Slicer.

    HYBRID VERIFICATION:
    - Programmatic: Slicer API check for loaded volumes (40 points)
    - VLM: Visual verification of brain scan in slice views (30 points)
    - Basic: Slicer running, screenshot captured (30 points)

    Pass threshold: Requires BOTH programmatic AND visual confirmation
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    require_exact_match = metadata.get('require_exact_match', True)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/slicer_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ============================================================
    # PROGRAMMATIC CHECKS (60 points total)
    # ============================================================

    score = 0
    feedback_parts = []
    details = {}

    # Check 1: Slicer was running (10 points)
    slicer_running = result.get('slicer_was_running', False)
    details['slicer_running'] = slicer_running

    if slicer_running:
        score += 10
        feedback_parts.append("✅ Slicer running")
    else:
        feedback_parts.append("❌ Slicer NOT running")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ 3D Slicer was not running - cannot verify task completion",
            "details": details
        }

    # Check 2: Sample file exists on disk (10 points)
    sample_exists = result.get('sample_file_exists', False)
    details['sample_file_exists'] = sample_exists

    if sample_exists:
        score += 10
        feedback_parts.append("✅ Sample file available")
    else:
        feedback_parts.append("❌ Sample file MISSING")

    # Check 3: Screenshot was captured (10 points)
    screenshot_exists = result.get('screenshot_exists', False)
    details['screenshot_exists'] = screenshot_exists

    if screenshot_exists:
        score += 10
        feedback_parts.append("✅ Screenshot captured")
    else:
        feedback_parts.append("❌ No screenshot")

    # Check 4: Volume loaded via Slicer API (30 points)
    volume_loaded = result.get('volume_loaded', False)
    mrhead_loaded = result.get('mrhead_loaded', False)
    loaded_name = result.get('loaded_volume_name', '')

    details['volume_loaded'] = volume_loaded
    details['mrhead_loaded'] = mrhead_loaded
    details['loaded_volume_name'] = loaded_name

    programmatic_pass = False
    if mrhead_loaded:
        score += 30
        feedback_parts.append("✅ MRHead loaded (API verified)")
        programmatic_pass = True
    elif volume_loaded:
        if require_exact_match:
            score += 15
            feedback_parts.append(f"⚠️ Volume loaded ({loaded_name}) but not MRHead")
        else:
            score += 30
            feedback_parts.append(f"✅ Volume loaded: {loaded_name}")
            programmatic_pass = True
    else:
        feedback_parts.append("❌ NO DATA LOADED (API check)")

    # ============================================================
    # VLM VISUAL CHECKS (40 points total)
    # ============================================================

    vlm_pass = False
    vlm_result = {"success": False}
    query_vlm = env_info.get('query_vlm')

    # Copy screenshot for VLM analysis
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/slicer_final.png", temp_screenshot.name)
        vlm_result = verify_with_vlm(temp_screenshot.name, query_vlm=query_vlm)
    except Exception as e:
        logger.warning(f"Could not copy screenshot for VLM: {e}")
        vlm_result = {"success": False, "error": str(e)}
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)

    details['vlm_result'] = vlm_result

    if vlm_result.get("success"):
        # VLM Check 1: Brain scan visible (20 points)
        if vlm_result.get("brain_scan_visible"):
            score += 20
            feedback_parts.append("✅ Brain scan visible (VLM)")
            vlm_pass = True
        else:
            feedback_parts.append("❌ Brain scan NOT visible (VLM)")

        # VLM Check 2: Slice views show data (10 points)
        if vlm_result.get("slice_views_show_data"):
            score += 10
            feedback_parts.append("✅ Slice views show data (VLM)")
        else:
            feedback_parts.append("❌ Slice views empty (VLM)")

        # VLM Check 3: Slicer functional (10 points)
        if vlm_result.get("slicer_functional"):
            score += 10
            feedback_parts.append("✅ Slicer functional (VLM)")
        else:
            feedback_parts.append("⚠️ Slicer may have issues (VLM)")

        # Add VLM confidence
        confidence = vlm_result.get("confidence", "unknown")
        details['vlm_confidence'] = confidence
    else:
        # VLM failed - give partial credit based on programmatic checks only
        feedback_parts.append(f"⚠️ VLM check skipped: {vlm_result.get('error', 'unavailable')}")
        # If programmatic passed, give some VLM points
        if programmatic_pass:
            score += 20
            vlm_pass = True  # Trust programmatic if VLM unavailable

    # ============================================================
    # FINAL SCORING
    # ============================================================

    # Task passes if BOTH programmatic AND visual checks pass
    # OR if programmatic passes and VLM is unavailable/failed
    passed = programmatic_pass and vlm_pass

    # Add summary
    if passed and score >= 90:
        feedback_parts.append("🎉 Task completed successfully!")
    elif passed:
        feedback_parts.append("✅ Task completed")
    else:
        feedback_parts.append("❌ Task NOT completed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
