def generate_flows_and_switches(number_of_flows):
    all_flows = [
        {'id': 0, 'pcp': 6, 'L': 1000, 'T_us': 10000000.0, 'phi': 0, 'source': '0', 'path': ['Switch 1', 'Switch 3', 'Switch 4']},
    ]


    for i in range(1, number_of_flows // 2, 2):
        all_flows.append({'id': i, 'pcp': 7, 'L': 1000, 'T_us': 10000000.0, 'phi': 0, 'source': '1', 'path': ['Switch 1', 'Switch 3', 'Switch 4']})
        if i + 1 < number_of_flows // 2:
            all_flows.append({'id': i + 1, 'pcp': 7, 'L': 1000, 'T_us': 10000000.0, 'phi': 0, 'source': '2', 'path': ['Switch 1', 'Switch 3', 'Switch 4']})

    for i in range(number_of_flows // 2, number_of_flows, 3):
        all_flows.append({'id': i, 'pcp': 7, 'L': 1000, 'T_us': 10000000.0, 'phi': 0, 'source': '3', 'path': ['Switch 2', 'Switch 3', 'Switch 4']})
        if i + 1 < number_of_flows:
            all_flows.append({'id': i + 1, 'pcp': 7, 'L': 1000, 'T_us': 10000000.0, 'phi': 0, 'source': '4', 'path': ['Switch 2', 'Switch 3', 'Switch 4']})
        if i + 2 < number_of_flows:
            all_flows.append({'id': i + 2, 'pcp': 7, 'L': 1000, 'T_us': 10000000.0, 'phi': 0, 'source': '5', 'path': ['Switch 2', 'Switch 3', 'Switch 4']})


    flow_map = {f['id']: f for f in all_flows}

    switches = [
        {'name': 'Switch 1', 'flow_ids': [0, ], 'capacity_mbps': 100.0},
        {'name': 'Switch 2', 'flow_ids': [], 'capacity_mbps': 100.0},
        {'name': 'Switch 3', 'flow_ids': [0], 'capacity_mbps': 100.0},
        {'name': 'Switch 4', 'flow_ids': [0], 'capacity_mbps': 100.0},
    ]

    for i in range(1, number_of_flows // 2):
        switches[0]['flow_ids'].append(i)
        switches[2]['flow_ids'].append(i)
        switches[3]['flow_ids'].append(i)

    for i in range(number_of_flows // 2, number_of_flows):
        switches[1]['flow_ids'].append(i)
        switches[2]['flow_ids'].append(i)
        switches[3]['flow_ids'].append(i)


    return all_flows, flow_map, switches

ALL_FLOWS, FLOW_MAP, SWITCHES = generate_flows_and_switches(number_of_flows=10)

