#!/bin/bash
echo "Starting cleanup process..."

echo "Step 1/2: Stopping Docker containers..."
docker compose down

echo "Step 2/2: Removing postgres data..."
rm -r tmp/