import math
import sys
import os
import importlib.util

# This document is co-authored by Google Gemini 3.1 Pro, GPT-6 Luna

def load_config(data_dir):
    """Dynamically imports config.py from the target data directory."""
    config_path = os.path.join(data_dir, "config.py")
    if not os.path.exists(config_path):
        print(f"Error: Could not find configuration file at '{config_path}'")
        sys.exit(1)

    spec = importlib.util.spec_from_file_location("data_config", config_path)
    config = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(config)

    # Check if config uses generate_flows_and_switches function or module-level variables
    if hasattr(config, "generate_flows_and_switches"):
        all_flows, flow_map, switches = config.generate_flows_and_switches()
        config.ALL_FLOWS = all_flows
        config.FLOW_MAP = flow_map
        config.SWITCHES = switches

    return config

def calculate_pmp_single_hop_wcd(flow_map, hop_flow_ids, capacity_mbps):
    hop_flows = [flow_map[fid] for fid in hop_flow_ids]
    results = {}
    C = capacity_mbps

    for target_flow in hop_flows:
        target_pcp = target_flow['pcp']
        s_ge = [f for f in hop_flows if f['pcp'] >= target_pcp]
        s_low = [f for f in hop_flows if f['pcp'] < target_pcp]

        aggregate_burst_ge_bits = sum(f['L'] * 8 for f in s_ge)
        aggregate_util_ge = sum((f['L'] * 8) / f['T_us'] for f in s_ge)

        if aggregate_util_ge >= C:
            results[target_flow['id']] = float('inf')
            continue

        s_max_us = max((f['L'] * 8 for f in s_low), default=0) / C
        numerator = aggregate_burst_ge_bits + C * s_max_us
        denominator = C - aggregate_util_ge

        results[target_flow['id']] = numerator / denominator

    return results

def calculate_rgp_single_hop_wcd(flow_map, hop_flow_ids, capacity_mbps):
    hop_flows = [flow_map[fid] for fid in hop_flow_ids]
    results = {}
    C = capacity_mbps

    for target_flow in hop_flows:
        target_pcp = target_flow['pcp']
        s_ge = [f for f in hop_flows if f['pcp'] >= target_pcp]
        s_low = [f for f in hop_flows if f['pcp'] < target_pcp]

        aggregate_burst_ge_bits = sum(f['L'] * 8 for f in s_ge)
        aggregate_util_ge = sum((f['L'] * 8) / f['T_us'] for f in s_ge)

        if aggregate_util_ge >= C:
            results[target_flow['id']] = float('inf')
            continue

        s_max_us = max((f['L'] * 8 for f in s_low), default=0) / C
        numerator = aggregate_burst_ge_bits + C * s_max_us
        denominator = C - aggregate_util_ge

        results[target_flow['id']] = numerator / denominator

    return results

def compute_network_delays(config):
    pmp_single_wcds = {sw['name']: calculate_pmp_single_hop_wcd(config.FLOW_MAP, sw['flow_ids'], sw['capacity_mbps']) for sw in config.SWITCHES}
    rgp_single_wcds = {sw['name']: calculate_rgp_single_hop_wcd(config.FLOW_MAP, sw['flow_ids'], sw['capacity_mbps']) for sw in config.SWITCHES}

    pmp_e2e_total = {f['id']: 0.0 for f in config.ALL_FLOWS}
    pmp_e2e_excl_last = {f['id']: 0.0 for f in config.ALL_FLOWS}

    rgp_e2e_total = {f['id']: 0.0 for f in config.ALL_FLOWS}
    rgp_e2e_excl_last = {f['id']: 0.0 for f in config.ALL_FLOWS}

    for flow in config.ALL_FLOWS:
        fid = flow['id']
        path = flow['path']
        t_tx = (flow['L'] * 8) / 100.0
        total_tx_delay = 4 * t_tx

        pmp_q_components = [pmp_single_wcds[sw_name][fid] for sw_name in path]
        rgp_q_components = [rgp_single_wcds[sw_name][fid] for sw_name in path]

        pmp_e2e_total[fid] = total_tx_delay + sum(pmp_q_components)
        pmp_e2e_excl_last[fid] = total_tx_delay + sum(pmp_q_components[:-1])

        rgp_e2e_total[fid] = total_tx_delay + sum(rgp_q_components)
        rgp_e2e_excl_last[fid] = total_tx_delay + sum(rgp_q_components[:-1])

    return {
        'pmp_single_wcds': pmp_single_wcds,
        'rgp_single_wcds': rgp_single_wcds,
        'pmp_e2e_total': pmp_e2e_total,
        'pmp_e2e_excl_last': pmp_e2e_excl_last,
        'rgp_e2e_total': rgp_e2e_total,
        'rgp_e2e_excl_last': rgp_e2e_excl_last
    }

