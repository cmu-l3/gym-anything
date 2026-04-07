import pandas as pd

try:
    jobs = pd.read_hdf('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/sanfran_public.h5', 'jobs')
    bld = pd.read_hdf('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/sanfran_public.h5', 'buildings')
    parcels = pd.read_hdf('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/sanfran_public.h5', 'parcels')
    
    print("Jobs rows:", len(jobs))
    print("Buildings rows:", len(bld))
    print("Parcels rows:", len(parcels))
    
    print("\nJobs head:")
    print(jobs.head())
    print("\nBuildings head:")
    print(bld.head())
    print("\nParcels head:")
    print(parcels.head())
except Exception as e:
    print("Error:", e)
