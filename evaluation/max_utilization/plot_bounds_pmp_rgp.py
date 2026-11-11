import sys
import os
import importlib.util
import matplotlib.pyplot as plt
import numpy as np

# This document is co-authored by Google Gemini 3.1 Pro, GPT-6 Luna

# =====================================================================
# DYNAMIC IMPORT OF ../network_wcd_calculator.py
# =====================================================================
PARENT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CALCULATOR_PATH = os.path.join(PARENT_DIR, "network_wcd_calculator.py")

if not os.path.exists(CALCULATOR_PATH):
    sys.path.append(PARENT_DIR)
    try:
        import network_wcd_calculator as net_calc
    except ImportError:
        raise ImportError(f"Could not locate network_wcd_calculator.py at '{CALCULATOR_PATH}' or in parent directory.")
else:
    spec = importlib.util.spec_from_file_location("network_wcd_calculator", CALCULATOR_PATH)
    net_calc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(net_calc)


class DynamicNetworkConfig:
    """
    Configuration setup for:
    - 1 Target PCP 6 Flow: 1000 Bytes, T = 10000 us
    - 10 Background PCP 7 Flows: 1000 Bytes, periods varied to sweep PCP 7 utilization
    """
    def __init__(self, util_pcp7_percent, num_pcp7_flows=10, C_mbps=100.0, L_bytes=1000, T_pcp6_us=10000.0, hops=3):
        self.C_mbps = C_mbps
        self.L_bytes = L_bytes
        self.hops = hops
        self.T_pcp6_us = T_pcp6_us

        # Target collective PCP 7 utilization in Mbps
        util_pcp7_mbps = (util_pcp7_percent / 100.0) * C_mbps
        
        if util_pcp7_mbps <= 0:
            T_pcp7_us = 1e12  # Near-infinite period for 0% utilization
        else:
            T_pcp7_us = (num_pcp7_flows * L_bytes * 8.0) / util_pcp7_mbps

        print(f"resulting in a period of {T_pcp7_us} at {util_pcp7_percent} utilization.")
        # Flow 0: Target PCP 6 Flow
        self.ALL_FLOWS = [{
            'id': 0,
            'pcp': 6,
            'L': L_bytes,
            'T_us': T_pcp6_us,
            'phi': 0,
            'source': 0,
            'path': [f"Switch {i+1}" for i in range(hops)]
        }]

        # Flows 1..10: 10 Background PCP 7 Flows
        for fid in range(1, num_pcp7_flows + 1):
            self.ALL_FLOWS.append({
                'id': fid,
                'pcp': 7,
                'L': L_bytes,
                'T_us': T_pcp7_us,
                'phi': 0,
                'source': 1,
                'path': [f"Switch {i+1}" for i in range(hops)]
            })

        self.FLOW_MAP = {f['id']: f for f in self.ALL_FLOWS}

        # Switch Topology Setup across all hops
        all_flow_ids = [f['id'] for f in self.ALL_FLOWS]
        self.SWITCHES = [
            {
                'name': f"Switch {i+1}",
                'capacity_mbps': C_mbps,
                'flow_ids': all_flow_ids
            }
            for i in range(hops)
        ]


def calculate_cyclic_traffic_delays(util_pcp7_percent, L_bytes=1000, C_mbps=100.0):
    """
    Calculates:
    1. Total End-to-End WCD
    2. Conservative Cyclic Traffic = WCD_Sw4 - Earliest_Arrival_Sw4
    3. Per Hop Cyclic Traffic = WCD(Switch 4)
    """
    config = DynamicNetworkConfig(util_pcp7_percent=util_pcp7_percent)
    results = net_calc.compute_network_delays(config)
    
    target_fid = 0
    t_tx_us = (L_bytes * 8.0) / C_mbps  # Transmission delay per link = 80 us
    
    # Queuing delays per hop
    sw1_q = results['pmp_single_wcds']['Switch 1'][target_fid]
    sw2_q = results['pmp_single_wcds']['Switch 2'][target_fid]
    sw3_q = results['pmp_single_wcds']['Switch 3'][target_fid]
    
    # 1. Total E2E WCD (WCD at Switch 4)
    e2e_total_wcd_us = results['pmp_e2e_total'][target_fid]

    # 2. Release Time at Switch 3 and Earliest Arrival at Switch 4
    release_sw3_us = (2 * t_tx_us) + sw1_q
    earliest_arrival_sw4_us = release_sw3_us + t_tx_us  # 3 * t_tx + sw1_q
    
    # Conservative Cyclic Traffic
    conservative_cyclic_us = (e2e_total_wcd_us - t_tx_us) - earliest_arrival_sw4_us
    
    # 3. Per Hop Cyclic Traffic = WCD of Switch 4 (queuing delay at Switch 4)
    per_hop_cyclic_us = sw3_q
    
    return {
        'e2e_total': e2e_total_wcd_us,
        'conservative_cyclic': conservative_cyclic_us,
        'per_hop_cyclic': per_hop_cyclic_us
    }


