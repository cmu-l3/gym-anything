import geopandas as gpd

gdf = gpd.read_file('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/qfield_env/data/world_survey.gpkg', layer='world_capitals')
for idx, row in gdf[gdf['name'].isin(['Oslo', 'Rome', 'Cape Town', 'Cairo'])].iterrows():
    print(f"{row['name']}: Lon {row.geometry.x:.4f}, Lat {row.geometry.y:.4f}")
print(gdf['name'].tolist())