def build_omnetpp_config_block(config, results, folder_name):
    """Generates the full OMNeT++ configuration block string for a specific Config section."""
    num_flows = len(config.ALL_FLOWS)
    single_pmp = results['pmp_single_wcds']
    lines = []

    # Specific Folder Config Section
    lines.append(f"[Config {folder_name}]")
    lines.append("*.switch*.eth[*].macLayer.queue.useRgpProtocol = false")
    lines.append("*.*.eth[*].bitrate = 100Mbps\n")
    
    # Source- & Sink-Apps section
    lines.append("# Source- & Sink-Apps")
    lines.append(f"*.deviceSink1.numApps = {num_flows}")

    # Count number of flows assigned to each unique source node
    source_counts = {}
    for flow in config.ALL_FLOWS:
        src = flow['source']
        source_counts[src] = source_counts.get(src, 0) + 1

    for src, count in sorted(source_counts.items(), key=lambda x: str(x[0])):
        lines.append(f"*.deviceSource[{src}].numApps = {count}")
    lines.append("")

    lines.append('*.deviceSource[*].app[*].typename = "UdpSourceApp"')
    lines.append('*.deviceSink1.app[*].typename = "UdpSinkApp"\n')

    lines.append('*.deviceSource[*].app[*].io.destAddress = "deviceSink1"\n')

    # Deterministically map flows to source app indices
    source_app_counters = {}
    flow_to_source_app = []

    for flow in config.ALL_FLOWS:
        src = flow['source']
        app_idx = source_app_counters.get(src, 0)
        source_app_counters[src] = app_idx + 1
        flow_to_source_app.append((src, app_idx))

    # Display-names matching source (formatted as "Source<node> (<app_idx>)") and sink apps per flow
    for fid, flow in enumerate(config.ALL_FLOWS):
        src, app_idx = flow_to_source_app[fid]
        lines.append(f'*.deviceSource[{src}].app[{app_idx}].display-name = "Source{src} ({app_idx})"')
        lines.append(f'*.deviceSink1.app[{fid}].display-name = "Sink{fid}"')
    lines.append("")

    # Destination and local ports matching stream mapping (1000 + fid)
    for fid, flow in enumerate(config.ALL_FLOWS):
        src, app_idx = flow_to_source_app[fid]
        port = 1000 + fid
        lines.append(f'*.deviceSource[{src}].app[{app_idx}].io.destPort = {port}')
        lines.append(f'*.deviceSink1.app[{fid}].io.localPort = {port}')
    lines.append("")

    # Packet Lengths per flow/app (uses L per flow)
    for fid, flow in enumerate(config.ALL_FLOWS):
        src, app_idx = flow_to_source_app[fid]
        pkt_len = int(flow['L'])
        lines.append(f"*.deviceSource[{src}].app[{app_idx}].source.packetLength = {pkt_len}B - 46B # {pkt_len}B overall pkt length incl. headers (8B UDP, 20B IPv4, 18B MAC)")
    lines.append("\n## Streams")

    # DisplayString text formats for Sink
    for fid, flow in enumerate(config.ALL_FLOWS):
        pcp = flow['pcp']
        lines.append(f'*.deviceSink1.app[{fid}].io.displayStringTextFormat = "{{numReceived}} Stream-({pcp})-({fid})"')
    lines.append("")

    # DisplayString text formats for Source (uses per-flow source & app_idx)
    for fid, flow in enumerate(config.ALL_FLOWS):
        pcp = flow['pcp']
        src, app_idx = flow_to_source_app[fid]
        lines.append(f'*.deviceSource[{src}].app[{app_idx}].io.displayStringTextFormat = "{{numSent}} Stream-({pcp})-({fid})"')
    lines.append("")

    # Switch stream identifier mapping (explicitly matching port = 1000 + fid)
    mappings = []
    for fid, flow in enumerate(config.ALL_FLOWS):
        pcp = flow['pcp']
        port = 1000 + fid
        mappings.append(f'{{stream: "Stream-({pcp})-({fid})", packetFilter: expr(udp.destPort == {port})}}')
    
    mapping_str = ",\n\t".join(mappings)
    lines.append(f"*.switch*.bridging.streamIdentifier.identifier.mapping = [\n\t{mapping_str}]\n\n")

    # Production intervals (uses per-flow source & app_idx)
    for fid, flow in enumerate(config.ALL_FLOWS):
        src, app_idx = flow_to_source_app[fid]
        lines.append(f"*.deviceSource[{src}].app[{app_idx}].source.productionInterval = {int(flow['T_us'])}us")
    lines.append("")

    # Start times (uses per-flow source & app_idx)
    for fid, flow in enumerate(config.ALL_FLOWS):
        src, app_idx = flow_to_source_app[fid]
        lines.append(f"*.deviceSource[{src}].app[{app_idx}].source.startTime = 0us")
    lines.append("\n")

    # Switch MAC queue configuration
    periods = [int(f['T_us']) for f in config.ALL_FLOWS]
    phases = [int(f['phi']) for f in config.ALL_FLOWS]
    
    lines.append(f"*.switch*.eth[*].macLayer.queue.flowCount = {num_flows}")
    lines.append(f"*.switch*.eth[*].macLayer.queue.periods = {periods}")
    lines.append(f"*.switch*.eth[*].macLayer.queue.phases = {phases}\n")

    # Dynamic accumulatedDelays calculation for PMP
    switch_flow_ids = {sw['name']: set(sw['flow_ids']) for sw in config.SWITCHES}
    sw1_flows = switch_flow_ids.get('Switch 1', set())
    sw2_flows = switch_flow_ids.get('Switch 2', set())

    sw1_items = ["1*80" if fid in sw1_flows else "0" for fid in range(num_flows)]
    sw2_items = ["1*80" if fid in sw2_flows else "0" for fid in range(num_flows)]

    lines.append("*.switch1.eth[2].macLayer.queue.accumulatedDelays = [" + ", ".join(sw1_items) + "]")
    lines.append("*.switch2.eth[2].macLayer.queue.accumulatedDelays = [" + ", ".join(sw2_items) + "]")

    sw3_items = []
    for fid in range(num_flows):
        sw_prev = "Switch 1" if fid in sw1_flows else "Switch 2"
        sw3_items.append(f"2*80 + {math.ceil(single_pmp[sw_prev][fid])}")
    lines.append("*.switch3.eth[2].macLayer.queue.accumulatedDelays = [" + ", ".join(sw3_items) + "]")

    sw4_items = []
    for fid in range(num_flows):
        sw_prev = "Switch 1" if fid in sw1_flows else "Switch 2"
        q1 = math.ceil(single_pmp[sw_prev][fid])
        q2 = math.ceil(single_pmp["Switch 3"][fid])
        sw4_items.append(f"3*80 + {q1} + {q2}")
    lines.append("*.switch4.eth[1].macLayer.queue.accumulatedDelays = [" + ", ".join(sw4_items) + "]")

    return "\n".join(lines)

