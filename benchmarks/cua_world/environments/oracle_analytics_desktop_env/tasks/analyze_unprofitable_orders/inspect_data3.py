import pandas as pd
excel_file = '/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/oracle_analytics_desktop_env/data/sample_order_lines2023.xlsx'
df = pd.read_excel(excel_file, sheet_name='DV Orders')
print("Columns:", df.columns.tolist())
print("Shape:", df.shape)
if 'Region' in df.columns:
    print(df['Region'].value_counts())
