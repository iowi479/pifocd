import sys
import os
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from network_wcd_calculator import compute_network_delays, load_config

# This document is co-authored by Google Gemini 3.1 Pro, GPT-6 Luna

if len(sys.argv) < 2:
    print("Usage: python3 plot_boxplots.py <data_directory>")
    sys.exit(1)

data_dir = sys.argv[1]
config = load_config(data_dir)

wcd_data = compute_network_delays(config)
pmp_wcd_total = wcd_data['pmp_e2e_total']
pmp_wcd_excl = wcd_data['pmp_e2e_excl_last']
rgp_wcd_total = wcd_data['rgp_e2e_total']

def load_and_parse_csv(filepath, protocol_label):
    try:
        df = pd.read_csv(filepath)
    except FileNotFoundError:
        print(f"Error: Could not find '{filepath}'")
        sys.exit(1)

    module_col = df.columns[2] if len(df.columns) > 2 else 'module'
    name_col   = df.columns[3] if len(df.columns) > 3 else 'name'
    values_col = 'vecvalue' if 'vecvalue' in df.columns else df.columns[6]

    df_filtered = df[df[name_col].astype(str).str.contains("packetLifeTime", case=False, na=False)].copy()
    if df_filtered.empty:
        df_filtered = df.copy()

    df_filtered = df_filtered[[module_col, values_col]].dropna()

    df_filtered['flow_id'] = df_filtered[module_col].apply(
        lambda x: int(str(x).split('app[')[1].split(']')[0]) if 'app[' in str(x) else 0
    )

    df_filtered[values_col] = df_filtered[values_col].astype(str).str.split()
    df_expanded = df_filtered.explode(values_col)

    df_expanded['lifetime_s'] = pd.to_numeric(df_expanded[values_col], errors='coerce')
    df_expanded = df_expanded.dropna(subset=['lifetime_s'])
    df_expanded['lifetime_us'] = df_expanded['lifetime_s'] * 1e6
    df_expanded['Protocol'] = protocol_label
    df_expanded['Stream_Label'] = df_expanded['flow_id'].apply(
        lambda fid: f"Flow {fid} (PCP {config.FLOW_MAP[fid]['pcp']})"
    )

    return df_expanded.sort_values(by='flow_id')

pmp_csv_path = os.path.join(data_dir, "pmp_lifetimes.csv")
rgp_csv_path = os.path.join(data_dir, "rgp_lifetimes.csv")

pmp_df = load_and_parse_csv(pmp_csv_path, "PMP")
rgp_df = load_and_parse_csv(rgp_csv_path, "RGP")

df_combined = pd.concat([pmp_df, rgp_df], ignore_index=True)

def get_stats_summary(df, protocol_name, wcd_excl_map, wcd_tot_map):
    stats = df.groupby('flow_id')['lifetime_us'].agg(
        Mean='mean', Min='min', Max='max', Count='count'
    ).reset_index()
    stats['WCD_Excl_Hop4'] = stats['flow_id'].map(wcd_excl_map) if wcd_excl_map else "-"
    stats['WCD_Total'] = stats['flow_id'].map(wcd_tot_map)
    stats['Stream'] = stats['flow_id'].apply(lambda fid: f"Flow {fid} (PCP {config.FLOW_MAP[fid]['pcp']})")
    stats['Protocol'] = protocol_name
    return stats[['Protocol', 'Stream', 'Min', 'Mean', 'Max', 'WCD_Excl_Hop4', 'WCD_Total', 'Count']]

print("\n" + "="*95)
print(f" PACKET LIFETIME STATISTICS & WCD BOUNDS (in µs) - Directory: {data_dir}")
print("="*95)
print(get_stats_summary(pmp_df, "PMP", pmp_wcd_excl, pmp_wcd_total).to_string(index=False, float_format=lambda x: f"{x:.2f}"))
print("-" * 95)
print(get_stats_summary(rgp_df, "RGP", None, rgp_wcd_total).to_string(index=False, float_format=lambda x: f"{x:.2f}"))
print("="*95 + "\n")

plt.figure(figsize=(14, 8))
sns.set_theme(style="whitegrid")

ax = sns.boxplot(
    data=df_combined,
    x='Stream_Label',
    y='lifetime_us',
    hue='Protocol',
    palette={'PMP': '#4C72B0', 'RGP': '#55A868'},
    showmeans=True,
    meanprops={"marker": "o", "markerfacecolor": "red", "markeredgecolor": "red", "markersize": "5"}
)

unique_flows = sorted(df_combined['flow_id'].unique())
for idx, fid in enumerate(unique_flows):
    ax.hlines(
        y=pmp_wcd_total[fid],
        xmin=idx - 0.38,
        xmax=idx - 0.02,
        colors='crimson',
        linestyles='--',
        linewidth=2.2,
        label='PMP Total WCD' if idx == 0 else ""
    )
    ax.hlines(
        y=pmp_wcd_excl[fid],
        xmin=idx - 0.38,
        xmax=idx - 0.02,
        colors='crimson',
        linestyles=':',
        linewidth=2.2,
        label='PMP WCD Excl. Hop 4' if idx == 0 else ""
    )

    ax.hlines(
        y=rgp_wcd_total[fid],
        xmin=idx + 0.02,
        xmax=idx + 0.38,
        colors='darkorange',
        linestyles='--',
        linewidth=2.2,
        label='RGP Total WCD' if idx == 0 else ""
    )

plt.title('Simulated Packet Lifetime vs. Theoretical WCD Bounds (PMP vs. RGP)', fontsize=14, fontweight='bold', pad=15)
plt.xlabel('Stream (Flow ID & Priority Class)', fontsize=12, labelpad=10)
plt.ylabel(r'Packet Lifetime ($\mu s$)', fontsize=12, labelpad=10)
plt.legend(loc='upper right', frameon=True)

plt.xticks(rotation=25, ha='right')
plt.tight_layout()

output_plot_path = os.path.join(data_dir, "pmp_vs_rgp_lifetime_boxplots.png")
plt.savefig(output_plot_path, dpi=300)
print(f"Plot successfully saved as '{output_plot_path}'.")
plt.show()
