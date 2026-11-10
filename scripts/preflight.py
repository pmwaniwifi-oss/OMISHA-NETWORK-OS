#!/usr/bin/env python3
"""Read-only inventory of this machine, not of a Windows host or another VM.

Never installs packages, runs installers, starts containers, reads environment
files, or prints service credentials. JSON is written only to stdout.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess


def probe(argv, version_pattern=None):
    executable = shutil.which(argv[0])
    if not executable:
        return {"available": False, "reason": "command_not_found"}
    try:
        result = subprocess.run([executable, *argv[1:]], capture_output=True, text=True, timeout=8)
    except (OSError, subprocess.TimeoutExpired):
        return {"available": False, "reason": "probe_failed"}
    if result.returncode != 0:
        return {"available": False, "reason": "probe_failed", "exit_code": result.returncode}
    if version_pattern:
        match = re.search(version_pattern, result.stdout)
        if not match:
            return {"available": False, "reason": "unexpected_command_output"}
        return {"available": True, "version": match.group(1)}
    return {"available": True}


def inventory():
    tools = {
        "docker_cli": probe(["docker", "--version"], r"Docker version ([\w.+-]+)"),
        "docker_compose": probe(["docker", "compose", "version", "--short"], r"^v?(\d+\.\d+[^\s]*)"),
        "go": probe(["go", "version"], r"^go version go(\d+\.\d+[^\s]*)"),
        "rustc": probe(["rustc", "--version"], r"^rustc (\d+\.\d+[^\s]*)"),
        "cargo": probe(["cargo", "--version"], r"^cargo (\d+\.\d+[^\s]*)"),
        "valkey_server": probe(["valkey-server", "--version"], r"v=([\d.]+)"),
    }
    # version --format contacts the daemon, without listing credentials or env.
    engine = probe(["docker", "version", "--format", "{{.Server.Version}}"], r"^(\d+\.\d+[^\s]*)")
    processes = []
    proc = Path("/proc")
    if proc.exists():
        for entry in proc.iterdir():
            if not entry.name.isdigit():
                continue
            try:
                name = (entry / "comm").read_text().strip()
            except OSError:
                continue
            if name in {"dockerd", "containerd", "valkey-server", "redis-server"}:
                processes.append(name)
    memory = None
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemTotal:"):
                memory = int(line.split()[1]) * 1024
    except OSError:
        pass
    free = shutil.disk_usage(Path.cwd()).free
    expected = ["/var/www/nmsprime/artisan", "/etc/nmsprime/env/global.env"]
    nms = {"expected_paths_present": {p: Path(p).exists() for p in expected},
           "runtime_verified": False, "note": "Path presence alone does not verify NMS Prime."}
    return {
        "schema": 1, "scope": "current_execution_environment_only",
        "platform": platform.system(), "architecture": platform.machine(),
        "resources": {"visible_cpu_count": os.cpu_count(), "visible_memory_bytes": memory,
                      "working_filesystem_free_bytes": free,
                      "note": "Container limits and host/VM reservations may differ."},
        "tools": tools, "docker_engine": engine,
        "observed_process_names": sorted(set(processes)), "nms_prime": nms,
        "deployment_ready": False,
        "note": "Inventory only. No container, ERP, NMS or application health is certified.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-docker", action="store_true", help="Exit 1 if Engine or Compose is unavailable")
    args = parser.parse_args()
    report = inventory()
    print(json.dumps(report, indent=2))
    return int(args.require_docker and not (
        report["docker_engine"]["available"] and report["tools"]["docker_compose"]["available"]))


if __name__ == "__main__":
    raise SystemExit(main())
