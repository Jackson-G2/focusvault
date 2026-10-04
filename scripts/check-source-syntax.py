#!/usr/bin/env python3
"""Dependency-free syntax/resource gate; never import helpers or call services."""
from pathlib import Path
import ast
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def check():
    counts = {"python": 0, "javascript": 0, "json": 0}
    for folder in ["ResearchAgent", "scripts"]:
        for path in sorted((ROOT / folder).rglob("*.py")):
            if "__pycache__" in path.parts:
                continue
            ast.parse(path.read_text(), filename=str(path), feature_version=(3, 9))
            counts["python"] += 1
    for path in sorted((ROOT / "BrowserExtension").rglob("*.js")):
        subprocess.run(["node", "--check", str(path)], check=True, capture_output=True, timeout=10)
        counts["javascript"] += 1
    for path in sorted((ROOT / "BrowserExtension").rglob("*.json")):
        json.loads(path.read_text())
        counts["json"] += 1
    manifest = json.loads((ROOT / "BrowserExtension/manifest.json").read_text())
    resources = [manifest["background"]["service_worker"], manifest["action"]["default_popup"]]
    for script in manifest.get("content_scripts", []):
        resources.extend(script.get("js", []))
        resources.extend(script.get("css", []))
    for resource in resources:
        if not (ROOT / "BrowserExtension" / resource).is_file():
            raise AssertionError("Missing manifest resource: " + resource)
    print("PASS: Python 3.9 syntax, all JavaScript syntax, JSON and MV3 resource references", counts)


if __name__ == "__main__":
    check()
