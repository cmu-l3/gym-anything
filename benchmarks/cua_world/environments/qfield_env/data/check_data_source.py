import sqlite3
import pandas as pd

# Let's check the rest of the records
conn = sqlite3.connect('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/qfield_env/data/world_survey.gpkg')
df = pd.read_sql_query("SELECT * FROM field_observations", conn)
print(df.to_dict('records'))
