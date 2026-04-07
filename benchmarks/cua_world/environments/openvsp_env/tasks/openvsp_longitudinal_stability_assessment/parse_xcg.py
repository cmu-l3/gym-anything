import xml.etree.ElementTree as ET
import sys
tree = ET.parse('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/openvsp_env/data/eCRM-001_wing_tail.vsp3')
root = tree.getroot()
for ref_cg in root.findall('.//RefCG'):
    x = ref_cg.find('X')
    if x is not None:
        print(f"RefCG X: {x.attrib.get('Value')}")
for xcg in root.findall('.//Xcg'):
    print(f"Xcg: {xcg.attrib.get('Value')}")
