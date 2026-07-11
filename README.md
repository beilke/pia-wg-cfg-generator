# Simple Private Internet Access WireGuard Config Generator

This script generates WireGuard configuration files for Private Internet Access (PIA) VPN service, simplifying the setup process by automatically selecting the best server based on ping response time.

## Standard Installation

```bash
git clone https://github.com/dieskim/simple-pia-wg-config-generator
cd simple-pia-wg-config-generator
chmod +x simple-pia-wg-config-generator.sh
DEBUG=1 PIA_USER=p0123456 PIA_PASS=xxxxxxxx ./simple-pia-wg-config-generator.sh
```

## Docker Installation

The Docker implementation uses Alpine Linux for a lightweight container (approximately 60MB) compared to Ubuntu-based alternatives (300MB+).

### Using the Pre-built Docker Image

The easiest way to get started is to use the pre-built Docker image:

```bash
docker pull fbeilke/pia-wg-generator:latest
```

### Quick Start with Docker Compose

A ready-to-use [`docker-compose.yml`](docker-compose.yml) ships with this repo — no Vault,
no build step, credentials as plain environment variables:

1. Download it (or clone the repo) and edit `PIA_USER`, `PIA_PASS` and `REGIONS`.
   Optionally enable the UniFi auto-push by setting `PUSH_TO_UNIFI: "1"` and
   filling in the `UNIFI_*` variables.

2. Run with Docker Compose:

```bash
docker compose up -d
```

Generated configs land in `./configs`, logs in `./logs`.

> For a Vault-integrated deployment (credentials fetched at startup, nothing
> secret in the compose file), see [`docker-compose.prod.yml`](docker-compose.prod.yml).

### Secure Setup with Environment Variables

To build your own container and keep your credentials secure:

1. Copy `.env.template` to `.env` and fill in your details:
   ```bash
   cp .env.template .env
   # Edit .env with your credentials
   ```

2. Run the build script:
   ```bash
   chmod +x generateBuild.sh
   ./generateBuild.sh
   ```

Your credentials will be loaded from the `.env` file, which is excluded from git.

### Docker Environment Variables

| Variable | Description | Default | Examples |
|----------|-------------|---------|----------|
| `PIA_USER` | Your PIA username | *required* | `p0123456` |
| `PIA_PASS` | Your PIA password | *required* | `your_password` |
| `REGIONS` | Comma-separated list of PIA regions | `uk` | `uk,france,nl_amsterdam` |
| `UPDATE_INTERVAL` | Cron schedule expression | `0 */12 * * *` | `*/5 * * * *` for every 5 minutes |
| `CONFIG_DIR` | Directory where configs will be stored | `/configs` | `/volume1/docker/configs` |
| `DEBUG` | Enable verbose output (0 or 1) | `0` | `1` |
| `PUSH_TO_UNIFI` | Push generated configs to UniFi VPN client networks (0 or 1) | `0` | `1` |
| `UNIFI_URL` | UniFi OS console URL | — | `https://192.168.1.1` |
| `UNIFI_USER` | UniFi local admin username (not SSO; can come from Vault) | — | `svc-mcp` |
| `UNIFI_PASS` | UniFi local admin password (can come from Vault) | — | — |
| `UNIFI_SITE` | UniFi site name | `default` | `default` |
| `UNIFI_REGION_MAP` | Maps PIA regions to UniFi network names | — | `uk=PIA-VPN-London,br=PIA-VPN-Brazil` |

### Custom Update Intervals

The container supports various update intervals. Here are some common cron schedule examples:

- Every 5 minutes: `*/5 * * * *`
- Every hour: `0 */1 * * *`
- Every 12 hours: `0 */12 * * *` (default)
- Once daily at midnight: `0 0 * * *`

### Running with Docker

```bash
docker run -d \
  --name pia-wg-generator \
  -e PIA_USER=your_username \
  -e PIA_PASS=your_password \
  -e REGIONS=uk,france,nl_amsterdam \
  -e UPDATE_INTERVAL="0 */12 * * *" \
  -e CONFIG_DIR=/configs \
  -v $(pwd)/configs:/configs \
  fbeilke/pia-wg-generator:latest
```

