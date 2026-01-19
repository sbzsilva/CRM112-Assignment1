#!/bin/bash

echo "--- Fetching Instance IPs ---"

# 1. Get Public IPs dynamically using AWS CLI filters
# Filters: Name tag and 'running' state
LINUX_A=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=Linux A" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
LINUX_B=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=Linux B" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
WINDOWS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=Windows" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
DATABASE=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=Database" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

# Check if IPs were found
if [[ "$LINUX_A" == "None" || -z "$LINUX_A" ]]; then echo "[ERROR] Could not find Linux A IP"; exit 1; fi
if [[ "$WINDOWS" == "None" || -z "$WINDOWS" ]]; then echo "[ERROR] Could not find Windows IP"; exit 1; fi

# Display IPs for your reference
echo "Linux A:  $LINUX_A"
echo "Linux B:  $LINUX_B"
echo "Windows:  $WINDOWS"
echo "Database: $DATABASE"
echo "-----------------------------"

# 2. Define Arrays for the Loop
ips=("$LINUX_A" "$LINUX_B" "$WINDOWS" "$DATABASE")
names=("Linux A" "Linux B" "Windows" "Database")

# 3. Connectivity Loop
# Note: This checks connectivity from CloudShell TO the instances.
echo "Starting Connectivity Check..."

for i in "${!ips[@]}"; do
    TARGET_IP="${ips[$i]}"
    TARGET_NAME="${names[$i]}"

    # Ping command: count 1, wait 2 seconds max
    # We hide standard output and only show result based on success/failure
    if ping -c 1 -W 2 "$TARGET_IP" &> /dev/null; then
        echo "[OK] CloudShell -> $TARGET_NAME ($TARGET_IP)"
    else
        echo "[FAIL] CloudShell -> $TARGET_NAME ($TARGET_IP) - Request Timed Out"
    fi
done