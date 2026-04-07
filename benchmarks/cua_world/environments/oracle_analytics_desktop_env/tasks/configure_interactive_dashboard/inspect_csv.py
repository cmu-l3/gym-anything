import pandas as pd
file_path = "/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/oracle_analytics_desktop_env/data/order_lines.csv"
df = pd.read_csv(file_path)
print("CSV Columns:", list(df.columns))
if "Region" in df.columns:
    print("Unique Regions:", df["Region"].unique().tolist())
