#!/usr/bin/env python3
"""
Verifier for Podcast Studio Signal Flow Task

Checks:
1. File Creation: .drawio and .png files exist and were modified.
2. Inventory: Counts distinct nodes for mics, cloudlifters, mixer, etc.
3. Topology: Verifies graph structure (Mic->Lifter->Mixer, Mixer->PC, etc.).
4. Labels: Checks for cable types (XLR, TRS, USB) on edges.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_podcast_studio_signal_flow(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Files to retrieve
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    analysis_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name

    try:
        # Get basic result
        copy_from_env("/tmp/task_result.json", result_file)
        with open(result_file, 'r') as f:
            result = json.load(f)

        # Get topology analysis
        copy_from_env("/tmp/topology_analysis.json", analysis_file)
        with open(analysis_file, 'r') as f:
            analysis = json.load(f)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(result_file): os.unlink(result_file)
        if os.path.exists(analysis_file): os.unlink(analysis_file)

    score = 0
    feedback = []

    # 1. File Creation (10 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
        feedback.append("Draw.io file created and saved.")
    else:
        feedback.append("Draw.io file missing or not saved.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
    
    if result.get("png_exists"):
        score += 5 # Bonus for PNG
        feedback.append("PNG export found.")

    # 2. Equipment Inventory (20 pts)
    # Target: 4 mics, 4 lifters, 1 mixer, 1 pc, 1 amp, 4 headphones, 1 monitor
    counts = analysis.get("node_counts", {})
    
    inv_score = 0
    if counts.get("mic", 0) >= 4: inv_score += 5
    if counts.get("cloudlifter", 0) >= 4: inv_score += 5
    if counts.get("mixer", 0) >= 1: inv_score += 5
    # Combined output gear
    if counts.get("pc", 0) >= 1 and counts.get("headphone", 0) >= 4 and counts.get("monitor", 0) >= 1:
        inv_score += 5
    
    score += inv_score
    feedback.append(f"Inventory Score: {inv_score}/20")

    # 3. Topology: Input Chains (25 pts)
    # Mic -> Cloudlifter -> Mixer
    correct_chains = analysis.get("mic_chains_correct", 0)
    if correct_chains >= 4:
        score += 25
        feedback.append("All 4 Mic input chains wired correctly.")
    elif correct_chains >= 1:
        # Partial credit
        partial = correct_chains * 5
        score += partial
        feedback.append(f"Partial input chains: {correct_chains}/4 wired correctly.")
    else:
        feedback.append("No correct Mic->Cloudlifter->Mixer chains found.")

    # 4. Topology: Output Chains (15 pts)
    # Mixer->PC, Mixer->Monitors, Mixer->Amp->Headphones
    out_chains = analysis.get("output_chains_correct", 0)
    # 3 possible output chains
    score += out_chains * 5
    feedback.append(f"Output paths: {out_chains}/3 correct.")

    # 5. Cable Labels (20 pts)
    # Look for XLR, TRS, USB keywords in labels
    labels = [l.lower() for l in analysis.get("cable_labels", [])]
    has_xlr = any("xlr" in l for l in labels)
    has_trs = any("trs" in l for l in labels)
    has_usb = any("usb" in l for l in labels)
    
    label_score = 0
    if has_xlr: label_score += 8
    if has_trs: label_score += 8
    if has_usb: label_score += 4
    
    score += label_score
    feedback.append(f"Cable Labels found: XLR={has_xlr}, TRS={has_trs}, USB={has_usb}.")

    # 6. Visual Verification (10 pts)
    # Just checking if they produced a PNG implies they cared about visual output
    if result.get("png_exists") and score > 40:
        score += 10
        feedback.append("Export completed (Visual check pass).")

    # Final tally
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }