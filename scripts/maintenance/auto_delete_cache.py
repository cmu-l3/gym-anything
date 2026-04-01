from glob import glob
import os
import time
import shutil

ROOT = os.environ.get("GYM_ANYTHING_QEMU_CACHE", os.path.expanduser("~/.cache/gym-anything/qemu"))
ROOT = os.path.join(ROOT, "work") + "/"
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