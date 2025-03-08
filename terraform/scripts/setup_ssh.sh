#!/bin/bash
# SSH setup script for Alpine LXC containers with improved reliability
# This script handles SSH installation with proper error handling and retries

set -e

CONTAINER_ID=$1
MAX_ATTEMPTS=5
DELAY=10

if [ -z "$CONTAINER_ID" ]; then
  echo "Error: Container ID not provided"
  exit 1
fi

# Create log file
LOG_FILE="ssh_setup_${CONTAINER_ID}.log"
echo "SSH Setup for container ${CONTAINER_ID} - $(date)" > $LOG_FILE

# Function to check if container is running and accepting commands
check_container() {
  echo "Checking if container ${CONTAINER_ID} is ready..." >> $LOG_FILE
  pct status $CONTAINER_ID 2>&1 | grep "running" > /dev/null
  return $?
}

# Function to run a command in container with retries
run_in_container() {
  local cmd=$1
  local attempt=1
  
  while [ $attempt -le $MAX_ATTEMPTS ]; do
    echo "Attempt $attempt: Running command: $cmd" >> $LOG_FILE
    if pct exec $CONTAINER_ID -- ash -c "$cmd" >> $LOG_FILE 2>&1; then
      echo "Command successful" >> $LOG_FILE
      return 0
    else
      echo "Command failed, retrying in $DELAY seconds..." >> $LOG_FILE
      sleep $DELAY
      attempt=$((attempt+1))
    fi
  done
  
  echo "ERROR: Failed to execute command after $MAX_ATTEMPTS attempts: $cmd" >> $LOG_FILE
  return 1
}

# Wait for container to be ready
attempt=1
while [ $attempt -le $MAX_ATTEMPTS ]; do
  echo "Waiting for container ${CONTAINER_ID} to be ready (attempt $attempt/$MAX_ATTEMPTS)..." >> $LOG_FILE
  if check_container; then
    echo "Container ${CONTAINER_ID} is running" >> $LOG_FILE
    # Extra wait to ensure container is fully initialized
    sleep 5
    break
  fi
  sleep $DELAY
  attempt=$((attempt+1))
done

if ! check_container; then
  echo "ERROR: Container ${CONTAINER_ID} is not running after $MAX_ATTEMPTS attempts" >> $LOG_FILE
  exit 1
fi

# Step 1: Update package index
echo "Updating package index..." >> $LOG_FILE
if ! run_in_container "apk update"; then
  echo "WARNING: Package update might have partially failed, continuing anyway" >> $LOG_FILE
fi

# Step 2: Install openssh
echo "Installing openssh..." >> $LOG_FILE
if ! run_in_container "apk add openssh"; then
  echo "ERROR: Failed to install SSH" >> $LOG_FILE
  exit 1
fi

# Step 3: Configure SSH
echo "Configuring SSH..." >> $LOG_FILE
run_in_container "rc-update add sshd"
run_in_container "mkdir -p /etc/ssh/"
run_in_container 'echo "PermitRootLogin yes" >> /etc/ssh/sshd_config'
run_in_container 'echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config'

# Step 4: Start SSH service
echo "Starting SSH service..." >> $LOG_FILE
if ! run_in_container "/etc/init.d/sshd start"; then
  echo "WARNING: Failed to start SSH service, will try one more time" >> $LOG_FILE
  sleep 5
  if ! run_in_container "/etc/init.d/sshd start"; then
    echo "ERROR: Failed to start SSH service after retry" >> $LOG_FILE
    exit 1
  fi
fi

echo "SSH setup completed successfully for container ${CONTAINER_ID}" >> $LOG_FILE
exit 0
