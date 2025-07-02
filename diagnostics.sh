#!/bin/bash
# Advanced diagnostics script for PIA WireGuard Config Generator container

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

CONTAINER_NAME="pia-wg-generator"
CONFIG_DIR="/volume1/docker/pia-wireguard/generated_configs"

echo -e "${PURPLE}=== PIA WireGuard Config Generator Diagnostics ===${NC}\n"

# Check Docker service
echo -e "${BLUE}[1/9] Checking Docker service...${NC}"
if docker info &>/dev/null; then
    echo -e "  ${GREEN}✓ Docker is running${NC}"
    docker_version=$(docker --version | head -n 1)
    echo -e "  Version: $docker_version"
else
    echo -e "  ${RED}✗ Docker is not running${NC}"
    echo -e "  Try restarting Docker with: sudo systemctl restart docker"
    exit 1
fi

# Check for container image
echo -e "\n${BLUE}[2/9] Checking for container image...${NC}"
if docker image inspect pia-wg-generator:latest &>/dev/null; then
    image_id=$(docker image inspect --format='{{.Id}}' pia-wg-generator:latest)
    image_created=$(docker image inspect --format='{{.Created}}' pia-wg-generator:latest)
    image_size=$(docker image inspect --format='{{.Size}}' pia-wg-generator:latest | numfmt --to=iec)
    echo -e "  ${GREEN}✓ Image found${NC}"
    echo -e "  ID: $image_id"
    echo -e "  Created: $image_created"
    echo -e "  Size: $image_size"
else
    echo -e "  ${RED}✗ Image not found${NC}"
    echo -e "  Run './generateBuild.sh' to create the image"
fi

# Check container status
echo -e "\n${BLUE}[3/9] Checking container status...${NC}"
if docker ps -a | grep -q $CONTAINER_NAME; then
    container_status=$(docker inspect --format='{{.State.Status}}' $CONTAINER_NAME 2>/dev/null)
    container_health=$(docker inspect --format='{{.State.Health.Status}}' $CONTAINER_NAME 2>/dev/null)
    started_at=$(docker inspect --format='{{.State.StartedAt}}' $CONTAINER_NAME 2>/dev/null)
    
    echo -e "  Status: $(if [ "$container_status" = "running" ]; then echo -e "${GREEN}$container_status${NC}"; else echo -e "${RED}$container_status${NC}"; fi)"
    echo -e "  Health: $(if [ "$container_health" = "healthy" ]; then echo -e "${GREEN}$container_health${NC}"; else echo -e "${YELLOW}$container_health${NC}"; fi)"
    echo -e "  Started at: $started_at"
    
    if [ "$container_status" != "running" ]; then
        exit_code=$(docker inspect --format='{{.State.ExitCode}}' $CONTAINER_NAME 2>/dev/null)
        finished_at=$(docker inspect --format='{{.State.FinishedAt}}' $CONTAINER_NAME 2>/dev/null)
        echo -e "  ${RED}Container exited with code $exit_code at $finished_at${NC}"
        echo -e "  Last 10 log lines:"
        docker logs --tail 10 $CONTAINER_NAME
    fi
else
    echo -e "  ${RED}✗ Container not found${NC}"
    echo -e "  Run './generateBuild.sh' to create and start the container"
fi

# Check container network
echo -e "\n${BLUE}[4/9] Checking container network...${NC}"
if docker ps -q -f name=$CONTAINER_NAME &>/dev/null; then
    network_name=$(docker inspect --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' $CONTAINER_NAME)
    ip_address=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_NAME)
    echo -e "  Network: $network_name"
    echo -e "  IP Address: $ip_address"
else
    echo -e "  ${RED}✗ Container not running, network information unavailable${NC}"
fi

# Check container logs for errors
echo -e "\n${BLUE}[5/9] Checking container logs for errors...${NC}"
if docker ps -q -f name=$CONTAINER_NAME &>/dev/null; then
    error_count=$(docker logs $CONTAINER_NAME 2>&1 | grep -i "error\|failed\|failure\|cannot\|unable" | wc -l)
    if [ $error_count -gt 0 ]; then
        echo -e "  ${RED}Found $error_count potential error messages${NC}"
        echo -e "  Recent errors:"
        docker logs $CONTAINER_NAME 2>&1 | grep -i "error\|failed\|failure\|cannot\|unable" | tail -n 5
    else
        echo -e "  ${GREEN}✓ No obvious errors found in logs${NC}"
    fi
