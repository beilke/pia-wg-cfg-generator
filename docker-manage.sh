#!/bin/bash
# Helper script to manage the PIA WireGuard Config Generator Docker container

set -e

# Configuration - edit as needed
CONTAINER_NAME="pia-wg-generator"
IMAGE_NAME="pia-wg-generator"
CONFIG_OUTPUT_DIR="./config-output"

# Function to display usage information
usage() {
    echo "Usage: $0 [command]"
    echo "Commands:"
    echo "  build      - Build the Docker image"
    echo "  start      - Start the container (build if needed)"
    echo "  stop       - Stop the container"
    echo "  restart    - Restart the container"
    echo "  logs       - View container logs"
    echo "  status     - Check container status"
    echo "  exec       - Execute a shell inside the container"
    echo "  update     - Trigger a manual config update"
    echo "  info       - Show container information"
    echo "  help       - Show this help message"
}

# Function to check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed or not in PATH"
        exit 1
    fi
}

# Function to build the Docker image
build_image() {
    echo "Building Docker image: $IMAGE_NAME"
    docker build -t "$IMAGE_NAME" .
}

# Function to start the container
start_container() {
    if ! docker image inspect "$IMAGE_NAME" &> /dev/null; then
        echo "Image not found, building..."
        build_image
    fi

    echo "Loading credentials..."
    if [ -f .env ]; then
        source .env
    else
        echo "No .env file found. Using default values."
        PIA_USER=${PIA_USER:-"your_pia_username"}
        PIA_PASS=${PIA_PASS:-"your_pia_password"}
        REGIONS=${REGIONS:-"uk"}
        UPDATE_INTERVAL=${UPDATE_INTERVAL:-"0 */12 * * *"}
    fi

    # Make sure the output directory exists
    mkdir -p "$CONFIG_OUTPUT_DIR"

    echo "Starting container..."
    docker run -d --name "$CONTAINER_NAME" \
        -e "PIA_USER=$PIA_USER" \
        -e "PIA_PASS=$PIA_PASS" \
        -e "REGIONS=$REGIONS" \
        -e "UPDATE_INTERVAL=$UPDATE_INTERVAL" \
        -e "CONFIG_DIR=/configs" \
        -v "$(pwd)/$CONFIG_OUTPUT_DIR:/configs" \
        --restart unless-stopped \
        "$IMAGE_NAME"

    echo "Container started. View logs with: $0 logs"
}

# Check for Docker
check_docker

# Process commands
case "$1" in
    build)
        build_image
        ;;
    start)
        # Check if container already exists
        if docker ps -a | grep -q "$CONTAINER_NAME"; then
            echo "Container already exists. Use restart to recreate it."
            exit 1
        fi
        start_container
        ;;
    stop)
        echo "Stopping container..."
        docker stop "$CONTAINER_NAME" || true
        docker rm "$CONTAINER_NAME" || true
        ;;
    restart)
        echo "Restarting container..."
        docker stop "$CONTAINER_NAME" || true
        docker rm "$CONTAINER_NAME" || true
        start_container
        ;;
    logs)
        docker logs -f "$CONTAINER_NAME"
        ;;
    status)
        echo "Container status:"
        docker ps -a | grep "$CONTAINER_NAME" || echo "Container not found"
        
        echo -e "\nLatest configs:"
        find "$CONFIG_OUTPUT_DIR" -name "*.conf" -type f -printf "%T+ %p\n" | sort -r | head -5
        ;;
    exec)
        docker exec -it "$CONTAINER_NAME" /bin/bash
        ;;
    update)
        echo "Triggering manual update..."
        docker exec "$CONTAINER_NAME" /bin/bash /app/docker_update_wireguard_configs.sh
        ;;
    info)
        echo "Container info:"
        docker exec "$CONTAINER_NAME" /bin/bash -c "cat /etc/alpine-release && echo 'Alpine Linux'"
        docker exec "$CONTAINER_NAME" /bin/bash -c "wg --version"
        docker image ls "$IMAGE_NAME"
        ;;
    help|*)
        usage
        ;;
esac
