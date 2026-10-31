# Security fixes: first implementation

Implemented on 2026-10-31:

- Upgrade to digest-pinned Alpine 3.24.3 and refresh inherited OS packages on each build.
- Store runtime credentials/settings as mode-600 JSON, shared by initial and cron runs. Parse only allowlisted variables without evaluating settings as shell code. Keep legacy standalone properties parsing as data.
- Restrict file creation permissions, use unpredictable temporary files, clean up sensitive temporary files, and remove password/token/private-key fragments from debug output.
- Verify UniFi TLS by default, support a private CA through `UNIFI_CA_CERT`, add request timeouts/HTTP failure checks, and retain explicit `UNIFI_INSECURE=1` for migration.
- Exclude secrets and audit output from the Docker build context.
- Build/test/scan both architectures before publishing or deploying. Promote scanned manifests without rebuilding. Pin action commits and restrict workflow permissions.
- Keep a separate policy for all 73 project findings from the original CSV so scanner omissions cannot silently clear those CVEs. Preserve Alpine build-specific applicability decisions and their evidence links.

## Validation

Passed locally: shell syntax for application/tests and workflow run blocks; YAML parsing; security regression checks for credential metacharacters and trailing newlines, JSON validation, variable allowlisting, restrictive settings-file permissions, UniFi verification defaults/CA/insecure options, CSRF header construction and rejection of HTTP controller URLs; four Python release-gate tests. The existing published-image inventory is rejected by the new CVE policy as expected.

The UniFi checks mock curl responses; they are not a live controller or certificate-handshake test. Full Docker builds, container startup/cron/Vault integration and both architecture image scans have not run locally because Docker is unavailable. CI runs image builds, container regression checks, scans and SBOM generation.

## Remaining work

**Publication/deployment is intentionally blocked by CVE-2025-60876** while BusyBox is installed without a verified fix. The Alpine upgrade is expected to address 67 original rows and Alpine records three further curl rows as not affected; this must still be checked against actual built image inventories and the original scanner. The three BusyBox rows remain unresolved. Do not delete their release rules to obtain a green build without a documented resolution.

Rootless runtime migration, full end-to-end scheduling/Vault/PIA validation, and a verified BusyBox patch or alternative base remain outstanding. qBittorrent's 28 CSV findings require a separate image update. Configure the controller CA before deploying the TLS behavior change; private/self-signed UniFi certificates are no longer silently accepted.

Local checks:

```sh
bash tests/security.sh
python3 -m unittest discover -s tests -p 'test_*.py'
python3 ci/check_reported_cves.py scan.json
```

The shell checks require Bash, jq and common Unix utilities. Run them in a clean checkout/container without an existing `/app/runtime-settings.json` file, since the UniFi script intentionally reads that file when present.
