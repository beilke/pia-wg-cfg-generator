# Simple Private Internet Access WireGuard Config Generator

This script generates WireGuard configuration files for Private Internet Access (PIA) VPN service, simplifying the setup process.

## Standard Installation

```bash
git clone https://github.com/dieskim/simple-pia-wg-config-generator
cd simple-pia-wg-config-generator
chmod +x simple-pia-wg-config-generator.sh
DEBUG=1 PIA_USER=p0123456 PIA_PASS=xxxxxxxx ./simple-pia-wg-config-generator.sh
```

## Docker Installation

The Docker implementation uses Alpine Linux for a lightweight container (approximately 60MB) compared to Ubuntu-based alternatives (300MB+).

### Secure Setup with Environment Variables

To keep your credentials secure:

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

### Quick Start with Docker Compose

1. Edit `docker-compose.yml` and set your PIA credentials and desired regions
2. Run with Docker Compose:

```bash
docker-compose up -d
```

### Docker Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PIA_USER` | Your PIA username | *required* |
| `PIA_PASS` | Your PIA password | *required* |
| `REGIONS` | Comma-separated list of PIA regions | `uk` |
| `UPDATE_INTERVAL` | Cron schedule expression | `0 */12 * * *` (every 12 hours) |
| `CONFIG_DIR` | Directory where configs will be stored | `/configs` |
| `DEBUG` | Enable verbose output (0 or 1) | `0` |

### Running with Docker

```bash
docker run -d \
  --name pia-wg-generator \
  -e PIA_USER=your_username \
  -e PIA_PASS=your_password \
  -e REGIONS=uk,france,nl_amsterdam \
  -e UPDATE_INTERVAL="0 */12 * * *" \
  -e CONFIG_DIR=/configs \
  -v $(pwd)/config-output:/configs \
  pia-wg-generator
```

### Logs

Container logs can be viewed using:

```bash
docker logs pia-wg-generator
```

## Credits

This script is based on PIA FOSS manual connections.
https://github.com/pia-foss/manual-connections/tree/master

#### Changes promoted from original Dieskim version: 
Script Purpose Update:
    The description now states that the script selects the WireGuard server with the lowest latency within a region.

Added Server Responsiveness Check:
    The script now includes ping in the list of required tools.
    Before generating configuration files, it checks if the servers are responsive using ping.

Credentials Handling Improvement:
    The script now reads PIA credentials from a file (credentials.properties) if available.
    If credentials are missing, it falls back to default values.

Improved Region Selection:
    The script allows for manual region selection or reads from a predefined regions.properties file.

Lowest Latency Selection:
    Instead of selecting any available server, the script now pings all available servers in a region.
    The server with the lowest response time is chosen for the WireGuard configuration.

Filename Update with Latency Info:
    The generated .conf file now includes the ping response time in milliseconds, e.g., pia-austria-vienna401_8ms.conf.


Also thanks to @beilke for the contribution
