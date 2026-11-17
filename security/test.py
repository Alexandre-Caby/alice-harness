#!/usr/bin/env python3
"""Network walls, probed from inside each running container (a probe container shares its network):
- only egress-network containers reach the internet
- only Open WebUI reaches Ollama
- none reaches other host services or publishes a port
- none mounts a repo file (it could be changed without root)

Usage: python3 test.py   (reads machine.env and versions.lock)"""
import os
import subprocess
import sys
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, os.path.join(ROOT, "tests"))
from owui import Report, env_file  # noqa: E402


def docker(*args):
    return subprocess.run(["docker", *args], capture_output=True, text=True).stdout.strip()


def reaches(image, container, host, port):
    probe = ("import socket, sys\ntry:\n    socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=4)\n"
             "    print('reached')\nexcept OSError:\n    print('blocked')")
    # gVisor keeps the network inside its sandbox: a probe sharing the namespace would see nothing, so ask from inside.
    if docker("container", "inspect", container, "-f", "{{.HostConfig.Runtime}}") == "runsc":
        return docker("exec", container, "python3", "-c", probe, host, str(port)) or "no probe"
    return docker("run", "--rm", f"--network=container:{container}", "--entrypoint", "python3", image,
                  "-c", probe, host, str(port)) or "no probe"


def main():
    m, lock = env_file("machine.env"), env_file("versions.lock")
    prefix, image = m["ALICE_PREFIX"], lock["PYTHON_IMAGE"]
    gateway = m["ALICE_NET_CORE_SUBNET"].split("/")[0].rsplit(".", 1)[0] + ".1"
    ollama_port = urllib.parse.urlsplit(m["ALICE_OLLAMA_URL"]).port or 11434
    egress = set(docker("network", "inspect", m["ALICE_NET_EGRESS"], "-f", "{{range .Containers}}{{.Name}} {{end}}").split())
    ours = [c for c in docker("ps", "--format", "{{.Names}}").split() if c.startswith(prefix + "-")]
    webui = f"{prefix}-openwebui"
    repo = os.path.realpath(ROOT) + os.sep
    t = Report("security")
    t.check(webui in ours, "Open WebUI is running")
    for c in ours:
        out = reaches(image, c, "1.1.1.1", 443)
        t.check(out == ("reached" if c in egress else "blocked"),
                f"{c} {'reaches' if c in egress else 'cannot reach'} the internet", out)
        out = reaches(image, c, gateway, ollama_port)
        t.check(out == ("reached" if c == webui else "blocked"), f"{c} {'reaches' if c == webui else 'cannot reach'} Ollama", out)
        t.check(reaches(image, c, gateway, 22) == "blocked", f"{c} cannot reach SSH on the machine")
        ports = docker("port", c)
        t.check(not ports, f"{c} publishes no port on the machine", ports)
        mounts = docker("container", "inspect", c, "-f", "{{range .Mounts}}{{.Source}} {{end}}").split()
        from_repo = [m for m in mounts if os.path.realpath(m).startswith(repo)]
        t.check(not from_repo, f"{c} mounts nothing from the repository", " ".join(from_repo))
    t.done()


if __name__ == "__main__":
    main()
