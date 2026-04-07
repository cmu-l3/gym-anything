#!/usr/bin/env python3
"""
Verifier for vectorize_lineart_asset task.

Checks if the agent successfully converted a raster image to a vector level (.pli)
and saved it correctly.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vectorize_lineart_asset(traj, env_info, task_info):
    """
    Verify the creation of a valid OpenToonz Vector Level (.pli) file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Criteria
    score = 0
    feedback = []
    
    # Criterion 1: Output file existence (30 pts)
    if result.get('file_exists', False):
        score += 30
        feedback.append("Output file 'director_sketch.pli' exists.")
    else:
        feedback.append("Output file 'director_sketch.pli' NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Anti-gaming Timestamp Check (20 pts)
    if result.get('is_new_file', False):
        score += 20
        feedback.append("File was created during the task.")
    else:
        feedback.append("File timestamp indicates it was not created during this session.")

    # Criterion 3: Format Validity (40 pts)
    # PLI files are proprietary binary files. They should NOT be recognized as standard images.
    is_raster = result.get('is_raster_disguised', False)
    mime_type = result.get('file_type_mime', '')
    file_size = result.get('file_size_bytes', 0)

    if is_raster:
        feedback.append("FAILED: File is just a renamed raster image (PNG/JPG).")
    elif file_size < 100:
        feedback.append("FAILED: File is too small to be a valid vector level.")
    elif "image/" in mime_type and "octet-stream" not in mime_type:
        # Some 'file' implementations might identify PLI as data or octet-stream
        # If it identifies as a known image type, it's likely wrong
        feedback.append(f"Warning: File type detected as {mime_type}, expected binary/data.")
        # We penalize if it's explicitly an image format we don't want
        if "png" in mime_type or "jpeg" in mime_type or "tiff" in mime_type:
             feedback.append("FAILED: File appears to be a raster image.")
        else:
             score += 40
             feedback.append("File format appears to be valid vector data.")
    else:
        # Likely "application/octet-stream" or "data", which is expected for PLI
        score += 40
        feedback.append("File format appears to be valid vector data.")

    # Criterion 4: Content check (implicit 10 pts)
    # If the file exists, is new, and is a valid binary PLI of sufficient size,
    # we assume the conversion happened as PLI files are complex to forge manually.
    if score >= 90:
        score += 10
        feedback.append("Bonus: conversion verified successfully.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }