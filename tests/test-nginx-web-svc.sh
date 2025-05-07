#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Running tests for Nginx web service..."

# Set up port forwarding to Nginx
kubectl port-forward service/nginx-web-svc 8080:80 -n local-apps &
PF_PID=$!

# Give port forwarding time to establish
sleep 2

# Check if curl is available
if command -v curl &>/dev/null; then
  echo "Testing Nginx connection with curl..."
  
  # Test HTTP response code
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080)
  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "✅ HTTP response code test passed: $HTTP_CODE"
  else
    echo "❌ HTTP response code test failed: $HTTP_CODE"
    kill $PF_PID
    exit 1
  fi
  
  # Test HTML content
  if curl -s http://localhost:8080 | grep -q "Welcome to Kubernetes Demo"; then
    echo "✅ HTML content test passed"
  else
    echo "❌ HTML content test failed"
    kill $PF_PID
    exit 1
  fi
  
  # Test status endpoint
  STATUS_RESPONSE=$(curl -s http://localhost:8080/status)
  if echo "$STATUS_RESPONSE" | grep -q "postgres-svc:5432" && \
     echo "$STATUS_RESPONSE" | grep -q "redis-svc:6379"; then
    echo "✅ Status endpoint test passed"
    echo "Status response: $STATUS_RESPONSE"
  else
    echo "❌ Status endpoint test failed"
    echo "Status response: $STATUS_RESPONSE"
    kill $PF_PID
    exit 1
  fi
  
  # Test health endpoint
  HEALTH_RESPONSE=$(curl -s http://localhost:8080/health)
  if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
    echo "✅ Health endpoint test passed"
  else
    echo "❌ Health endpoint test failed"
    kill $PF_PID
    exit 1
  fi
  
  # Test response time
  RESPONSE_TIME=$(curl -s -w "%{time_total}\n" -o /dev/null http://localhost:8080)
  if (( $(echo "$RESPONSE_TIME < 1.0" | bc -l) )); then
    echo "✅ Response time test passed: $RESPONSE_TIME seconds"
  else
    echo "⚠️ Response time test warning: $RESPONSE_TIME seconds (>1s)"
  fi
else
  echo "curl not available, using alternative connection test..."
  
  # Alternative test using wget
  if command -v wget &>/dev/null; then
    if wget -q --spider http://localhost:8080; then
      echo "✅ Nginx web service is accessible via wget"
    else
      echo "❌ Nginx web service is not accessible via wget"
      kill $PF_PID
      exit 1
    fi
  else
    echo "⚠️ Neither curl nor wget available, cannot perform comprehensive tests"
  fi
fi

# Clean up port forwarding
kill $PF_PID

echo "✨ Nginx web service tests completed successfully!"