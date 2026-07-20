#!/usr/bin/env python3
"""Affiche le layout du conteneur parent de la fenêtre focus (polybar)."""
import json
import subprocess

ICONS = {"splith": "[]=", "splitv": "[]‖", "tabbed": "[T]", "stacked": "[S]"}

def walk(node, parent_layout):
    if node.get("focused"):
        return parent_layout
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        found = walk(child, node.get("layout", parent_layout))
        if found:
            return found
    return None

try:
    tree = json.loads(subprocess.check_output(["i3-msg", "-t", "get_tree"]))
    layout = walk(tree, "splith") or "splith"
    print(ICONS.get(layout, layout))
except Exception:
    print("[]=")
