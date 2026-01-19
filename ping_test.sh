#!/bin/bash

echo "--- Fetching Instance IPs ---"

# 1. Get Public IPs dynamically using AWS CLI filters
# We filter by Tag Name and ensure we only get 'running' instances
LINUX_A=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=Linux A" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
LINUX_B=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=Linux B" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
WINDOWS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=Windows" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
DATABASE=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=Database" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

# Verify we got IPs (Empty variables mean instances aren't running)
if [[ "$LINUX_A" == "None" || -z "$LINUX_A" ]]; then echo "Error: Could not find Linux A IP"; exit 1; fi
if [[ "$WINDOWS" == "None" || -z "$WINDOWS" ]]; then echo "Error: Could not find Windows IP"; exit 1; fi

echo "Linux A:  $LINUX_A"
echo "Linux B:  $LINUX_B"
echo "Windows:  $WINDOWS"
echo "Database: $DATABASE"
echo "-----------------------------"

# 2. Define Arrays for the Loop
# We use two arrays: one for IPs and one for Names so the output is readable
ips=("$LINUX_A" "$LINUX_B" "$WINDOWS" "$DATABASE")
names=("Linux A" "Linux B" "Windows" "Database")

# 3. The Ping Loop (Based on your script)
# Note: This executes the ping FROM CloudShell TO the targets.
for i in "${!ips[@]}"; do
  for j in "${!ips[@]}"; do
    if [ $i -ne $j ]; then
      echo "Checking connectivity: CloudShell → ${names[j]} (${ips[j]})"
      
      # Using a 2-second timeout (-W 2) so it doesn't hang if Windows blocks ping
      ping -c 1 -W 2 "${ips[j]}" | grep "time=" || echo "   ❌ Timeout/No reply (Check Security Groups or OS Firewall)"
    fi
  done
done