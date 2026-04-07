import pandas as pd
csv_file = '/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/oracle_analytics_desktop_env/data/order_lines.csv'
df = pd.read_csv(csv_file)
overall_loss = (df['Profit'] < 0).mean()
print(f"CSV Overall Loss Rate: {overall_loss}")
