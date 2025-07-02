#!/bin/bash
# Script to check the status of the PIA WireGuard config generator container

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== PIA WireGuard Config Generator Status ===${NC}"

# Check if container exists
if ! docker ps -a | grep -q pia-wg-generator; then
    echo -e "${RED}Container not found. Run generateBuild.sh to create it.${NC}"
    exit 1
fi

# Check container status
container_status=$(docker inspect -f '{{.State.Status}}' pia-wg-generator 2>/dev/null)
if [ "$container_status" = "running" ]; then
    echo -e "${GREEN}Container is running${NC}"
    
    # Get container uptime
    start_time=$(docker inspect -f '{{.State.StartedAt}}' pia-wg-generator | xargs date +%s -d)
    current_time=$(date +%s)
    uptime_seconds=$((current_time - start_time))
    days=$((uptime_seconds / 86400))
    hours=$(( (uptime_seconds % 86400) / 3600 ))
    minutes=$(( (uptime_seconds % 3600) / 60 ))
    echo -e "Uptime: ${days}d ${hours}h ${minutes}m"
    
    # Check health status
    health_status=$(docker inspect -f '{{.State.Health.Status}}' pia-wg-generator 2>/dev/null)
    if [ "$health_status" = "healthy" ]; then
        echo -e "Health: ${GREEN}$health_status${NC}"
    else
        echo -e "Health: ${RED}$health_status${NC}"
        echo -e "\nHealth check details:"
        docker inspect -f '{{range .State.Health.Log}}{{.Output}}{{end}}' pia-wg-generator | tail -n 5
    fi
    
    # Check for running processes in container
    echo -e "\nProcesses in container:"
    docker exec pia-wg-generator ps -ef
else
    echo -e "${RED}Container is not running (status: $container_status)${NC}"
    
    # Show last few log lines for debugging
    echo -e "\nLast container logs before it stopped:"
    docker logs --tail 20 pia-wg-generator
fi

# Check the configuration files
config_dir="/volume1/docker/pia-wireguard/generated_configs"
if [ -d "$config_dir" ]; then
    config_count=$(find "$config_dir" -name "*.conf" | wc -l)
    echo -e "\n${YELLOW}Configuration Files:${NC}"
    echo -e "Found ${GREEN}$config_count${NC} configuration files in $config_dir"
    
    # Show most recent files
    echo -e "\nMost recent config files:"
    find "$config_dir" -name "*.conf" -type f -printf "%T+ %p\n" | sort -r | head -5 | \
        while read line; do
            file=$(echo "$line" | cut -d' ' -f2-)
            timestamp=$(echo "$line" | cut -d' ' -f1)
            filename=$(basename "$file")
            echo -e "${GREEN}$timestamp${NC} - $filename"
        done
else
    echo -e "\n${RED}Config directory not found: $config_dir${NC}"
fi

# Get recent logs
echo -e "\n${YELLOW}Recent Logs:${NC}"
docker logs --tail 10 pia-wg-generator 2>&1

echo -e "\n${YELLOW}=== End of Status Report ===${NC}"
echo -e "For full logs: ${GREEN}docker logs pia-wg-generator${NC}"
