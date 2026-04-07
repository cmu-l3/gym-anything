import pandas as pd
excel_file = '/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/oracle_analytics_desktop_env/data/sample_order_lines2023.xlsx'
df = pd.read_excel(excel_file, sheet_name='DV Orders')
print("EXCEL COLUMNS:", df.columns.tolist())
csv_file = '/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/oracle_analytics_desktop_env/data/order_lines.csv'
df2 = pd.read_csv(csv_file)
print("CSV COLUMNS:", df2.columns.tolist())
