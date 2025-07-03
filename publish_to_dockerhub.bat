@echo off
echo Publishing PIA WireGuard Config Generator to DockerHub...

docker login

bash publish_to_dockerhub_fixed.sh

echo.
echo If successful, users can run the container with:
echo docker-compose -f docker-compose.fixed.yml up -d
