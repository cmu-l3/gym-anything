import pandas as pd
import numpy as np

try:
    print("Downloading sanfran_public.h5...")
    import urllib.request
    urllib.request.urlretrieve("https://github.com/UDST/sanfran_urbansim/raw/master/data/sanfran_public.h5", "/tmp/sanfran_public.h5")
    
    print("Loading data...")
    parcels = pd.read_hdf('/tmp/sanfran_public.h5', 'parcels')
    bld = pd.read_hdf('/tmp/sanfran_public.h5', 'buildings')
    
    # - For each parcel, calculate total residential_units and total non_residential_sqft across all its buildings (treat NaNs as 0).
    bld['residential_units'] = bld['residential_units'].fillna(0)
    bld['non_residential_sqft'] = bld['non_residential_sqft'].fillna(0)
    
    bld_agg = bld.groupby('parcel_id')[['residential_units', 'non_residential_sqft']].sum()
    
    # - Join these building-level aggregations to the parcels table.
    parcels = parcels.join(bld_agg, how='left')
    parcels['residential_units'] = parcels['residential_units'].fillna(0)
    parcels['non_residential_sqft'] = parcels['non_residential_sqft'].fillna(0)
    
    # - Determine ADU eligibility. A parcel is eligible if it meets ALL three criteria:
    # 1. Exactly 1 residential unit total
    # 2. Zero non-residential space
    # 3. Parcel size is at least 3,000 square feet.
    
    # Inspect parcels to find lot area column. Let's print columns:
    print("Parcel columns:", list(parcels.columns))
    
    # Let's assume the column is 'parcel_sqft' or 'shape_area'
    area_col = 'parcel_sqft' if 'parcel_sqft' in parcels.columns else ('shape_area' if 'shape_area' in parcels.columns else None)
    
    if area_col is None:
        raise ValueError("Could not find parcel area column")
        
    print(f"Using '{area_col}' for area.")
    
    is_eligible = (
        (parcels['residential_units'] == 1) & 
        (parcels['non_residential_sqft'] == 0) & 
        (parcels[area_col] >= 3000)
    )
    
    parcels['is_eligible'] = is_eligible.astype(int)
    
    # - Group the parcels by zone_id
    zone_agg = parcels.groupby('zone_id').agg(
        total_parcels=('is_eligible', 'count'),
        eligible_parcels=('is_eligible', 'sum')
    ).reset_index()
    
    zone_agg['pct_eligible'] = (zone_agg['eligible_parcels'] / zone_agg['total_parcels']) * 100
    
    total_eligible_citywide = int(zone_agg['eligible_parcels'].sum())
    zone_with_most_capacity = int(zone_agg.loc[zone_agg['eligible_parcels'].idxmax(), 'zone_id'])
    max_capacity_in_a_zone = int(zone_agg['eligible_parcels'].max())
    
    # average_pct_eligible_across_zones (float - unweighted mean across zones having >=1 parcel)
    valid_zones = zone_agg[zone_agg['total_parcels'] >= 1]
    average_pct_eligible_across_zones = float(valid_zones['pct_eligible'].mean())
    
    print(f"total_eligible_citywide: {total_eligible_citywide}")
    print(f"zone_with_most_capacity: {zone_with_most_capacity}")
    print(f"max_capacity_in_a_zone: {max_capacity_in_a_zone}")
    print(f"average_pct_eligible_across_zones: {average_pct_eligible_across_zones}")
    
except Exception as e:
    print(f"Error: {e}")
