import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("gate", ROOT / "ci/check_reported_cves.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
POLICY = json.loads((ROOT / "ci/reported-cves.json").read_text())


class ReleaseGateTests(unittest.TestCase):
    def report(self, packages):
        return {"Metadata": {"OS": {"Family": "alpine", "Name": "3.24.3"}},
                "Results": [{"Packages": [{"Name": n, "Version": v} for n, v in packages.items()]}]}

    def test_unresolved_issue_blocks_even_without_scanner_findings(self):
        failures = gate.check(self.report({"busybox": "1.37.0-r31"}), POLICY)
        self.assertTrue(any("CVE-2025-60876" in f for f in failures))

    def test_old_curl_is_blocked_and_fixed_curl_passes(self):
        self.assertTrue(gate.check(self.report({"curl": "8.12.1-r0"}), POLICY))
        self.assertEqual([], gate.check(self.report({"curl": "8.23.0-r0"}), POLICY))

    def test_empty_inventory_fails_closed(self):
        self.assertTrue(gate.check(self.report({}), POLICY))

    def test_unknown_os_cannot_reuse_alpine_exemptions(self):
        report = self.report({"curl": "8.23.0-r0"})
        report["Metadata"]["OS"] = {"Family": "debian", "Name": "13"}
        self.assertTrue(gate.check(report, POLICY))


if __name__ == "__main__":
    unittest.main()
