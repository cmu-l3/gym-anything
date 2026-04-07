import geopandas as gpd

gdf = gpd.read_file('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/qfield_env/data/world_survey.gpkg', layer='world_capitals')
print("Contains Oslo:", any(gdf['name'].str.contains('Oslo', case=False, na=False)))
print("Contains Cape Town:", any(gdf['name'].str.contains('Cape Town', case=False, na=False)))
print("Contains Cape:", any(gdf['name'].str.contains('Cape', case=False, na=False)))
