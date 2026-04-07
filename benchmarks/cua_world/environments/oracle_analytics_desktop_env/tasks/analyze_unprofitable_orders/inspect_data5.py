import pandas as pd
excel_file = '/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/oracle_analytics_desktop_env/data/sample_order_lines2023.xlsx'
df = pd.read_excel(excel_file, sheet_name='DV Orders')
overall_loss = (df['Profit'] < 0).mean()
print(f"Overall Loss Rate: {overall_loss}")
city_loss = df.groupby('City').apply(lambda x: (x['Profit'] < 0).mean())
print(f"Min City Loss Rate: {city_loss.min()}")
print(f"Max City Loss Rate: {city_loss.max()}")
print(f"Mean City Loss Rate: {city_loss.mean()}")
