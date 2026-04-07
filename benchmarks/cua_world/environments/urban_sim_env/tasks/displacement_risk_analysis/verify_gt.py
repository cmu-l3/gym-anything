import pandas as pd
import json
import numpy as np

data_path = '/tmp/sanfran_public.h5'

buildings  = pd.read_hdf(data_path, 'buildings')
households = pd.read_hdf(data_path, 'households')
parcels    = pd.read_hdf(data_path, 'parcels')

# Compute income 25th percentile (definition of "low-income" for this task)
income_p25 = float(households['income'].quantile(0.25))

# Compute zone-level household counts
bldg_zone = buildings[['residential_units']].copy()
bldg_zone.index.name = 'building_id'
bldg_parcels = buildings.join(parcels[['zone_id']], on='parcel_id', how='left')
households_with_zone = households.join(
    bldg_parcels[['zone_id']], on='building_id', how='left'
).dropna(subset=['zone_id'])
households_with_zone['zone_id'] = households_with_zone['zone_id'].astype(int)

zone_hh = households_with_zone.groupby('zone_id').agg(
    total_households=('income', 'count'),
    low_income_households=('income', lambda x: (x < income_p25).sum())
).reset_index()

zones_with_data = int((zone_hh['total_households'] >= 10).sum())
total_zones = int(len(zone_hh))

gt = {
    'income_p25': income_p25,
    'zones_with_data': zones_with_data,
    'total_zones': total_zones,
    'total_households': int(len(households)),
    'total_buildings': int(len(buildings))
}

print(json.dumps(gt, indent=2))