# =====================================================================
# CONFIGURATION, CALCULATION & PRINTING (10% TO 95%)
# =====================================================================

PCP6_PERIOD_US = 10000.0  # Period Deadline Invariant: 10,000 us (10 ms)

# Discrete evaluation steps spanning 10% to 95% utilization
util_steps = np.linspace(10.0, 95.0, 18)

x_vals = []
e2e_y_vals = []
conservative_y_vals = []
per_hop_y_vals = []

print("\n" + "="*110)
print(f"{'PCP 7 Util (%)':<15} | {'E2E WCD (µs)':<18} | {'Conservative Cyclic (µs)':<28} | {'Per Hop Cyclic (µs)':<22}")
print("="*110)

for u in util_steps:
    d = calculate_cyclic_traffic_delays(util_pcp7_percent=u)
    
    if np.isinf(d['e2e_total']):
        print(f"{u:>12.2f}% | {'INF':>18} | {'INF':>28} | {'INF':>22}")
        break
        
    x_vals.append(u)
    e2e_y_vals.append(d['e2e_total'])
    conservative_y_vals.append(d['conservative_cyclic'])
    per_hop_y_vals.append(d['per_hop_cyclic'])
    
    print(f"{u:>12.2f}% | {d['e2e_total']:>18.2f} | {d['conservative_cyclic']:>28.2f} | {d['per_hop_cyclic']:>22.2f}")

print("="*110 + "\n")

# =====================================================================
# PLOTTING (X: 10-95%, Y: 0-20ms)
# =====================================================================

plt.figure(figsize=(13, 8))

# 1. Total E2E WCD
plt.plot(x_vals, e2e_y_vals, color='#1f77b4', linewidth=2.5, marker='o', markersize=6, label='Total E2E, Cyclic Traffic (CT)')

# 2. Conservative Cyclic Traffic
plt.plot(x_vals, conservative_y_vals, color='#ff7f0e', linewidth=2.2, marker='^', markersize=6, linestyle='-', label='Per Hop Cyclic Traffic (PHCT)')

# 3. Per Hop Cyclic Traffic (Switch 4 WCD)
plt.plot(x_vals, per_hop_y_vals, color='#2ca02c', linewidth=2.0, marker='s', markersize=6, linestyle='--', label='Per Scheduler Cyclic Traffic (PSCT)')

# Annotate points that fit within the 0-20ms y-range
for x, y_e2e, y_cons, y_hop in zip(x_vals, e2e_y_vals, conservative_y_vals, per_hop_y_vals):
    # E2E WCD Annotations
    if y_e2e <= 20000:
        plt.annotate(f"{y_e2e:.0f}µs", (x, y_e2e), textcoords="offset points", xytext=(0, 8), ha='center', fontsize=7, fontweight='bold', color='#1f77b4')
    
    # Conservative Cyclic Annotations
    if y_cons <= 20000:
        plt.annotate(f"{y_cons:.0f}µs", (x, y_cons), textcoords="offset points", xytext=(0, 8), ha='center', fontsize=7, fontweight='bold', color='#d95f02')

    # Per Hop Cyclic Annotations
    if y_hop <= 20000:
        plt.annotate(f"{y_hop:.0f}µs", (x, y_hop), textcoords="offset points", xytext=(0, -12), ha='center', fontsize=7, fontweight='bold', color='#2ca02c')

# 10 ms Period Deadline Cutoff Reference Line
plt.axhline(
    y=PCP6_PERIOD_US, 
    color='red', 
    linestyle='--', 
    linewidth=2.0, 
    label=f'10 ms Deadline ({int(PCP6_PERIOD_US)} µs)'
)

# Formatting
plt.title('Cyclic Traffic Delays vs. PCP 7 Link Utilization\n(1 PCP 6 @ T=10,000µs, 10 PCP 7 Streams @ 1000B)', fontsize=12, pad=12)
plt.xlabel('Collective PCP 7 Link Utilization (%)', fontsize=11)
plt.ylabel('Delay / Time Difference (µs)', fontsize=11)

# Specified ranges: X from 10% to 95%, Y from 0 to 20,000 us (0-20ms)
plt.xlim(10, 95)
plt.ylim(0, 20000)

plt.grid(True, which='both', linestyle='--', alpha=0.5)
plt.legend(fontsize=10, loc='upper left')




plt.tight_layout()
output_plot_path = os.path.join(os.path.dirname(__file__), "pcp6_cyclic_delays_10_95_percent.png")
plt.savefig(output_plot_path, dpi=300)
print(f"Plot successfully saved as '{output_plot_path}'.")
plt.show()
