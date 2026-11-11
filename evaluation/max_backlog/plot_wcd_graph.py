import matplotlib.pyplot as plt
import numpy as np

# This document is co-authored by Google Gemini 3.1 Pro, GPT-6 Luna

def single_hop_q_us(n_link):
    """Calculates single-hop queueing delay in microseconds for n_link flows."""
    burst_bits = n_link * 8000.0
    utilization_mbps = n_link * (8000.0 / 10000000.0)  # 0.0008 Mbps per flow
    capacity_mbps = 100.0  # 100 Mbps

    return burst_bits / (capacity_mbps - utilization_mbps)

def total_wcd_sec(N):
    """Calculates total end-to-end WCD in seconds for N total network flows."""
    tx_delay_us = 320.0
    hop1_q_us = single_hop_q_us(N / 2.0)
    hop2_q_us = single_hop_q_us(N)
    hop3_q_us = single_hop_q_us(N)

    total_us = tx_delay_us + hop1_q_us + hop2_q_us + hop3_q_us
    return total_us / 1e6

# Generate sample points from 1 to 2,000 flows
N_values = np.array([1, 50, 100, 500, 1000, 1500, 2000])
WCD_values = [total_wcd_sec(n) for n in N_values]

# Plotting
plt.figure(figsize=(10, 6))
plt.plot(N_values, WCD_values, marker='o', linewidth=2, color='blue', label='Max End-to-End WCD Formula')

plt.title('Worst-Case Delay vs. Number of Flows', fontsize=13)
plt.xlabel('Number of Flows (N)', fontsize=11)
plt.ylabel('Max End-to-End WCD (Seconds)', fontsize=11)

# Dynamically fit the y-axis strictly to the range of y-values
plt.ylim(min(WCD_values) * 0.95, max(WCD_values) * 1.05)

plt.grid(True, which='both', linestyle='--', alpha=0.7)
plt.legend(fontsize=11)

plt.tight_layout()
plt.savefig('formula_wcd_graph.png', dpi=300)
plt.show()