def print_calculator_results(data_dir):
    config = load_config(data_dir)
    results = compute_network_delays(config)
    num_flows = len(config.ALL_FLOWS)

    # Extract clean folder name from path
    folder_name = os.path.basename(os.path.normpath(data_dir))

    config_block_str = build_omnetpp_config_block(config, results, folder_name)

    # Save to file in data_dir
    output_ini_path = os.path.join(data_dir, "omnetpp_generated.ini")
    with open(output_ini_path, "w") as f:
        f.write(config_block_str + "\n")

    print("\n" + "="*85)
    print(" 0. GENERATED OMNeT++ CONFIGURATION PARAMETERS")
    print("="*85)
    print(config_block_str)
    print("="*85)
    print(f"\n[+] Configuration file saved successfully to: {output_ini_path}\n")

    print("="*85)
    print(f" 1. PHASE MODIFICATION PROTOCOL (PMP) - DATA DIR: {data_dir}")
    print("="*85)
    print("End-to-End Theoretical Delay Bounds:")
    for fid in range(num_flows):
        tot = results['pmp_e2e_total'][fid]
        excl = results['pmp_e2e_excl_last'][fid]
        pcp = config.FLOW_MAP[fid]['pcp']
        print(f"  Flow {fid:2d} (PCP {pcp}): Total WCD = {tot:7.2f} µs | Excl. Hop 4 WCD = {excl:7.2f} µs")

    print("\n" + "="*85)
    print(" 2. RELEASE GUARD PROTOCOL (RGP) ")
    print("="*85)
    print("Note: RGP requires no static accumulatedDelays configuration in INI.")
    print("\nEnd-to-End Theoretical Delay Bounds:")
    for fid in range(num_flows):
        tot = results['rgp_e2e_total'][fid]
        excl = results['rgp_e2e_excl_last'][fid]
        pcp = config.FLOW_MAP[fid]['pcp']
        print(f"  Flow {fid:2d} (PCP {pcp}): Total WCD = {tot:7.2f} µs | Excl. Hop 4 WCD = {excl:7.2f} µs")
    print("="*85 + "\n")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 network_wcd_calculator.py <data_directory>")
        sys.exit(1)

    data_dir = sys.argv[1]
    print_calculator_results(data_dir)
