import pandas as pd

file_path = "/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/oracle_analytics_desktop_env/data/sample_order_lines2023.xlsx"
df = pd.read_excel(file_path)

print("Columns:", list(df.columns))

if "Region" in df.columns:
    print("Unique Regions:", df["Region"].unique().tolist())
else:
    print("Region column not found!")

