# PIA WireGuard Config Generator

A Docker container that automatically generates and updates WireGuard configuration files for Private Internet Access (PIA) VPN. It pings servers in your selected regions and creates configuration files for the ones with the lowest latency.

## Features

- **Automatic Server Selection**: Pings servers in specified regions to find the ones with lowest latency
- **Regular Updates**: Automatically regenerates configs on a customizable schedule
- **Multiple Regions**: Generate configs for multiple PIA regions at once
- **Lightweight**: Based on Alpine Linux for a small container footprint (~60MB)
- **Easy Setup**: Simple environment variables to configure

## Usage

### Quick Start

```bash
docker run -d \
  --name pia-wg-generator \
  -e PIA_USER=your_username \
  -e PIA_PASS=your_password \
  -e REGIONS=uk,france,nl_amsterdam \
  -v /path/to/configs:/configs \
  --restart unless-stopped \
  YOUR_DOCKERHUB_USERNAME/pia-wg-generator:latest
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PIA_USER` | Your PIA username | *required* |
| `PIA_PASS` | Your PIA password | *required* |
| `REGIONS` | Comma-separated list of PIA regions | `uk` |
| `UPDATE_INTERVAL` | Cron-like schedule expression | `0 */12 * * *` (every 12 hours) |
| `CONFIG_DIR` | Directory inside container where configs will be stored | `/configs` |
| `DEBUG` | Enable verbose output (0 or 1) | `0` |

### Available Update Intervals

The container supports these predefined intervals:
- `0 */1 * * *` - Every 1 hour
- `0 */2 * * *` - Every 2 hours
- `0 */4 * * *` - Every 4 hours
- `0 */6 * * *` - Every 6 hours
- `0 */12 * * *` - Every 12 hours (default)
- `0 0 * * *` - Once a day at midnight

### Available Regions

Some common region codes:
- `uk` - United Kingdom
- `us` - United States
- `ca` - Canada
- `au` - Australia
- `de-frankfurt` - Frankfurt, Germany
- `nl_amsterdam` - Amsterdam, Netherlands
- `swiss` - Switzerland
- `sweden` - Sweden
- `norway` - Norway
- `denmark` - Denmark
- `france` - France
- `brazil` - Brazil

## Docker Compose Example

```yaml
version: '3'

services:
  pia-wg-generator:
    image: YOUR_DOCKERHUB_USERNAME/pia-wg-generator:latest
    container_name: pia-wg-generator
    environment:
      - PIA_USER=your_pia_username
      - PIA_PASS=your_pia_password
      - REGIONS=uk,france,nl_amsterdam
      - UPDATE_INTERVAL=0 */12 * * *
    volumes:
      - ./config-output:/configs
    restart: unless-stopped
```

## Logs

View container logs to see the generated configurations:

```bash
docker logs pia-wg-generator
```

## Source Code

The source code for this Docker image is available on GitHub: [Link to your GitHub repo]

## Credits

Based on the PIA WireGuard Config Generator with contributions from multiple developers.
