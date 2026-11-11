ALL_FLOWS = [
    {'id': 0, 'pcp': 7, 'L': 1000, 'T_us': 1100.0, 'path': ['Switch 1', 'Switch 3', 'Switch 4']},
    {'id': 1, 'pcp': 6, 'L': 1000, 'T_us': 2000.0, 'path': ['Switch 1', 'Switch 3', 'Switch 4']},
    {'id': 2, 'pcp': 5, 'L': 1000, 'T_us': 2000.0, 'path': ['Switch 1', 'Switch 3', 'Switch 4']},
    {'id': 3, 'pcp': 4, 'L': 1000, 'T_us': 1800.0, 'path': ['Switch 2', 'Switch 3', 'Switch 4']},
    {'id': 4, 'pcp': 3, 'L': 1000, 'T_us': 2500.0, 'path': ['Switch 2', 'Switch 3', 'Switch 4']},
    {'id': 5, 'pcp': 2, 'L': 1000, 'T_us': 2500.0, 'path': ['Switch 2', 'Switch 3', 'Switch 4']},
]

FLOW_MAP = {f['id']: f for f in ALL_FLOWS}

SWITCHES = [
    {'name': 'Switch 1', 'flow_ids': [0, 1, 2], 'capacity_mbps': 100.0},
    {'name': 'Switch 2', 'flow_ids': [3, 4, 5], 'capacity_mbps': 100.0},
    {'name': 'Switch 3', 'flow_ids': [0, 1, 2, 3, 4, 5], 'capacity_mbps': 100.0},
    {'name': 'Switch 4', 'flow_ids': [0, 1, 2, 3, 4, 5], 'capacity_mbps': 100.0},
]
