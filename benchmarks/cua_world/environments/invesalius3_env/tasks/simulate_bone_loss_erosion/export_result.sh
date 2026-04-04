#!/bin/bash
# Export result for simulate_bone_loss_erosion task

echo "=== Exporting simulate_bone_loss_erosion result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_end.png
OUTPUT_FILE="/home/ga/Documents/bone_loss_simulation.inv3"

# Use Python to inspect the InVesalius project file (tarball)
python3 << 'PYEOF'
import os
import tarfile
import plistlib
import json
import tempfile
import shutil
import glob

output_path = "/home/ga/Documents/bone_loss_simulation.inv3"
result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "valid_project": False,
    "mask_count": 0,
    "masks": [],
    "error": None
}

if os.path.isfile(output_path):
    result["file_exists"] = True
    result["file_size_bytes"] = os.path.getsize(output_path)
    
    # Create temp dir to extract relevant parts of the project
    tmp_dir = tempfile.mkdtemp()
    try:
        if tarfile.is_tarfile(output_path):
            with tarfile.open(output_path, "r:*") as tar:
                # We need to find mask plists and their data files
                # Structure is typically flat or one folder deep
                file_names = tar.getnames()
                
                # Extract Plist files first to find mask metadata
                plist_files = [f for f in file_names if f.endswith(".plist")]
                tar.extractall(path=tmp_dir, members=[tar.getmember(n) for n in plist_files])
                
                result["valid_project"] = True
                
                # Find mask files
                # InVesalius 3 typically names them mask_N.plist and mask_N.dat (or similar)
                mask_plists = [f for f in plist_files if "mask_" in f and f != "masks.plist"]
                
                # If plists are inside a folder in the tar, find them in tmp_dir
                extracted_plists = []
                for root, dirs, files in os.walk(tmp_dir):
                    for file in files:
                        if file.endswith(".plist") and "mask_" in file:
                            extracted_plists.append(os.path.join(root, file))
                
                result["mask_count"] = len(extracted_plists)
                
                # Now try to calculate "volume" (non-zero bytes) for each mask
                # We need to extract the corresponding data files
                # The data file is usually referenced in the plist or has same basename
                
                for plist_path in extracted_plists:
                    try:
                        with open(plist_path, 'rb') as fp:
                            pl = plistlib.load(fp)
                        
                        mask_name = pl.get('name', 'Unknown')
                        
                        # InVesalius usually stores the raw file with the same ID
                        # e.g. mask_0.plist -> mask_0.dat or .raw
                        base = os.path.splitext(os.path.basename(plist_path))[0]
                        
                        # Find corresponding data file in the tar list
                        # It might be .dat, .raw, .memmap, or .zip
                        data_candidates = [n for n in file_names if base in n and not n.endswith('.plist')]
                        
                        voxel_count = 0
                        
                        if data_candidates:
                            data_file_name = data_candidates[0] # Take first match
                            tar.extract(data_file_name, path=tmp_dir)
                            
                            # Locate the extracted file
                            full_data_path = os.path.join(tmp_dir, data_file_name)
                            
                            # Count non-zero bytes (rough volume approximation)
                            # This works because masks are usually byte-maps (0 vs 1/255)
                            # Reading in chunks to avoid memory issues
                            with open(full_data_path, 'rb') as f:
                                while chunk := f.read(8192):
                                    # Simple count of non-null bytes
                                    # For binary masks, this equals voxel count
                                    for b in chunk:
                                        if b != 0:
                                            voxel_count += 1
                                            
                        result["masks"].append({
                            "name": mask_name,
                            "id": base,
                            "voxel_count": voxel_count
                        })
                    except Exception as e:
                        result["error"] = f"Error parsing mask {plist_path}: {str(e)}"

    except Exception as e:
        result["valid_project"] = False
        result["error"] = str(e)
    finally:
        shutil.rmtree(tmp_dir)

with open("/tmp/simulate_bone_loss_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="