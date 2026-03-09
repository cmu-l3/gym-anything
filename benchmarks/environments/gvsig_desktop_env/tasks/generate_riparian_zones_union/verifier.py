#!/usr/bin/env python3
"""
Verifier for generate_riparian_zones_union task.

Checks:
1. river_buffers.shp exists and is a valid polygon shapefile.
2. countries_rivers_union.shp exists and is a valid polygon shapefile.
3. Union shapefile has more features than buffer or countries (proving split).
4. Attributes from both sources are preserved in Union.
"""

import json
import os
import struct
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_riparian_zones_union(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_union_features = metadata.get('min_union_features', 180)

    score = 0
    feedback_parts = []
    
    # Setup temp dir for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        # Load JSON result
        json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", json_path)
            with open(json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # --- Criterion 1: Buffer Created (20 pts) ---
        buffer_exists = result.get("buffer_exists", False)
        buffer_new = result.get("buffer_created_during_task", False)
        
        if buffer_exists:
            score += 10
            if buffer_new:
                score += 10
                feedback_parts.append("Buffer file created.")
            else:
                feedback_parts.append("Buffer file exists but old timestamp.")
            
            # Retrieve buffer file for inspection
            try:
                buffer_shp_path = os.path.join(temp_dir, "river_buffers.shp")
                buffer_shx_path = os.path.join(temp_dir, "river_buffers.shx")
                copy_from_env("/tmp/river_buffers.shp", buffer_shp_path)
                copy_from_env("/tmp/river_buffers.shx", buffer_shx_path)
                
                # Check geometry type (Polygon = 5)
                shp_type = get_shapefile_type(buffer_shp_path)
                if shp_type == 5:
                    feedback_parts.append("Buffer is Polygon.")
                else:
                    feedback_parts.append(f"Buffer has wrong geometry type: {shp_type}.")
                    score -= 5
            except Exception as e:
                logger.warning(f"Could not inspect buffer file: {e}")
        else:
            feedback_parts.append("Buffer file NOT found.")

        # --- Criterion 2: Union Created (20 pts) ---
        union_exists = result.get("union_exists", False)
        union_new = result.get("union_created_during_task", False)

        if union_exists:
            score += 10
            if union_new:
                score += 10
                feedback_parts.append("Union file created.")
            else:
                feedback_parts.append("Union file exists but old timestamp.")
        else:
            feedback_parts.append("Union file NOT found.")

        # --- Criterion 3 & 4: Union Content Validity (40 pts) ---
        if union_exists:
            try:
                union_shp_path = os.path.join(temp_dir, "countries_rivers_union.shp")
                union_shx_path = os.path.join(temp_dir, "countries_rivers_union.shx")
                union_dbf_path = os.path.join(temp_dir, "countries_rivers_union.dbf")
                
                copy_from_env("/tmp/countries_rivers_union.shp", union_shp_path)
                copy_from_env("/tmp/countries_rivers_union.shx", union_shx_path)
                copy_from_env("/tmp/countries_rivers_union.dbf", union_dbf_path)
                
                # Check Feature Count
                # Reading feature count from SHX header (bytes 24-28 is file length in 16-bit words)
                # This is a rough estimation or we can parse records. 
                # Better: count records in DBF or SHX index.
                count = count_records(union_shx_path)
                
                if count > min_union_features:
                    score += 20
                    feedback_parts.append(f"Union feature count valid ({count} features).")
                else:
                    feedback_parts.append(f"Union feature count too low ({count}). Expected > {min_union_features}.")
                
                # Check Attribute Preservation (20 pts)
                # We need to check if DBF has fields from countries (e.g. 'NAME' or 'POP_EST')
                fields = get_dbf_fields(union_dbf_path)
                # Convert bytes to string if needed
                field_names = [f[0].replace(b'\x00', b'').decode('latin1', 'ignore') if isinstance(f[0], bytes) else f[0] for f in fields]
                
                # Check for country fields
                has_country_field = any(f.startswith("NAME") or f.startswith("POP_EST") for f in field_names)
                if has_country_field:
                    score += 20
                    feedback_parts.append("Attributes preserved.")
                else:
                    feedback_parts.append("Attributes missing (Countries fields not found).")
                    
            except Exception as e:
                feedback_parts.append(f"Failed to inspect Union content: {e}")
        
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }

def get_shapefile_type(shp_path):
    """Read shape type from SHP header (byte 32)."""
    try:
        with open(shp_path, "rb") as f:
            f.seek(32)
            return struct.unpack("<i", f.read(4))[0]
    except:
        return -1

def count_records(shx_path):
    """Count records using SHX file size."""
    try:
        # SHX header is 100 bytes. Each record is 8 bytes.
        size = os.path.getsize(shx_path)
        return (size - 100) // 8
    except:
        return 0

def get_dbf_fields(dbf_path):
    """Read DBF field descriptors."""
    fields = []
    try:
        with open(dbf_path, "rb") as f:
            # Header length at byte 8 (2 bytes)
            f.seek(8)
            header_len = struct.unpack("<H", f.read(2))[0]
            
            # Field descriptors start at 32, 32 bytes each
            f.seek(32)
            while f.tell() < header_len - 1:
                data = f.read(32)
                if len(data) < 32: break
                if data[0] == 0x0D: break # Terminator
                
                name = data[:11]
                fields.append((name,))
    except:
        pass
    return fields