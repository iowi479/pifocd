import sys
import os
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from network_wcd_calculator import load_config

# This document is co-authored by Google Gemini 3.1 Pro, GPT-6 Luna

if len(sys.argv) < 2:
    print("Usage: python3 plot_jitter.py <data_directory>")
    sys.exit(1)

data_dir = sys.argv[1]
config = load_config(data_dir)

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

df_combined['packet_jitter_us'] = (
    df_combined.groupby(['Protocol', 'flow_id'])['lifetime_us']
    .diff()
    .abs()
)

jitter_stats = df_combined.groupby(['Protocol', 'flow_id'])['packet_jitter_us'].agg(
    Mean_P2P_Jitter='mean',
    Min_P2P_Jitter='min',
    Max_P2P_Jitter='max',
    Count='count'
).reset_index()

jitter_stats['Stream'] = jitter_stats['flow_id'].apply(
    lambda fid: f"Flow {fid} (PCP {config.FLOW_MAP[fid]['pcp']})"
)

print("\n" + "="*95)
print(f" PACKET-TO-PACKET JITTER SUMMARY (in µs) - Directory: {data_dir}")
print("="*95)
print(
    jitter_stats[['Protocol', 'Stream', 'Min_P2P_Jitter', 'Mean_P2P_Jitter', 'Max_P2P_Jitter', 'Count']]
    .to_string(index=False, float_format=lambda x: f"{x:.2f}")
)
print("="*95 + "\n")

plt.figure(figsize=(14, 8))
sns.set_theme(style="whitegrid")

ax = sns.boxplot(
    data=df_combined.dropna(subset=['packet_jitter_us']),
    x='Stream_Label',
    y='packet_jitter_us',
    hue='Protocol',
    palette={'PMP': '#4C72B0', 'RGP': '#55A868'},
    showmeans=True,
    meanprops={"marker": "o", "markerfacecolor": "red", "markeredgecolor": "red", "markersize": "5"}
)

plt.title('End-to-End Packet Jitter Comparison per Stream (PMP vs. RGP)', fontsize=14, fontweight='bold', pad=15)
plt.xlabel('Stream (Flow ID & Priority Class)', fontsize=12, labelpad=10)
plt.ylabel(r'Packet-to-Packet Delay Jitter ($\mu s$)', fontsize=12, labelpad=10)
plt.legend(loc='upper right', frameon=True)

plt.xticks(rotation=25, ha='right')
plt.tight_layout()

output_plot_path = os.path.join(data_dir, "pmp_vs_rgp_jitter_boxplots.png")
plt.savefig(output_plot_path, dpi=300)
print(f"Plot successfully saved as '{output_plot_path}'.")
plt.show()
