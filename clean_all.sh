#!/bin/bash
echo "Starting cleanup process..."

echo "Step 1/4: Stopping Docker containers..."
docker compose down

echo "Step 2/4: Removing configuration..."
rm -r data/
rm .env

echo "Step 3/4: Removing secrets..."
rm -r secrets/

echo "Step 4/4: Removing postgres data..."
rm -r tmp/