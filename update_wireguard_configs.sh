#!/bin/bash

# Remove all .conf files from configs/ directory
rm -f configs/*.conf

# Remove all .conf files from /volume1/docker/downloads/
rm -f /volume1/docker/downloads/*.conf

# Run the WireGuard config generator
./pia-wg-cfg-generator.sh

# Run wg-debug.sh on all .conf files
sudo ./wg-debug.sh configs/*.conf

# Copy generated .conf files to /volume1/docker/downloads/
cp -v configs/*.conf /volume1/docker/downloads/

echo "WireGuard configuration update completed successfully."
