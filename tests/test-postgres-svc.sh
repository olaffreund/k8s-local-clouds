#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Running tests for PostgreSQL database..."

# Set up port forwarding to PostgreSQL
kubectl port-forward service/postgres-svc 5432:5432 -n local-apps &
PF_PID=$!

# Give port forwarding time to establish
sleep 3

# Check if PostgreSQL is available
if command -v pg_isready &>/dev/null; then
  echo "Checking PostgreSQL connection using pg_isready..."
  if pg_isready -h localhost -p 5432 -U appuser; then
    echo "✅ PostgreSQL connection test passed"
  else
    echo "❌ PostgreSQL connection test failed"
    kill $PF_PID
    exit 1
  fi
else
  echo "pg_isready not available, skipping direct connection test"
fi

# Run a test query using psql if available
if command -v psql &>/dev/null; then
  echo "Testing PostgreSQL query execution..."
  if PGPASSWORD=apppassword psql -h localhost -p 5432 -U appuser -d appdb -c "SELECT 1 as test;" -t | grep -q "1"; then
    echo "✅ PostgreSQL query execution test passed"
  else
    echo "❌ PostgreSQL query execution test failed"
    kill $PF_PID
    exit 1
  fi
else
  echo "psql not available, using alternative connection test..."
  
  # Alternative test using netcat
  if command -v nc &>/dev/null; then
    if nc -z localhost 5432; then
      echo "✅ PostgreSQL port is open and accepting connections"
    else
      echo "❌ PostgreSQL port is not accessible"
      kill $PF_PID
      exit 1
    fi
  else
    echo "⚠️ Neither psql nor nc available, cannot perform comprehensive tests"
  fi
fi

# Clean up port forwarding
kill $PF_PID

echo "✨ PostgreSQL tests completed successfully!"