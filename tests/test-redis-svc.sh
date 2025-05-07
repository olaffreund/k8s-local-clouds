#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Running tests for Redis service..."

# Set up port forwarding to Redis
kubectl port-forward service/redis-svc 6379:6379 -n local-apps &
PF_PID=$!

# Give port forwarding time to establish
sleep 3

# Check if Redis CLI is available
if command -v redis-cli &>/dev/null; then
  echo "Testing Redis connection with redis-cli..."
  
  # Test ping command
  if redis-cli ping | grep -q "PONG"; then
    echo "✅ Redis ping test passed"
  else
    echo "❌ Redis ping test failed"
    kill $PF_PID
    exit 1
  fi
  
  # Test setting and getting a value
  TEST_VALUE="test-$(date +%s)"
  if redis-cli set test_key "$TEST_VALUE" | grep -q "OK" && \
     [ "$(redis-cli get test_key)" = "$TEST_VALUE" ]; then
    echo "✅ Redis set/get test passed"
  else
    echo "❌ Redis set/get test failed"
    kill $PF_PID
    exit 1
  fi
  
  # Check Redis info
  if redis-cli info | grep -q "redis_version"; then
    echo "✅ Redis info test passed"
    REDIS_VERSION=$(redis-cli info | grep redis_version | cut -d: -f2 | tr -d '\r')
    echo "Redis version: $REDIS_VERSION"
  else
    echo "❌ Redis info test failed"
    kill $PF_PID
    exit 1
  fi
else
  echo "redis-cli not available, using alternative connection test..."
  
  # Alternative test using netcat
  if command -v nc &>/dev/null; then
    if nc -z localhost 6379; then
      echo "✅ Redis port is open and accepting connections"
    else
      echo "❌ Redis port is not accessible"
      kill $PF_PID
      exit 1
    fi
  else
    echo "⚠️ Neither redis-cli nor nc available, cannot perform comprehensive tests"
  fi
fi

# Clean up port forwarding
kill $PF_PID

echo "✨ Redis tests completed successfully!"