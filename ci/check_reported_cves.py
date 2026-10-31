"""Gate the original report even when Trivy lacks advisories for these packages."""
import json
import re
import sys
from pathlib import Path


def version(value):
    if not re.fullmatch(r"\d+(?:\.\d+)*(?:-r\d+)?", value):
        raise ValueError(f"Unrecognized package version: {value}")
    upstream, _, revision = value.partition("-r")
    parts = tuple(map(int, upstream.split(".")))
    return parts + (0,) * (4 - len(parts)) + (int(revision or 0),)


def check(report, policy):
    packages = {}
    failures = []
    os_info = report.get("Metadata", {}).get("OS", {})
    if (os_info.get("Family") != "alpine"
            or os_info.get("Name", "").split(".")[:2] != ["3", "24"]
            or os_info.get("EOSL", False)):
        failures.append("Expected supported Alpine 3.24; re-review policy for another OS/branch")
    for result in report.get("Results", []):
        for package in result.get("Packages", []):
            packages[package["Name"]] = package["Version"]
    if not packages:
        return failures + ["Missing package inventory"]
    for rule in policy:
        installed = packages.get(rule["package"])
        if installed is None:
            continue
        if rule["status"] == "unresolved":
            failures.append(f'{rule["cve"]}: {rule["package"]} {installed}: no verified fix; release blocked')
        elif rule["status"] == "not_affected":
            if os_info.get("Family") != "alpine":
                failures.append(f'{rule["cve"]}: Alpine applicability decision requires review on another OS')
        elif version(installed) < version(rule["fixed"]):
            failures.append(f'{rule["cve"]}: {rule["package"]} {installed} < {rule["fixed"]}')
    return failures


if __name__ == "__main__":
    policy = json.loads(Path(__file__).with_name("reported-cves.json").read_text())
    failures = check(json.loads(Path(sys.argv[1]).read_text()), policy)
    print("\n".join(failures) if failures else "Original report package gate passed")
    sys.exit(bool(failures))
