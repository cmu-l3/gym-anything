#!/usr/bin/env python3
"""
Verifier for customer_value_segmentation task.

Scoring breakdown (100 pts total):
  20 pts - DVA workbook file exists and was created after task start
  15 pts - File is a valid ZIP archive
  15 pts - Canvas 'Revenue Mix' present
  15 pts - Canvas 'Value Scatter' present
  15 pts - Canvas 'Discount Impact' present
  10 pts - Calculated column 'Customer_LTV' present
  10 pts - Calculated column 'Order_Value_Index' present
"""

import json
import logging
import os
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\customer_value_segmentation_result.json"


def _load_dva_json_text(dva_path):
    if not zipfile.is_zipfile(dva_path):
        return None, "Not a valid ZIP archive"
    import zlib
    all_text = []
    try:
        with zipfile.ZipFile(dva_path, 'r') as zf:
            for name in zf.namelist():
                data = zf.read(name)
                if name.lower().endswith('.json'):
                    try:
                        all_text.append(data.decode('utf-8', errors='replace'))
                    except Exception:
                        pass
                elif name.lower().endswith('.arc'):
                    try:
                        decompressed = zlib.decompress(data)
                        all_text.append(decompressed.decode('utf-8', errors='replace'))
                    except Exception:
                        pass
        return '\n'.join(all_text), None
    except Exception as e:
        return None, str(e)


def verify_customer_value_segmentation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    result = {}
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, tmp_json.name)
        with open(tmp_json.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp_json.name)
        except Exception:
            pass

    dva_info = result.get('dva_file', {})
    if not isinstance(dva_info, dict):
        dva_info = {}

    score = 0
    feedback_parts = []

    # Check 1: File exists and is new (20 pts)
    if dva_info.get('exists') and dva_info.get('is_new'):
        score += 20
        feedback_parts.append("Workbook file created after task start (+20)")
    else:
        msg = "predates task start" if dva_info.get('exists') else "not found"
        feedback_parts.append(f"Workbook file {msg} (0)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    dva_remote_path = dva_info.get('path', '')
    if not dva_remote_path:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | No DVA path"}

    tmp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.dva')
    try:
        copy_from_env(dva_remote_path, tmp_dva.name)
    except Exception as e:
        feedback_parts.append(f"Could not copy DVA file: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    try:
        json_text, err = _load_dva_json_text(tmp_dva.name)
        if err or json_text is None:
            feedback_parts.append(f"Invalid DVA structure: {err}")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # Check 2: Valid ZIP (15 pts)
        score += 15
        feedback_parts.append("DVA is valid ZIP archive (+15)")

        text_lower = json_text.lower()

        # Check 3: Canvas 'Revenue Mix' (15 pts)
        if 'revenue mix' in text_lower:
            score += 15
            feedback_parts.append("Canvas 'Revenue Mix' found (+15)")
        else:
            feedback_parts.append("Canvas 'Revenue Mix' NOT found (0)")

        # Check 4: Canvas 'Value Scatter' (15 pts)
        if 'value scatter' in text_lower:
            score += 15
            feedback_parts.append("Canvas 'Value Scatter' found (+15)")
        else:
            feedback_parts.append("Canvas 'Value Scatter' NOT found (0)")

        # Check 5: Canvas 'Discount Impact' (15 pts)
        if 'discount impact' in text_lower:
            score += 15
            feedback_parts.append("Canvas 'Discount Impact' found (+15)")
        else:
            feedback_parts.append("Canvas 'Discount Impact' NOT found (0)")

        # Check 6: Calculated column 'Customer_LTV' (10 pts)
        if 'customer_ltv' in text_lower or 'customer_ltv' in json_text:
            score += 10
            feedback_parts.append("Calculated column 'Customer_LTV' found (+10)")
        else:
            feedback_parts.append("Calculated column 'Customer_LTV' NOT found (0)")

        # Check 7: Calculated column 'Order_Value_Index' (10 pts)
        if 'order_value_index' in text_lower or 'order_value_index' in json_text:
            score += 10
            feedback_parts.append("Calculated column 'Order_Value_Index' found (+10)")
        else:
            feedback_parts.append("Calculated column 'Order_Value_Index' NOT found (0)")

    finally:
        try:
            os.unlink(tmp_dva.name)
        except Exception:
            pass

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
