#!/bin/bash

#
# This script is meant for quick & easy install of Replicated Studio via:
#   'curl -sSL {{ replicated_install_url }}/studio | sudo bash'
# or:
#   'wget -qO- {{ replicated_install_url }}/studio | sudo bash'
#

echo "Installing Replicated"

curl '{{ replicated_install_url }}/docker?customer_base_url="http://172.17.0.1:8006"' | sudo bash

echo "Starting Replicated Studio"

mkdir -p ./replicated

docker run --name studio -d \
     --restart always \
     -v `pwd`/replicated:/replicated \
     -p 8006:8006 \
     replicated/studio:latest

echo "Replicated Studio started"
