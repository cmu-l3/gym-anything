import sys
sys.path.append('.')
from verifier import verify_generate_multiday_trip_planner
import json

def dummy_copy(src, dst):
    if src == "C:\\tmp\\task_result.json":
        raise Exception("File not found")
    with open(dst, 'w') as f:
        f.write("<gpx><rte></rte><rte></rte></gpx>")

traj = []
env_info = {'copy_from_env': dummy_copy}
task_info = {'metadata': {}}

res = verify_generate_multiday_trip_planner(traj, env_info, task_info)
print(json.dumps(res, indent=2))
