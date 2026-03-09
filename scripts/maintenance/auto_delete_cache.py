from glob import glob
import os
import time
import shutil

ROOT = "/home/pranjala/.cache/gym-anything/qemu/work/"
ROOT = "/compute/babel-u5-28/pranjala/qemu_cache/work/"
MAX_AGE_SECONDS = 60 * 60
SLEEP_SECONDS = 600

while True:
    cache_folders = glob(os.path.join(ROOT, "ga_qemu_*"))
    print(f'Found {len(cache_folders)} cache folders')
    for path in cache_folders:
        # print(path)
        try:
            if not os.path.isdir(path):
                continue
            if time.time() - os.path.getmtime(path) > MAX_AGE_SECONDS:
                print(f"Deleting {path} (older than {MAX_AGE_SECONDS}s)")
                shutil.rmtree(path)
        except FileNotFoundError:
            # disappeared between glob and stat/delete
            pass
        except Exception as e:
            print(f"Failed to delete {path}: {e}")
    time.sleep(SLEEP_SECONDS)