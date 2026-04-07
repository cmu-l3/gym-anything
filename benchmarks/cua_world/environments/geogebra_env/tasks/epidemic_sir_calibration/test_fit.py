import numpy as np
import pandas as pd
from scipy.integrate import odeint
from scipy.optimize import minimize

# Data from setup_task.sh
data = {
    'Day': [0, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14],
    'Infected': [1, 25, 75, 227, 296, 258, 236, 192, 126, 71, 28, 11, 7]
}
df = pd.DataFrame(data)

N = 763
I0 = 1
R0 = 0
S0 = N - I0 - R0

def sir_model(y, t, beta, gamma):
    S, I, R = y
    dSdt = -beta * S * I / N
    dIdt = beta * S * I / N - gamma * I
    dRdt = gamma * I
    return [dSdt, dIdt, dRdt]

def objective(params):
    beta, gamma = params
    t = df['Day'].values
    y0 = [S0, I0, R0]
    
    # We only care about points at exactly t
    # odeint needs a sorted array of time points, which t is.
    # However, to be safe, we simulate at all integer days from 0 to 14
    t_full = np.arange(0, 15)
    
    try:
        sol = odeint(sir_model, y0, t_full, args=(beta, gamma))
    except:
        return 1e9
        
    I_sim = sol[t, 1]
    
    # Sum of squared errors
    sse = np.sum((I_sim - df['Infected'].values)**2)
    return sse

# Initial guess based on metadata
initial_guess = [1.66, 0.44]
result = minimize(objective, initial_guess, bounds=[(0, 5), (0, 2)])

print(f"Optimal Beta: {result.x[0]:.4f}")
print(f"Optimal Gamma: {result.x[1]:.4f}")
print(f"SSE: {result.fun:.4f}")

# Also check how close 1.66 and 0.44 are
print(f"SSE for Beta=1.66, Gamma=0.44: {objective([1.66, 0.44]):.4f}")
print(f"SSE for Beta=1.668, Gamma=0.445: {objective([1.668, 0.445]):.4f}")
