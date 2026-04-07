import pandas as pd
import numpy as np
import json

h5_path = '/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/sanfran_public.h5'
try:
    hh = pd.read_hdf(h5_path, 'households')
    bld = pd.read_hdf(h5_path, 'buildings')
    pcl = pd.read_hdf(h5_path, 'parcels')

    bld_df = bld.copy()
    bld_df['building_id'] = bld_df.index
    pcl_df = pcl.copy()
    pcl_df['parcel_id'] = pcl_df.index

    # Merge buildings with parcels to get zone_id
    bld_pcl = pd.merge(bld_df, pcl_df[['zone_id']], left_on='parcel_id', right_index=True, how='left')

    # Merge households with buildings to get zone_id
    hh_df = hh.copy()
    hh_bld = pd.merge(hh_df, bld_pcl[['zone_id']], left_on='building_id', right_index=True, how='left')

    # Aggregations
    hh_bld['persons'] = hh_bld['persons'].fillna(0)
    zone_persons = hh_bld.groupby('zone_id')['persons'].sum()

    bld_pcl['non_residential_sqft'] = bld_pcl['non_residential_sqft'].fillna(0)
    zone_sqft = bld_pcl.groupby('zone_id')['non_residential_sqft'].sum()

    df = pd.DataFrame({'total_persons': zone_persons, 'total_non_res_sqft': zone_sqft}).fillna(0)

    df['residential_demand_gpd'] = df['total_persons'] * 55.0
    df['commercial_demand_gpd'] = df['total_non_res_sqft'] * 0.15
    df['total_demand_gpd'] = df['residential_demand_gpd'] + df['commercial_demand_gpd']

    df['gross_per_capita_gpd'] = np.where(df['total_persons'] > 0, df['total_demand_gpd'] / df['total_persons'], 0)

    result = {
        "citywide_total_demand_gpd": float(df['total_demand_gpd'].sum()),
        "citywide_residential_demand_gpd": float(df['residential_demand_gpd'].sum()),
        "citywide_commercial_demand_gpd": float(df['commercial_demand_gpd'].sum()),
        "zone_with_highest_demand": int(df['total_demand_gpd'].idxmax()),
        "zone_with_highest_per_capita": int(df[df['total_persons'] >= 100]['gross_per_capita_gpd'].idxmax()),
        "top15_total_demand_zones": df.nlargest(15, 'total_demand_gpd').index.astype(int).tolist(),
        "top15_per_capita_zones": df[df['total_persons'] >= 100].nlargest(15, 'gross_per_capita_gpd').index.astype(int).tolist()
    }
    print(json.dumps(result, indent=2))
except Exception as e:
    print(f"Error: {e}")
