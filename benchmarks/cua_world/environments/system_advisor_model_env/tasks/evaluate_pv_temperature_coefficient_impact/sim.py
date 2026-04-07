import PySAM.Pvwattsv8 as Pvwatts

def run_sim(module_type):
    sys = Pvwatts.new()
    
    # Configure parameters
    sys.SolarResource.solar_resource_file = "/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/phoenix_az_tmy.csv"
    sys.SystemDesign.system_capacity = 50000
    sys.SystemDesign.array_type = 2
    sys.SystemDesign.dc_ac_ratio = 1.25
    sys.SystemDesign.inv_eff = 96.0
    sys.SystemDesign.losses = 14.08
    sys.SystemDesign.gcr = 0.35
    sys.SystemDesign.tilt = 0
    sys.SystemDesign.azimuth = 180
    sys.SystemDesign.module_type = module_type
    
    sys.execute()
    
    annual = sys.Outputs.annual_energy
    monthly = sys.Outputs.monthly_energy
    
    return annual, monthly

annual_1, monthly_1 = run_sim(1)
annual_2, monthly_2 = run_sim(2)

print(f"Premium Annual: {annual_1}")
print(f"Premium Monthly: {monthly_1}")
print(f"Thin Film Annual: {annual_2}")
print(f"Thin Film Monthly: {monthly_2}")

def calc_season(monthly, indices):
    return sum(monthly[i] for i in indices)

prem_sum = calc_season(monthly_1, [5, 6, 7])
thin_sum = calc_season(monthly_2, [5, 6, 7])
prem_win = calc_season(monthly_1, [11, 0, 1])
thin_win = calc_season(monthly_2, [11, 0, 1])

sum_gain = ((thin_sum - prem_sum) / prem_sum) * 100
win_gain = ((thin_win - prem_win) / prem_win) * 100

print(f"Premium Summer: {prem_sum}")
print(f"Thin Film Summer: {thin_sum}")
print(f"Premium Winter: {prem_win}")
print(f"Thin Film Winter: {thin_win}")
print(f"Summer Gain %: {sum_gain}")
print(f"Winter Gain %: {win_gain}")
