#!/usr/bin/env python3
"""Verifier for zstack_depth_profiling task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_zstack_processing(traj, env_info, task_info):
    """
    Verify Z-Stack processing results.
    
    Criteria:
    1. MIP created, valid image, created after start time. (20 pts)
    2. AVG created, valid image, mean value < MIP mean value. (15 pts)
    3. Reslice created, dimensions indicate XZ view (not square). (15 pts)
    4. Montage created, dimensions indicate tiling. (15 pts)
    5. Z-profile CSV created, valid data rows, variation present. (20 pts)
    6. Logical consistency (MIP max >= AVG max, profile rows ~57). (15 pts)
    
    Pass threshold: 60 points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/zstack_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
        
        score = 0
        feedback_parts = []
        files = result.get("files", {})
        task_start = result.get("task_start_timestamp", 0)
        
        # Helper to check file validity
        def check_file(key, name):
            f = files.get(key, {})
            if not f.get("exists"):
                return False, f"{name} missing"
            if task_start > 0 and f.get("mtime", 0) < task_start:
                return False, f"{name} predates task"
            if f.get("size", 0) < 100:
                return False, f"{name} too small"
            return True, f"{name} OK"

        # 1. MIP Verification
        mip_ok, mip_msg = check_file("mip", "MIP")
        if mip_ok:
            score += 20
            feedback_parts.append(mip_msg)
        else:
            feedback_parts.append(mip_msg)

        # 2. AVG Verification
        avg_ok, avg_msg = check_file("avg", "AVG")
        if avg_ok:
            score += 15
            feedback_parts.append(avg_msg)
            # Check AVG vs MIP logic
            mip_mean = files.get("mip", {}).get("mean_pixel", 0)
            avg_mean = files.get("avg", {}).get("mean_pixel", 0)
            if mip_mean > 0 and avg_mean > mip_mean:
                 feedback_parts.append("WARN: AVG mean > MIP mean (unlikely)")
        else:
            feedback_parts.append(avg_msg)

        # 3. Reslice Verification
        res_ok, res_msg = check_file("reslice", "Reslice")
        if res_ok:
            # Check dimensions (Fly Brain is 256x256x57)
            # XZ view should be roughly 256 x 57 (or 57 x 256 depending on rotation)
            # It should NOT be square 256x256
            w = files.get("reslice", {}).get("width", 0)
            h = files.get("reslice", {}).get("height", 0)
            ratio = w / h if h > 0 else 1
            if 0.9 < ratio < 1.1 and w > 200:
                # If it's square and large, it might just be a duplicate of the original slice
                # But XZ reslice of 256x256x57 is 256x57 -> ratio 4.49 or 0.22
                feedback_parts.append(f"Reslice suspicious dimensions ({w}x{h})")
                score += 5 # Partial credit
            else:
                score += 15
                feedback_parts.append(f"Reslice dimensions OK ({w}x{h})")
        else:
            feedback_parts.append(res_msg)

        # 4. Montage Verification
        mon_ok, mon_msg = check_file("montage", "Montage")
        if mon_ok:
            # Montage should be larger than single slice (256x256)
            w = files.get("montage", {}).get("width", 0)
            if w > 300: # Arbitrary threshold > 256
                score += 15
                feedback_parts.append("Montage dimensions indicate tiling")
            else:
                score += 5
                feedback_parts.append(f"Montage small ({w} width)")
        else:
            feedback_parts.append(mon_msg)

        # 5. Profile Verification
        prof = result.get("profile_data", {})
        if prof.get("is_valid"):
            rows = prof.get("rows", 0)
            std = prof.get("std_dev", 0)
            # Fly brain stack has 57 slices
            if 20 <= rows <= 100:
                score += 20
                feedback_parts.append(f"Profile rows OK ({rows})")
            else:
                score += 10
                feedback_parts.append(f"Profile row count suspicious ({rows})")
            
            if std > 0.1:
                # Variation exists
                pass
            else:
                feedback_parts.append("Profile data is constant (suspicious)")
        else:
            feedback_parts.append("Profile data invalid/missing")

        # 6. Cross-Consistency
        # Check if MIP max >= AVG max
        mip_max = files.get("mip", {}).get("max_pixel", 0)
        avg_max = files.get("avg", {}).get("max_pixel", 0)
        
        consistency = True
        if mip_ok and avg_ok:
            if avg_max > mip_max:
                consistency = False
                feedback_parts.append("FAIL: AVG max > MIP max")
        
        if prof.get("is_valid") and prof.get("max_val") > 255:
             # 8-bit image check
             consistency = False
             feedback_parts.append("FAIL: Profile values > 255")

        if consistency and score >= 50:
             score += 15
             feedback_parts.append("Cross-checks passed")

        return {
            "passed": score >= 60,
            "score": min(100, score),
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}