import subprocess, re, sys, os

SLEUTHKIT_DIR = "/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/sleuthkit/tools/fstools"
fsstat_bin = os.path.join(SLEUTHKIT_DIR, "fsstat")
fls_bin = os.path.join(SLEUTHKIT_DIR, "fls")
istat_bin = os.path.join(SLEUTHKIT_DIR, "istat")

IMAGE = "/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/autopsy_env/tasks/file_slack_space_extraction/8-jpeg-search/8-jpeg-search.dd"

print(subprocess.check_output([fsstat_bin, IMAGE]).decode()[:500])
print("FLS:")
fls = subprocess.check_output([fls_bin, '-r', IMAGE]).decode()
for line in fls.splitlines():
    if '.jpg' in line.lower() or '.jpeg' in line.lower():
        print(line)