### Container Status

The container includes a healthcheck that verifies:
1. The startup has completed successfully
2. The cron service is running

You can check the container status with:

```bash
docker ps -a | grep pia-wg-generator
```

### Logs

Container logs can be viewed using:

```bash
docker logs pia-wg-generator
```

## Configuration Update Process

The container performs these steps when generating configurations:

1. Cleans up any old configuration files
2. Authenticates with the PIA API
3. Fetches the server list for each region
4. Pings all available servers in each region
5. Selects the server with the lowest ping time
6. Generates WireGuard configuration files
7. Copies the configuration files to the output directory
8. Optionally pushes each config to a UniFi VPN client network (see below)

This process runs both at startup and at the scheduled intervals specified by `UPDATE_INTERVAL`.

## UniFi Integration (optional)

With `PUSH_TO_UNIFI=1`, every generation run also updates matching **VPN Client**
networks on a UniFi gateway (UDM/UCG). UniFi stores WireGuard client profiles as
the raw `.conf` file inside the network config, so the push is a single API call
per region: the script logs into the UniFi OS console, finds each network listed
in `UNIFI_REGION_MAP` by name, and replaces its WireGuard configuration file with
the freshly generated one. The tunnels reconnect to the new (lowest-ping) server
within seconds.

Example without Vault — all credentials as plain environment variables:

```bash
docker run -d \
  --name pia-wg-generator \
  -e PIA_USER=p1234567 \
  -e PIA_PASS=your_pia_password \
  -e REGIONS=uk,br \
  -e PUSH_TO_UNIFI=1 \
  -e UNIFI_URL=https://192.168.1.1 \
  -e UNIFI_USER=unifi-local-admin \
  -e UNIFI_PASS=your_unifi_password \
  -e UNIFI_REGION_MAP="uk=PIA-VPN-London,br=PIA-VPN-Brazil" \
  -v $(pwd)/configs:/configs \
  fbeilke/pia-wg-generator:latest
```

Notes:

- The UniFi user must be a **local admin** (not an Ubiquiti SSO account).
  Credentials come from plain env vars (`UNIFI_USER`/`UNIFI_PASS`, as above), or
  — when the container runs in Vault mode — from Vault
  (`secret/data/mcp-infrastructure/unifi`, keys `username`/`password`). Vault is
  entirely optional.
- The VPN client networks must already exist on the controller (created once in
  the UI by importing any config file) — the script updates them, it does not
  create them.
- Configs are pushed unconditionally on every run; each push briefly restarts
  that WireGuard tunnel.
- Push failures never break config generation; see `/logs/unifi-push.log`.

## Recent Improvements

### Docker Container Enhancements

- **Alpine Linux Base**: Uses Alpine 3.18.3 for a lightweight container (~60MB)
- **Process Management**: Improved PID 1 handling with tini for proper signal processing
- **Cron Implementation**: Robust scheduling with environment variable preservation
- **Startup Optimization**: Streamlined initialization and configuration process
- **Reliable Execution**: Fixed issues with both initial and scheduled executions

### Script Enhancements

- **Server Selection**: Automatically selects server with lowest ping response time
- **Credentials Handling**: Securely manages PIA credentials from environment or properties files
- **Multiple Region Support**: Generates configs for multiple regions in one run
- **Cleanup Process**: Properly cleans old configs before generating new ones
- **Detailed Logging**: Better output and logging for troubleshooting

#### Core Features:

- **Lowest Latency Selection**: Pings all available servers in a region and selects the one with the best response time
- **Dynamic Region Selection**: Supports reading from a properties file or environment variables
- **Secure Credentials Handling**: Reads PIA credentials from file or environment
- **Filename with Latency Info**: Generated .conf files include ping response time in milliseconds
- **Docker Integration**: Complete containerization with proper scheduling and health checks


