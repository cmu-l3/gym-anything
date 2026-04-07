import subprocess, json, re, hashlib, os

IMAGE1 = "/tmp/7-undel-ntfs_dir/7-undel-ntfs/7-ntfs-undel.dd"
IMAGE2 = "/tmp/8-jpeg-search_dir/8-jpeg-search/8-jpeg-search.dd"

def get_file_hashes(image_path, label):
    """Extract files from image using icat and compute MD5 hashes."""
    try:
        fls_result = subprocess.run(
            ["fls", "-r", image_path],
            capture_output=True, text=True, timeout=60
        )
        fls_lines = fls_result.stdout.splitlines()
    except Exception as e:
        print(f"WARNING: fls failed for {label}: {e}")
        fls_lines = []

    files = []
    for line in fls_lines:
        stripped = re.sub(r'^[+\s]+', '', line)
        is_deleted = ' * ' in stripped
        m = re.match(r'^([\w/-]+)\s+(?:\*\s+)?(\d+)(?:-\S+)?:\s+(.+)', stripped)
        if not m:
            continue
        type_field = m.group(1)
        inode = m.group(2)
        name = m.group(3).strip()
        if '	' in name:
            name = name.split('	')[0].strip()
        if type_field.endswith('d') or type_field.endswith('v'):
            continue
        if name in ('.', '..') or ':' in name or name.startswith('$'):
            continue
        files.append({"name": name, "inode": inode, "deleted": is_deleted})

    file_hashes = {}
    for file_info in files:
        try:
            icat_result = subprocess.run(
                ["icat", image_path, file_info["inode"]],
                capture_output=True, timeout=10
            )
            if icat_result.returncode == 0 and icat_result.stdout:
                md5 = hashlib.md5(icat_result.stdout).hexdigest()
                file_hashes[file_info["name"]] = {
                    "md5": md5,
                    "inode": file_info["inode"],
                    "deleted": file_info["deleted"],
                    "size": len(icat_result.stdout)
                }
        except subprocess.TimeoutExpired:
            continue
        except Exception:
            continue

    print(f"{label}: {len(file_hashes)}/{len(files)} files hashed")
    return file_hashes, len(files)

hashes1, total1 = get_file_hashes(IMAGE1, "Source1")
hashes2, total2 = get_file_hashes(IMAGE2, "Source2")

matches = []
md5_to_name1 = {v["md5"]: k for k, v in hashes1.items() if not v["deleted"]}
for name2, info2 in hashes2.items():
    if not info2["deleted"] and info2["md5"] in md5_to_name1:
        name1 = md5_to_name1[info2["md5"]]
        matches.append({
            "md5": info2["md5"],
            "source1_name": name1,
            "source2_name": name2
        })

md5s1 = set(v["md5"] for v in hashes1.values())
md5s2 = set(v["md5"] for v in hashes2.values())
shared_md5s = md5s1 & md5s2

print("TOTAL_FILES_SOURCE1:", total1)
print("TOTAL_FILES_SOURCE2:", total2)
print("SHARED_MD5S:", len(shared_md5s))
print("MATCHES:", len(matches))
print("MATCHES_LIST:", matches)
with open("multi_source_gt.json", "w") as f:
    json.dump({"matches": matches, "shared_md5_count": len(shared_md5s), "source1": total1, "source2": total2}, f)
