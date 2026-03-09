#!/usr/bin/env python3
"""
Verifier for export_diagram_formats task.

Checks for:
1. Valid PDF file export (header check, size check)
2. Valid PNG file export (header check, size check, dimensions)
3. Files created AFTER task start (anti-gaming)
"""

import json
import os
import tempfile
import struct
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_diagram_formats(traj, env_info, task_info):
    """
    Verify that the agent exported the diagram to PDF and PNG.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_size_bytes', 5000)

    score = 0
    feedback_parts = []
    
    # Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # --- PDF Verification (40 points max) ---
    pdf_exists = result.get('pdf_exists', False)
    pdf_fresh = result.get('pdf_fresh', False)
    pdf_path = result.get('pdf_path', '')
    
    if pdf_exists and pdf_path:
        # Copy PDF to verify content
        temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        try:
            copy_from_env(pdf_path, temp_pdf.name)
            
            # Check 1: Existence & Freshness (15 pts)
            if pdf_fresh:
                score += 15
                feedback_parts.append("PDF created during task")
            else:
                feedback_parts.append("PDF exists but is old (pre-task)")
            
            # Check 2: Valid Header (15 pts)
            with open(temp_pdf.name, 'rb') as f:
                header = f.read(5)
            if header == b'%PDF-':
                score += 15
                feedback_parts.append("PDF header valid")
            else:
                feedback_parts.append(f"Invalid PDF header: {header}")
                
            # Check 3: Non-trivial size (10 pts)
            size = os.path.getsize(temp_pdf.name)
            if size > min_size:
                score += 10
                feedback_parts.append(f"PDF content size OK ({size} bytes)")
            else:
                feedback_parts.append(f"PDF too small ({size} bytes)")
                
        except Exception as e:
            feedback_parts.append(f"Error verifying PDF content: {e}")
        finally:
            if os.path.exists(temp_pdf.name):
                os.unlink(temp_pdf.name)
    else:
        feedback_parts.append("PDF export not found")

    # --- PNG Verification (40 points max) ---
    png_exists = result.get('png_exists', False)
    png_fresh = result.get('png_fresh', False)
    png_path = result.get('png_path', '')

    if png_exists and png_path:
        # Copy PNG to verify content
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(png_path, temp_png.name)
            
            # Check 1: Existence & Freshness (15 pts)
            if png_fresh:
                score += 15
                feedback_parts.append("PNG created during task")
            else:
                feedback_parts.append("PNG exists but is old (pre-task)")
            
            # Check 2: Valid Header (15 pts)
            with open(temp_png.name, 'rb') as f:
                header = f.read(8)
            # PNG signature: 89 50 4E 47 0D 0A 1A 0A
            if header == b'\x89PNG\r\n\x1a\n':
                score += 15
                feedback_parts.append("PNG header valid")
                
                # Check dimensions (basic parsing of IHDR chunk)
                # IHDR follows signature, length 13 bytes.
                # Structure: Length(4) ChunkType(4) Width(4) Height(4) ...
                with open(temp_png.name, 'rb') as f:
                    f.seek(16) # Skip Sig(8) + Len(4) + Type(4) to get to Width
                    w_bytes = f.read(4)
                    h_bytes = f.read(4)
                    try:
                        width = struct.unpack('>I', w_bytes)[0]
                        height = struct.unpack('>I', h_bytes)[0]
                        if width > 100 and height > 100:
                            feedback_parts.append(f"PNG dimensions OK ({width}x{height})")
                        else:
                            feedback_parts.append(f"PNG too small dimensions ({width}x{height})")
                    except:
                        feedback_parts.append("Could not parse PNG dimensions")
            else:
                feedback_parts.append(f"Invalid PNG header")
            
            # Check 3: Non-trivial size (10 pts)
            size = os.path.getsize(temp_png.name)
            if size > min_size:
                score += 10
                feedback_parts.append(f"PNG content size OK ({size} bytes)")
            else:
                feedback_parts.append(f"PNG too small ({size} bytes)")

        except Exception as e:
            feedback_parts.append(f"Error verifying PNG content: {e}")
        finally:
            if os.path.exists(temp_png.name):
                os.unlink(temp_png.name)
    else:
        feedback_parts.append("PNG export not found")

    # --- Basic process check (20 pts) ---
    # If app was running and at least one file created
    app_running = result.get('app_was_running', False)
    if app_running:
        score += 10
        feedback_parts.append("EdrawMax was running")
    
    # Bonus for timestamps matching (already checked in freshness, but ensures logic)
    if pdf_fresh and png_fresh:
        score += 10
        feedback_parts.append("Workflow completed correctly")

    # Final logic
    # Need at least 60 points and BOTH files to be "fresh" to consider a full pass
    # Or strict threshold
    
    passed = (score >= 60) and pdf_fresh and png_fresh
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }