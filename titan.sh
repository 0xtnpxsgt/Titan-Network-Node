#!/bin/bash

# Define color codes
INFO='\033[0;36m'  # Cyan
BANNER='\033[0;35m' # Magenta
WARNING='\033[0;33m'
ERROR='\033[0;31m'
SUCCESS='\033[0;32m'
NC='\033[0m' # No Color

# Display banner
echo -e "${BANNER}=========================================================================${NC}"
echo -e "${BANNER}               Titan Edge Docker Setup Script v1.0                        ${NC}"
echo -e "${BANNER}=========================================================================${NC}"

# Function to ensure a non-empty value
get_non_empty_input() {
    local prompt="$1"
    local input=""
    while [ -z "$input" ]; do
        read -p "$prompt" input
        if [ -z "$input" ]; then
            echo -e "${ERROR}Error: This field cannot be empty.${NC}"
        fi
    done
    echo "$input"
}

# Ask for the number of Titan Edge instances
read -p "How many Titan Edge instances would you like to create? " instance_count

# Loop through the instances
for i in $(seq 1 "$instance_count"); do
    echo -e "${INFO}Configuring Titan Edge instance $i:${NC}"

    # Prompt for device name
    device_name=$(get_non_empty_input "Enter a unique device name for instance $i: ")
    if [ -z "$device_name" ]; then
        device_name="instance_$i"
    fi

    # Create a directory for this device's configuration
    device_dir="./$device_name"
    if [ ! -d "$device_dir" ]; then
        mkdir "$device_dir"
        echo -e "${INFO}Created directory for $device_name at $device_dir${NC}"
    fi

    # Proxy configuration for each instance
    echo "Configuring proxy for Titan Edge instance $i:"
    read -p "Enter proxy in format IP:PORT:USERNAME:PASSWORD: " proxy_details
    proxy_ip=$(echo $proxy_details | cut -d':' -f1)
    proxy_port=$(echo $proxy_details | cut -d':' -f2)
    proxy_username=$(echo $proxy_details | cut -d':' -f3)
    proxy_password=$(echo $proxy_details | cut -d':' -f4)

    # Generate Dockerfile
    echo -e "${INFO}Creating Dockerfile for $device_name...${NC}"
    cat <<EOF > "$device_dir/Dockerfile"
FROM nezha123/titan-edge
WORKDIR /app
EOF

    # Create and configure redsocks if a proxy is used
    cat <<EOF > "$device_dir/redsocks.conf"
base {
    log_debug = off;
    log_info = on;
    log = "file:/var/log/redsocks.log";
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;
    ip = $proxy_ip;
    port = $proxy_port;
    type = http-connect;
    login = "$proxy_username";
    password = "$proxy_password";
}
EOF

    # Entrypoint script for redsocks
    cat <<EOF > "$device_dir/entrypoint.sh"
#!/bin/sh
redsocks -c /etc/redsocks.conf &
sleep 5
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-ports 12345
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports 12345
exec "\$@"
EOF

    chmod +x "$device_dir/entrypoint.sh"

    # Build and run Docker container
    docker build -t "titan_edge_docker_$device_name" "$device_dir"
    docker run -d --cap-add=NET_ADMIN -v "$device_dir/redsocks.conf:/etc/redsocks.conf" \
    -v "$device_dir/entrypoint.sh:/entrypoint.sh" --name "$device_name" \
    "titan_edge_docker_$device_name" /entrypoint.sh

    echo -e "${SUCCESS}Titan Edge instance $i ($device_name) has been set up successfully.${NC}"
done
