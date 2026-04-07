#!/bin/bash
echo "=== Setting up tsk_fragmentation_profiling task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/fragmentation_result.json /tmp/tsk_fragmentation_gt.json \
      /tmp/tsk_fragmentation_start_time 2>/dev/null || true

mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Verify disk image ─────────────────────────────────────────────────────────
IMAGE="/home/ga/evidence/jpeg_search.dd"
if [ ! -s "$IMAGE" ]; then
    echo "ERROR: Disk image not found at $IMAGE"
    exit 1
fi
echo "Disk image: $IMAGE ($(stat -c%s "$IMAGE") bytes)"

# ── Pre-compute TSK ground truth dynamically ──────────────────────────────────
echo "Pre-computing ground truth from TSK (hidden from agent)..."
python3 << 'PYEOF'
import subprocess, re, json, hashlib

IMAGE = "/home/ga/evidence/jpeg_search.dd"

# 1. Run fls to get all allocated files
try:
    fls_out = subprocess.check_output(['fls', '-r', '-F', IMAGE]).decode('utf-8', 'ignore')
except Exception as e:
    print(f"ERROR running fls: {e}")
    fls_out = ""

files = []
for line in fls_out.split('\n'):
    line = line.strip()
    if not line: continue
    # Exclude deleted files
    if ' * ' in line: continue
    # Parse 'r/r 123: filename'
    m = re.match(r'^[+\s]*[\w/-]+\s+(\d+)(?:-\S+)?:\s+(.+)', line)
    if m:
        inode = m.group(1)
        name = m.group(2).strip()
        # Clean tabs and exclude virtual metadata files
        if '\t' in name:
            name = name.split('\t')[0].strip()
        if name not in ('.', '..') and not name.startswith('$'):
            files.append({'inode': int(inode), 'name': name})

# 2. Run istat on each file to map block runs
results = []
for f in files:
    try:
        istat_out = subprocess.check_output(['istat', IMAGE, str(f['inode'])]).decode('utf-8', 'ignore')
        blocks = []
        in_sectors = False
        for line in istat_out.split('\n'):
            line = line.strip()
            if line.startswith('Sectors:') or line.startswith('Blocks:') or line.startswith('Cluster Runs:'):
                in_sectors = True
                continue
            if in_sectors:
                if not line: continue
                # Stop parsing if we hit other metadata headers
                if re.match(r'^[A-Za-z]+:', line):
                    in_sectors = False
                    continue
                
                # Handle range formats
                if '->' in line:
                    parts = line.split('->')
                    start = int(re.findall(r'\d+', parts[0])[-1])
                    end = int(re.findall(r'\d+', parts[1])[0])
                    blocks.extend(list(range(start, end+1)))
                elif ' - ' in line:
                    parts = line.split(' - ')
                    start = int(re.findall(r'\d+', parts[0])[-1])
                    end = int(re.findall(r'\d+', parts[1])[0])
                    blocks.extend(list(range(start, end+1)))
                else:
                    # Individual numbers listed
                    nums = [int(x) for x in re.findall(r'\d+', line)]
                    blocks.extend(nums)
                    
        # Group contiguous blocks into runs
        runs = 0
        run_starts = []
        if blocks:
            runs = 1
            run_starts.append(blocks[0])
            for i in range(1, len(blocks)):
                if blocks[i] != blocks[i-1] + 1:
                    runs += 1
                    run_starts.append(blocks[i])
        
        f['run_count'] = runs
        f['run_starts'] = run_starts
        results.append(f)
    except Exception as e:
        pass

# 3. Sort by run_count DESC, inode ASC
results.sort(key=lambda x: (-x['run_count'], x['inode']))

# 4. Identify the target (most fragmented) file
target = results[0] if results else None

# 5. Extract raw sector data for hash comparison
second_run_sector = target['run_starts'][1] if target and len(target['run_starts']) > 1 else -1
sector_hash = "N/A"
if second_run_sector >= 0:
    try:
        blk_out = subprocess.check_output(['blkcat', IMAGE, str(second_run_sector)])
        sector_hash = hashlib.sha256(blk_out).hexdigest()
    except Exception as e:
        pass
        
gt = {
    "files": results,
    "most_fragmented": target,
    "second_run_sector": second_run_sector,
    "sector_hash": sector_hash
}

with open('/tmp/tsk_fragmentation_gt.json', 'w') as f:
    json.dump(gt, f)

print(f"GT pre-computation finished. Mapped {len(results)} files.")
PYEOF

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/tsk_fragmentation_start_time

# Take an initial screenshot (just terminal)
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="