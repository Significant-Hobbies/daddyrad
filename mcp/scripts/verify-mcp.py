#!/usr/bin/env python3
"""Exercise the real stdio MCP executable against disposable four-engine fixtures."""
import argparse
import json
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time
import uuid


def verify(binary):
    with tempfile.TemporaryDirectory(prefix="daddyrad-mcp-verify-") as temporary:
        root = Path(temporary).resolve()
        home = root / "home"
        storage = root / "storage"
        skill = home / ".agents/skills/manual"
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text("---\nname: manual\ndescription: Verification fixture\ndisable-model-invocation: true\n---\nPrivate body must never be returned.\n")
        (skill / "agents").mkdir()
        (skill / "agents/openai.yaml").write_text("policy:\n  allow_implicit_invocation: false\n")
        unsafe = home / ".agents/skills/linked-policy"
        unsafe.mkdir()
        (unsafe / "SKILL.md").write_text("---\nname: linked-policy\n---\n")
        (unsafe / "agents").mkdir()
        external_policy = root / "external-policy.yaml"
        external_policy.write_text("policy:\n  allow_implicit_invocation: false\n")
        (unsafe / "agents/openai.yaml").symlink_to(external_policy)
        artifact = storage / "project/node_modules/package"
        artifact.mkdir(parents=True)
        (storage / "project/package.json").write_text("{}")
        (artifact / "fixture.bin").write_bytes(b"x" * 8192)
        (storage / "escape").symlink_to(home, target_is_directory=True)
        process = subprocess.Popen([str(binary), "--storage-root", str(storage), "--context-home", str(home)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        messages = queue.Queue()
        errors = []

        def read_stdout():
            for line in process.stdout:
                try:
                    assert len(line) <= 262144, "Unbounded stdout line"
                    messages.put(json.loads(line))
                except Exception as error:
                    messages.put(error)
            messages.put(EOFError("Server stdout closed"))

        def read_stderr():
            for line in process.stderr:
                errors.append(line[:1024])
                if len(errors) > 100:
                    errors.pop(0)

        threading.Thread(target=read_stdout, daemon=True).start()
        threading.Thread(target=read_stderr, daemon=True).start()
        serial = 0
        resident_samples = []

        def request(method, params):
            nonlocal serial
            serial += 1
            process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": serial, "method": method, "params": params}) + "\n")
            process.stdin.flush()
            deadline = time.monotonic() + 40
            while time.monotonic() < deadline:
                result = messages.get(timeout=max(0.01, deadline - time.monotonic()))
                if isinstance(result, Exception):
                    raise result
                if result.get("id") == serial:
                    assert "error" not in result, result
                    resident = subprocess.run(["ps", "-o", "rss=", "-p", str(process.pid)], capture_output=True, text=True, check=True)
                    resident_samples.append(int(resident.stdout.strip()))
                    return result["result"]
            raise TimeoutError(method)

        def call(name, arguments=None, expected_error=False):
            result = request("tools/call", {"name": name, "arguments": arguments or {}})
            assert bool(result.get("isError")) == expected_error, (name, result)
            assert "structuredContent" in result
            return result["structuredContent"]

        try:
            initialized = request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "DaddyRad verification", "version": "1"}})
            assert initialized["serverInfo"]["name"] == "DaddyRad"
            process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
            process.stdin.flush()
            tools = request("tools/list", {})["tools"]
            assert len(tools) == 8 and all(tool["annotations"]["readOnlyHint"] for tool in tools)
            capabilities = call("daddy_capabilities")
            assert capabilities["readOnly"] and len(capabilities["engines"]) == 4
            snapshot = call("performance_snapshot")
            assert snapshot["processes"] and all("pid" not in row and "name" not in row for row in snapshot["processes"])
            token = snapshot["processes"][0]["processToken"]
            history = call("performance_process_history", {"process_token": token})
            assert history["evidence"] == "unavailable"
            skills = call("context_skills", {"runtime": "Codex"})
            assert skills["total"] == 1 and skills["skills"][0]["policies"][0]["mode"] == "Manual only"
            assert "Private body" not in json.dumps(skills)
            scanned = call("storage_analyze", {"path": str(storage)})
            assert any(group["category"] == "nodeModules" and group["allocatedBytes"] > 0 for group in scanned["categories"])
            call("storage_analyze", {"path": str(storage / "escape")}, expected_error=True)
            call("storage_analyze", {"path": str(home)}, expected_error=True)
            oversized = storage / "entry-budget"
            oversized.mkdir()
            for index in range(20020):
                (oversized / f"file-{index}").touch()
            exhausted = call("storage_analyze", {"path": str(oversized)}, expected_error=True)
            assert "20,000 entries" in exhausted["error"]
            rules = [{"id": str(uuid.uuid4()), "pattern": pattern, "target": {"browser": browser, "profile": ""}} for pattern, browser in [("example.com", "chrome"), ("*.example.com", "safari")]]
            route = call("browser_explain_route", {"url": "https://sub.example.com/private?token=hidden", "config": {"rules": rules}})
            assert route["matchedRuleIndex"] == 0 and route["otherMatchingRuleIndices"] == [1] and route["target"]["browser"] == "chrome"
            assert "hidden" not in json.dumps(route)
            before = call("performance_capture", {"seconds": 3})
            after = call("performance_capture", {"seconds": 3})
            assert before["sampleCount"] >= 2 and after["sampleCount"] >= 2
            comparison = call("performance_compare", {"before_id": before["captureID"], "after_id": after["captureID"]})
            assert comparison["evidence"] == "derived" and "do not establish identical workloads" in comparison["limits"]
            call("performance_compare", {"before_id": "missing", "after_id": after["captureID"]}, expected_error=True)
            call("performance_snapshot", {"limit": 999}, expected_error=True)
            process.stdin.close()
            process.wait(timeout=10)
            assert process.returncode == 0, errors
            print(json.dumps({"result": "passed", "tools": len(tools), "engines": 4, "residentMiB": {"initialized": round(resident_samples[0] / 1024, 1), "maximumSampled": round(max(resident_samples) / 1024, 1), "limits": "Point-in-time RSS samples after requests, not a continuous peak or app comparison."}, "checks": ["initialize", "tools/list", "all tools/call", "native captures", "default identity privacy", "runtime policy", "storage classification", "storage entry-budget cancellation", "scope/symlink denial including linked policy", "first-match routing", "invalid inputs", "clean EOF shutdown"]}))
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    verify(parser.parse_args().binary.resolve())
