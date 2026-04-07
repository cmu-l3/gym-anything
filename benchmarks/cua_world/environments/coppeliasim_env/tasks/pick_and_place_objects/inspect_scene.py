import os
import sys
import time

sys.path.insert(0, '/tmp/CoppeliaSim_Edu_V4_10_0_rev0_Ubuntu24_04/programming/zmqRemoteApi/clients/python')

from coppeliasim_zmqremoteapi_client import RemoteAPIClient

print("Connecting...")
try:
    client = RemoteAPIClient()
    sim = client.require('sim')
except Exception as e:
    print(f"Failed to connect: {e}")
    sys.exit(1)

print("Loading scene...")
try:
    sim.loadScene('/tmp/CoppeliaSim_Edu_V4_10_0_rev0_Ubuntu24_04/scenes/pickAndPlaceDemo.ttt')
except Exception as e:
    print(f"Failed to load scene: {e}")

print("Getting joints...")
try:
    joint_handles = sim.getObjectsInTree(sim.handle_scene, sim.object_joint_type, 0)
    for h in joint_handles:
        print("Joint:", sim.getObjectAlias(h))
except Exception as e:
    pass

print("Getting all objects...")
try:
    all_objs = sim.getObjectsInTree(sim.handle_scene, sim.handle_all, 0)
    for h in all_objs:
        print("Obj:", sim.getObjectAlias(h))
except Exception as e:
    pass

print("Done!")
