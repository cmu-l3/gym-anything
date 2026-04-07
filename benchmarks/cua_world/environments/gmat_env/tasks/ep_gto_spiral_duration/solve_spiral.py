import numpy as np
from scipy.integrate import solve_ivp

mu = 398600.4415  # km^3/s^2
g0 = 9.81 / 1000  # km/s^2
T = 0.25 / 1000   # thrust in kN (or kg * km/s^2)
Isp = 1500
m_dot = T / (Isp * g0)  # kg/s

m0 = 2000.0

# Initial orbital elements
a0 = 24392.5
e0 = 0.730
i0 = 27.0 * np.pi / 180
O0 = 0.0 * np.pi / 180
w0 = 180.0 * np.pi / 180
nu0 = 0.0 * np.pi / 180

# Convert Keplerian to Cartesian
def kepler_to_cartesian(a, e, i, O, w, nu, mu):
    p = a * (1 - e**2)
    r = p / (1 + e * np.cos(nu))
    
    # Position and velocity in perifocal frame
    r_pqw = np.array([r * np.cos(nu), r * np.sin(nu), 0])
    v_pqw = np.sqrt(mu / p) * np.array([-np.sin(nu), e + np.cos(nu), 0])
    
    # Rotation matrices
    R3_O = np.array([[np.cos(-O), -np.sin(-O), 0],
                     [np.sin(-O),  np.cos(-O), 0],
                     [0,           0,          1]])
    R1_i = np.array([[1, 0, 0],
                     [0, np.cos(-i), -np.sin(-i)],
                     [0, np.sin(-i),  np.cos(-i)]])
    R3_w = np.array([[np.cos(-w), -np.sin(-w), 0],
                     [np.sin(-w),  np.cos(-w), 0],
                     [0,           0,          1]])
    
    Q = R3_O @ R1_i @ R3_w
    
    r_ijk = Q @ r_pqw
    v_ijk = Q @ v_pqw
    return r_ijk, v_ijk

r0_vec, v0_vec = kepler_to_cartesian(a0, e0, i0, O0, w0, nu0, mu)
state0 = np.concatenate([r0_vec, v0_vec, [m0]])

def eom(t, state):
    r_vec = state[0:3]
    v_vec = state[3:6]
    m = state[6]
    
    r = np.linalg.norm(r_vec)
    v = np.linalg.norm(v_vec)
    
    a_grav = -mu / r**3 * r_vec
    
    # thrust in V-direction (prograde)
    a_thrust = (T / m) * (v_vec / v)
    
    dr = v_vec
    dv = a_grav + a_thrust
    dm = -m_dot
    
    return np.concatenate([dr, dv, [dm]])

def event_sma(t, state):
    r_vec = state[0:3]
    v_vec = state[3:6]
    r = np.linalg.norm(r_vec)
    v = np.linalg.norm(v_vec)
    # Energy
    E = v**2 / 2 - mu / r
    a = -mu / (2 * E)
    return a - 42164.17
event_sma.terminal = True
event_sma.direction = 1

t_span = (0, 300 * 86400)  # max 300 days
res = solve_ivp(eom, t_span, state0, method='DOP853', events=event_sma, rtol=1e-9, atol=1e-9)

if res.t_events[0].size > 0:
    t_final = res.t_events[0][0]
    state_final = res.y_events[0][0]
    r_vec_f = state_final[0:3]
    v_vec_f = state_final[3:6]
    m_f = state_final[6]
    
    r = np.linalg.norm(r_vec_f)
    v = np.linalg.norm(v_vec_f)
    E = v**2 / 2 - mu / r
    a = -mu / (2 * E)
    
    h_vec = np.cross(r_vec_f, v_vec_f)
    e_vec = np.cross(v_vec_f, h_vec) / mu - r_vec_f / r
    ecc = np.linalg.norm(e_vec)
    
    hz = h_vec[2]
    h = np.linalg.norm(h_vec)
    inc = np.arccos(hz / h) * 180 / np.pi
    
    days = t_final / 86400
    fuel_used = 2000 - m_f
    fuel_rem = 500 - fuel_used
    print(f"Elapsed days: {days:.4f}")
    print(f"Remaining fuel: {fuel_rem:.4f} kg")
    print(f"Final SMA: {a:.4f} km")
    print(f"Final ECC: {ecc:.4f}")
    print(f"Final INC: {inc:.4f} deg")
else:
    print("Target SMA not reached.")
