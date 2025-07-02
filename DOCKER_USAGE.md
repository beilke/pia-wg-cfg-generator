# Building and Running the PIA WireGuard Config Generator Docker Container

## Build the Docker image
docker build -t pia-wg-generator .

## Run with Docker command line
docker run -d \
  --name pia-wg-generator \
  -e PIA_USER=your_username \
  -e PIA_PASS=your_password \
  -e REGIONS=uk,france,nl_amsterdam \
  -e UPDATE_INTERVAL="0 */12 * * *" \
  -e CONFIG_DIR=/configs \
  -e DEBUG=0 \
  -v $(pwd)/config-output:/configs \
  pia-wg-generator

## View logs
docker logs -f pia-wg-generator

## Stop container
docker stop pia-wg-generator

## Remove container
docker rm pia-wg-generator

## Using Docker Compose
# First ensure you've edited docker-compose.yml with your credentials
docker-compose up -d

## Stop Docker Compose
docker-compose down
