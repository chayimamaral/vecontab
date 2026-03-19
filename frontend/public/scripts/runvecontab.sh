#!/bin/bash

# Define the paths to the backend and frontend directories
backend_dir="/path/to/vecontab/backend"
frontend_dir="/path/to/vecontab/frontend"

# Define the commands to start and stop the servers
start_backend="yarn start > $backend_dir/server.log 2>&1 &"
start_frontend="yarn start > $frontend_dir/server.log 2>&1 &"
stop_backend="yarn stop"
stop_frontend="yarn stop"

# Define a function to start the servers
function start_servers() {
  # Start the backend application
  cd $backend_dir
  eval $start_backend
  backend_pid=$!

  # Start the frontend application
  cd $frontend_dir
  eval $start_frontend
  frontend_pid=$!

  # Check the status of the servers
  while true; do
    backend_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health)
    frontend_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/health)

    echo "Backend status: $backend_status"
    echo "Frontend status: $frontend_status"

    if [ $backend_status -eq 200 ] && [ $frontend_status -eq 200 ]; then
      echo "Both servers are up and running"
      break
    fi

    sleep 5
  done
}

# Define a function to stop the servers
function stop_servers() {
  # Stop the servers
  cd $backend_dir
  $stop_backend
  cd $frontend_dir
  $stop_frontend
}

# Check the command-line arguments
if [ "$1" == "start" ]; then
  start_servers
elif [ "$1" == "stop" ]; then
  stop_servers
else
  echo "Usage: $0 [start|stop]"
  exit 1
fi