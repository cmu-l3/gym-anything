import pandas as pd
from sklearn.cluster import DBSCAN

h5_path = "/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/urban_sim_env/tasks/active_transportation_propensity/sanfran_public.h5"

try:
    jobs = pd.read_hdf(h5_path, 'jobs')
    buildings = pd.read_hdf(h5_path, 'buildings')
    parcels = pd.read_hdf(h5_path, 'parcels')
    
    # Calculate the total number of jobs located in each building
    job_counts = jobs.groupby('building_id').size().reset_index(name='total_jobs')
    
    # Filter for 'employment nodes': buildings that contain strictly 50 or more jobs
    emp_nodes = job_counts[job_counts['total_jobs'] >= 50]
    
    # Join these employment nodes to the parcels table to obtain the 'x' and 'y' coordinates
    # first, get parcel_id for each building
    emp_buildings = pd.merge(emp_nodes, buildings[['parcel_id']], left_on='building_id', right_index=True)
    
    # then get x and y
    emp_parcels = pd.merge(emp_buildings, parcels[['x', 'y']], left_on='parcel_id', right_index=True)
    
    # Drop any buildings that have missing coordinates
    emp_parcels = emp_parcels.dropna(subset=['x', 'y'])
    
    coords = emp_parcels[['x', 'y']].values
    
    # Run sklearn.cluster.DBSCAN to find spatial clusters
    dbscan = DBSCAN(eps=1500, min_samples=5)
    labels = dbscan.fit_predict(coords)
    
    emp_parcels['cluster'] = labels
    
    # Filter out spatial noise (-1)
    valid_clusters = emp_parcels[emp_parcels['cluster'] != -1]
    
    # Group by cluster and compute metrics
    metrics = valid_clusters.groupby('cluster').agg(
        building_count=('building_id', 'count'),
        total_jobs=('total_jobs', 'sum'),
        centroid_x=('x', 'mean'),
        centroid_y=('y', 'mean')
    ).reset_index()
    
    metrics = metrics.sort_values(by='total_jobs', ascending=False)
    
    print("Metrics columns:", list(metrics.columns))
    print("Number of clusters:", len(metrics))
    print("Top cluster total jobs:", metrics.iloc[0]['total_jobs'] if len(metrics)>0 else "N/A")
    print("Job count > 0:", len(job_counts))
except Exception as e:
    print("Error:", e)
