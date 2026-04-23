#!/bin/bash

# 1. Check for root/sudo
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root or with sudo."
  exit 1
fi

CONTAINER_NAME="portainer"
IMAGE_NAME="portainer/portainer-ce:lts"

echo "Checking for Portainer installation and updates..."

# 2. Check if the container already exists
if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
  # Container exists, proceed with update logic
  CURRENT_ID=$(docker inspect --format '{{.Image}}' $CONTAINER_NAME 2>/dev/null)

  docker pull $IMAGE_NAME
  LATEST_ID=$(docker inspect --format '{{.Id}}' $IMAGE_NAME)

  if [ "$CURRENT_ID" == "$LATEST_ID" ]; then
    echo "Portainer is already up to date. Nothing to do."
    exit 0
  else
    echo "New version available. Updating..."
    echo "Stopping current Portainer container..."
    docker stop $CONTAINER_NAME
    echo "Removing old container..."
    docker rm $CONTAINER_NAME
  fi
else
  # Container does not exist, prepare for fresh install
  echo "Portainer not found. Initiating fresh installation..."
  docker pull $IMAGE_NAME
fi

# 3. Run the new container (executes for both new installs and updates)
echo "Starting Portainer container..."
docker run -d \
  -p 8000:8000 \
  -p 9443:9443 \
  --name=$CONTAINER_NAME \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /opt/portainer:/data \
  $IMAGE_NAME

# 4. Optional: cleanup old images to save space
echo "Cleaning up old images..."
docker image prune -f

echo "Operation complete! Portainer is running."
