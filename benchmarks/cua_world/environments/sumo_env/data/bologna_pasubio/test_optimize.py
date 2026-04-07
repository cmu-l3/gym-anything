import xml.etree.ElementTree as ET
import subprocess
import os
import shutil

scenario_dir = '/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/sumo_env/data/bologna_pasubio'
tls_path = os.path.join(scenario_dir, 'pasubio_tls.add.xml')
tripinfos_path = os.path.join(scenario_dir, 'tripinfos.xml')

# Backup original
shutil.copy(tls_path, tls_path + ".bak")

os.chdir(scenario_dir)

results = []
try:
    for offset in range(0, 121, 10):
        # Modify XML
        tree = ET.parse(tls_path + ".bak")
        root = tree.getroot()
        first_tl = root.find('.//tlLogic')
        first_tl.set('offset', str(offset))
        tree.write(tls_path)
        
        if os.path.exists(tripinfos_path):
            os.remove(tripinfos_path)
            
        # Run SUMO
        subprocess.run(['sumo', '-c', 'run.sumocfg'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        # Parse output
        try:
            trip_tree = ET.parse(tripinfos_path)
            trip_root = trip_tree.getroot()
            total_waiting_time = sum(float(trip.get('waitingTime', 0)) for trip in trip_root.findall('tripinfo'))
            
            results.append((offset, total_waiting_time))
            print(f"Offset: {offset}, Total Waiting Time: {total_waiting_time}")
        except Exception as e:
            print(f"Failed parsing offset {offset}: {e}")
        
    best_offset, best_time = min(results, key=lambda x: x[1])
    print(f"Best offset: {best_offset} with waiting time {best_time}")

finally:
    # Restore
    shutil.copy(tls_path + ".bak", tls_path)
    if os.path.exists(tls_path + ".bak"):
        os.remove(tls_path + ".bak")
