import pandas as pd
df = pd.read_csv('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/topocal_env/data/survey_points.csv')
print(f"Number of points: len({df.index})")
print(df.head())
