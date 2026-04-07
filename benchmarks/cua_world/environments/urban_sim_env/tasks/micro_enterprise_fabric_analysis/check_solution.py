import pandas as pd
import numpy as np

# Load data
jobs = pd.read_hdf('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/sanfran_public.h5', 'jobs')
bld = pd.read_hdf('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/sanfran_public.h5', 'parcels')

# 3. Calculate total jobs per building
jobs_per_bldg = jobs.groupby('building_id').size().reset_index(name='job_count')

# 4. Filter buildings to ONLY include those with >= 1 job
bld_jobs = bld.merge(jobs_per_bldg, on='building_id', how='inner')
bld_jobs = bld_jobs[bld_jobs['job_count'] >= 1].copy()

# 5. Categorize business buildings by job count
def categorize_size(jobs):
    if jobs <= 10: return 'Micro/Small'
    elif jobs <= 50: return 'Medium'
    else: return 'Large'
bld_jobs['size_tier'] = bld_jobs['job_count'].apply(categorize_size)

# 6. Join to parcels to assign 'zone_id'
bld_jobs = bld_jobs.merge(parcels[['zone_id']], left_on='parcel_id', right_index=True, how='left')

# 7. Group by 'zone_id' and calculate metrics
def calc_metrics(group):
    total_business_bldgs = len(group)
    micro_small_bldgs = len(group[group['size_tier'] == 'Micro/Small'])
    medium_bldgs = len(group[group['size_tier'] == 'Medium'])
    large_bldgs = len(group[group['size_tier'] == 'Large'])
    micro_small_bldg_pct = (micro_small_bldgs / total_business_bldgs * 100) if total_business_bldgs > 0 else 0
    
    total_jobs = group['job_count'].sum()
    micro_small_jobs = group[group['size_tier'] == 'Micro/Small']['job_count'].sum()
    micro_small_job_pct = (micro_small_jobs / total_jobs * 100) if total_jobs > 0 else 0
    
    return pd.Series({
        'total_business_bldgs': total_business_bldgs,
        'micro_small_bldgs': micro_small_bldgs,
        'medium_bldgs': medium_bldgs,
        'large_bldgs': large_bldgs,
        'micro_small_bldg_pct': micro_small_bldg_pct,
        'total_jobs': total_jobs,
        'micro_small_jobs': micro_small_jobs,
        'micro_small_job_pct': micro_small_job_pct
    })

zone_metrics = bld_jobs.groupby('zone_id').apply(calc_metrics).reset_index()

# 8. Filter to ONLY include zones with at least 20 total_business_bldgs
zone_metrics = zone_metrics[zone_metrics['total_business_bldgs'] >= 20]

# 9. Sort descending by micro_small_bldg_pct and select Top 15
top_15 = zone_metrics.sort_values(by='micro_small_bldg_pct', ascending=False).head(15)
print("Top 15 DataFrame shape:", top_15.shape)
print("Top 1 zone_id:", top_15.iloc[0]['zone_id'])
