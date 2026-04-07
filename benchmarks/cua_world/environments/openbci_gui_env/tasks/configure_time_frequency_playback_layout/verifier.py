#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_layout(traj, env_info, task_info):
    """
    Verifies that the OpenBCI GUI is configured with a 2-panel layout 
    showing Time Series and Spectrogram (Channel 2) during playback.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # 1. Retrieve basic state data from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    app_running = result_data.get("app_running", False)
    if not app_running:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "OpenBCI GUI is not running. The session must be active to verify the layout."
        }

    # 2. VLM Verification
    # We use the final screenshot to check the layout and widget configuration.
    # We also check a few trajectory frames to confirm interaction.
    
    final_screenshot = get_final_screenshot(traj)
    trajectory_frames = sample_trajectory_frames(traj, n=3)
    
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No final screenshot available for verification."}

    prompt = """
    You are an expert verifier for the OpenBCI GUI. Examine the provided screenshot of the OpenBCI dashboard.
    
    The user was tasked to:
    1. Set up a 2-panel layout.
    2. Display the 'Time Series' widget.
    3. Display the 'Spectrogram' widget.
    4. Configure the Spectrogram widget to show 'Channel 2' (Look for "Chan 2", "CH2", "2", or similar indicator on the Spectrogram widget).
    5. Ensure data is playing back (waveforms visible, spectrogram heatmap populating).

    Please evaluate the following:
    1. **Layout**: Are there exactly 2 main content panels visible? (Ignore top/side toolbars).
    2. **Time Series**: Is the Time Series widget (scrolling waveforms) visible?
    3. **Spectrogram**: Is the Spectrogram widget (time-frequency heatmap) visible?
    4. **Channel 2**: Is the Spectrogram widget specifically set to Channel 2? (Look closely at the dropdown/label on the Spectrogram widget header).
    5. **Playback**: Does the data look live/populated (not empty black/white boxes)?
    
    Return your response in JSON format:
    {
        "layout_is_2_panel": boolean,
        "time_series_present": boolean,
        "spectrogram_present": boolean,
        "spectrogram_is_channel_2": boolean,
        "data_is_visible": boolean,
        "reasoning": "string explanation"
    }
    """

    vlm_response = query_vlm(
        prompt=prompt,
        images=[final_screenshot], # We prioritize the final state
        model="gpt-4o" # or equivalent high-capability vision model
    )

    try:
        analysis = vlm_response.get("parsed", {})
        if not analysis:
            # Fallback if parsing failed but we got text
            logger.warning("VLM JSON parsing failed, relying on raw text/defaults if possible.")
            return {"passed": False, "score": 0, "feedback": "VLM analysis failed to produce structured output."}

        layout_ok = analysis.get("layout_is_2_panel", False)
        ts_ok = analysis.get("time_series_present", False)
        spec_ok = analysis.get("spectrogram_present", False)
        chan2_ok = analysis.get("spectrogram_is_channel_2", False)
        data_ok = analysis.get("data_is_visible", False)
        reasoning = analysis.get("reasoning", "No reasoning provided.")

        score = 0
        feedback = []

        if data_ok:
            score += 20
            feedback.append("Data playback is active.")
        else:
            feedback.append("Data playback does not appear active.")

        if layout_ok:
            score += 20
            feedback.append("Layout is correctly set to 2 panels.")
        else:
            feedback.append("Layout is NOT 2 panels.")

        if ts_ok:
            score += 15
            feedback.append("Time Series widget is present.")
        else:
            feedback.append("Time Series widget missing.")

        if spec_ok:
            score += 15
            feedback.append("Spectrogram widget is present.")
        else:
            feedback.append("Spectrogram widget missing.")

        if chan2_ok:
            score += 30
            feedback.append("Spectrogram correctly configured to Channel 2.")
        else:
            feedback.append("Spectrogram NOT set to Channel 2 (or could not be determined).")

        # Pass threshold: Needs to be nearly perfect. 
        # Missing Channel 2 config is the most common failure mode for "lazy" agents.
        passed = score >= 90 

        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback) + f" (VLM Reasoning: {reasoning})"
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}