else
    echo -e "  ${RED}✗ Container not running, cannot check logs${NC}"
fi

# Check running processes in container
echo -e "\n${BLUE}[6/9] Checking processes in container...${NC}"
if docker ps -q -f name=$CONTAINER_NAME &>/dev/null; then
    echo -e "  Process list:"
    docker exec -t $CONTAINER_NAME ps aux || echo -e "  ${RED}Failed to execute process listing command${NC}"
    
    # Specifically check for crond
    if docker exec -t $CONTAINER_NAME pgrep crond &>/dev/null; then
        echo -e "  ${GREEN}✓ crond process is running${NC}"
    else
        echo -e "  ${RED}✗ crond process is not running${NC}"
    fi
else
    echo -e "  ${RED}✗ Container not running, cannot check processes${NC}"
fi

# Check config files
echo -e "\n${BLUE}[7/9] Checking configuration files...${NC}"
if [ -d "$CONFIG_DIR" ]; then
    config_count=$(find "$CONFIG_DIR" -name "*.conf" 2>/dev/null | wc -l)
    if [ $config_count -gt 0 ]; then
        echo -e "  ${GREEN}✓ Found $config_count configuration files${NC}"
        
        # Get newest file
        newest_file=$(find "$CONFIG_DIR" -name "*.conf" -type f -printf "%T@ %T+ %p\n" 2>/dev/null | sort -nr | head -1)
        if [ -n "$newest_file" ]; then
            newest_time=$(echo "$newest_file" | cut -d' ' -f2)
            newest_path=$(echo "$newest_file" | cut -d' ' -f3-)
            echo -e "  Most recent file: $(basename "$newest_path") (created $newest_time)"
        fi
    else
        echo -e "  ${RED}✗ No configuration files found${NC}"
    fi
else
    echo -e "  ${RED}✗ Configuration directory not found: $CONFIG_DIR${NC}"
fi

# Check cron configuration
echo -e "\n${BLUE}[8/9] Checking cron configuration...${NC}"
if docker ps -q -f name=$CONTAINER_NAME &>/dev/null; then
    crontab=$(docker exec -t $CONTAINER_NAME cat /etc/crontabs/root 2>/dev/null)
    if [ -n "$crontab" ]; then
        echo -e "  ${GREEN}✓ Crontab is configured:${NC}"
        echo -e "$crontab" | sed 's/^/  /'
    else
        echo -e "  ${RED}✗ No crontab found${NC}"
    fi
else
    echo -e "  ${RED}✗ Container not running, cannot check cron configuration${NC}"
fi

# Provide fix suggestions
echo -e "\n${BLUE}[9/9] Diagnostics summary and suggestions:${NC}"
if docker ps -q -f name=$CONTAINER_NAME &>/dev/null; then
    if [ "$container_status" = "running" ] && [ "$container_health" = "healthy" ]; then
        echo -e "  ${GREEN}✓ Container appears to be functioning normally${NC}"
    else
        echo -e "  ${YELLOW}Container is running but may have issues${NC}"
        echo -e "  Suggested fixes:"
        echo -e "  - Restart the container: docker restart $CONTAINER_NAME"
        echo -e "  - Rebuild container: ./generateBuild.sh"
        echo -e "  - Check for proper Alpine support: docker exec $CONTAINER_NAME sh -c 'cat /etc/alpine-release'"
    fi
else
    echo -e "  ${RED}✗ Container is not running${NC}"
    echo -e "  Suggested fixes:"
    echo -e "  - Rebuild and start container: ./generateBuild.sh"
    echo -e "  - Check Docker logs: docker logs $CONTAINER_NAME"
fi

echo -e "\n${PURPLE}=== Diagnostics Complete ===${NC}"
echo -e "For more detailed logs: docker logs $CONTAINER_NAME"
