import subprocess, re, json, sys, os

# paths to tools
SLEUTHKIT_DIR = "/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/sleuthkit/tools/fstools"
fsstat_bin = os.path.join(SLEUTHKIT_DIR, "fsstat")
fls_bin = os.path.join(SLEUTHKIT_DIR, "fls")
istat_bin = os.path.join(SLEUTHKIT_DIR, "istat")

IMAGE = "/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/autopsy_env/tasks/file_slack_space_extraction/8-jpeg-search/8-jpeg-search.dd"

try:
    fsstat = subprocess.check_output([fsstat_bin, IMAGE]).decode()
except Exception as e:
    print("fsstat failed:", e)
    sys.exit(1)

# Get the block size (TSK uses this as its unit for 'blocks' or 'sectors' in istat)
block_size_m = re.search(r'Cluster Size:\s*(\d+)', fsstat, re.IGNORECASE)
if not block_size_m:
    block_size_m = re.search(r'Block Size:\s*(\d+)', fsstat, re.IGNORECASE)
if not block_size_m:
    block_size_m = re.search(r'Sector Size:\s*(\d+)', fsstat, re.IGNORECASE)
block_size = int(block_size_m.group(1)) if block_size_m else 512

print(f"Detected block size: {block_size}")

try:
    fls = subprocess.check_output([fls_bin, '-r', IMAGE]).decode()
except Exception as e:
    print("fls failed:", e)
    sys.exit(1)

jpegs = []
for line in fls.splitlines():
    if ' * ' in line: continue # skip deleted files
    stripped = re.sub(r'^[+\s]+', '', line)
    m = re.match(r'^([\w/-]+)\s+(\d+)(?:-\S+)?:\s+(.+)', stripped)
    if m and m.group(1).endswith('r') and m.group(3).lower().endswith(('.jpg', '.jpeg')):
        name = m.group(3).split('\t')[0].strip()
        jpegs.append({'inode': m.group(2), 'name': name})

valid_jpegs = []
for j in jpegs:
    try:
        istat = subprocess.check_output([istat_bin, IMAGE, j['inode']]).decode()
        size_m = re.search(r'Size:\s*(\d+)', istat)
        size = int(size_m.group(1)) if size_m else 0

        blocks_match = re.search(r'(?:Sectors|Blocks|Cluster Runs):\n(.*?)(?:\n\n|\Z)', istat, re.DOTALL)
        if not blocks_match: continue

        blocks_str = blocks_match.group(1).replace('\n', ' ')
        blocks = []
        for token in blocks_str.split():
            if '-' in token:
                start, end = token.split('-')
                blocks.extend(range(int(start), int(end)+1))
            elif token.isdigit():
                blocks.append(int(token))

        if not blocks: continue

        slack_bytes = (len(blocks) * block_size) - size
        if 50 < slack_bytes < block_size:
            valid_jpegs.append({
                'name': j['name'],
                'inode': j['inode'],
                'size': size,
                'first_block': blocks[0],
                'last_block': blocks[-1],
                'slack_offset': size % block_size
            })
    except Exception as e:
        print("istat error on", j['inode'], e)
        pass

if not valid_jpegs:
    print("WARNING: No valid JPEGs for slack injection. Ground truth will be empty.")
    gt = {}
else:
    # Sort by size to find the smallest allocated JPEG
    valid_jpegs.sort(key=lambda x: x['size'])
    target = valid_jpegs[0]

    true_key = "KEY-TRU-8F9A2C"
    
    gt = {
        "target_file": target['name'],
        "logical_size_bytes": target['size'],
        "starting_sector": target['first_block'],
        "extracted_key": true_key
    }
    print("GT:", gt)

