#!/bin/bash
echo "=== Setting up MFT Record Extraction task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Reports directory exists
mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports 2>/dev/null || true

# Clean up any prior runs
rm -f /home/ga/Reports/daubert_validation.txt
rm -f /home/ga/Reports/target_mft_record.bin
rm -f /home/ga/Reports/target_file_content.bin
rm -f /tmp/mft_gt.json
rm -f /tmp/mft_result.json

IMAGE="/home/ga/evidence/ntfs_undel.dd"

if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Evidence image $IMAGE not found."
    exit 1
fi

echo "Computing Ground Truth dynamically..."

python3 << 'PYEOF'
import subprocess, re, json, hashlib, os

IMAGE = "/home/ga/evidence/ntfs_undel.dd"

# 1. List deleted files using fls
try:
    fls_out = subprocess.check_output(['fls', '-r', '-d', IMAGE], text=True, timeout=30)
except Exception as e:
    print(f"fls error: {e}")
    sys.exit(1)

deleted_files = []
for line in fls_out.splitlines():
    line = line.strip().lstrip('+ ')
    m = re.match(r'^[\w/-]+\s+\*\s+(\d+)(?:-\S+)?:\s+(.+)', line)
    if m:
        inode = int(m.group(1))
        name = m.group(2).split('\t')[0].strip()
        if name in ('.', '..') or name.startswith('$'):
            continue
        deleted_files.append((inode, name))

# 2. Find the largest deleted file
max_size = -1
target_inode = -1
target_name = ""
target_mtimes = {"si_mtime": "", "fn_mtime": ""}

for inode, name in deleted_files:
    try:
        istat_out = subprocess.check_output(['istat', '-z', 'UTC', IMAGE, str(inode)], text=True, timeout=5)
    except Exception:
        continue
        
    size_m = re.search(r'Size:\s+(\d+)', istat_out)
    if not size_m: continue
    size = int(size_m.group(1))
    
    if size > max_size or (size == max_size and inode < target_inode):
        max_size = size
        target_inode = inode
        target_name = name
        
        # Parse MTIMEs from istat output safely by sections
        si_mtime = ""
        fn_mtime = ""
        
        sections = istat_out.split("Attribute Values:")
        for i, sec in enumerate(sections):
            if i > 0:
                prev_sec = sections[i-1]
                if "$STANDARD_INFORMATION" in prev_sec:
                    m = re.search(r'Modified:\s+(.+)', sec)
                    if m: si_mtime = m.group(1).strip()
                if "$FILE_NAME" in prev_sec:
                    m = re.search(r'Modified:\s+(.+)', sec)
                    if m: fn_mtime = m.group(1).strip()
                    
        target_mtimes["si_mtime"] = si_mtime
        target_mtimes["fn_mtime"] = fn_mtime

# 3. Extract MFT record and file content, compute hashes
mft_hash = ""
mft_sig = ""
content_hash = ""

if target_inode != -1:
    try:
        # File content hash
        content_raw = subprocess.check_output(['icat', IMAGE, str(target_inode)])
        content_hash = hashlib.sha256(content_raw).hexdigest()
        
        # MFT record hash
        mft_raw = subprocess.check_output(['icat', IMAGE, '0'])
        record_offset = target_inode * 1024
        record = mft_raw[record_offset : record_offset + 1024]
        
        if len(record) == 1024:
            mft_hash = hashlib.sha256(record).hexdigest()
            mft_sig = record[:4].decode('ascii', errors='ignore')
    except Exception as e:
        print(f"Extraction error: {e}")

gt = {
    "target_inode": target_inode,
    "target_name": target_name,
    "target_size": max_size,
    "si_mtime": target_mtimes["si_mtime"],
    "fn_mtime": target_mtimes["fn_mtime"],
    "content_hash": content_hash,
    "mft_hash": mft_hash,
    "mft_sig": mft_sig
}

with open('/tmp/mft_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"GT precomputed: Inode {target_inode}, Size {max_size}, ContentHash {content_hash[:8]}, MFTHash {mft_hash[:8]}")
PYEOF

chmod 600 /tmp/mft_gt.json

echo "=== Setup complete ==="