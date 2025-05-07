#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Running extended tests for demo-app-svc..."

# Set up port forwarding
PORT=8081
kubectl port-forward service/demo-app-svc 8081:80 -n local-apps &
PF_PID=$!

# Give port forwarding time to establish
sleep 2

# Run a series of tests
echo "Testing HTTP response code..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT)
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "✅ HTTP response code test passed: $HTTP_CODE"
else
  echo "❌ HTTP response code test failed: $HTTP_CODE"
  exit 1
fi

echo "Testing response content..."
CONTENT=$(curl -s http://localhost:$PORT | grep -c "nginx" || true)
if [[ "$CONTENT" -gt 0 ]]; then
  echo "✅ Content test passed: Found nginx welcome page"
else
  echo "❌ Content test failed: Couldn't find expected content"
  exit 1
fi

# Test response time
echo "Testing response time..."
RESPONSE_TIME=$(curl -s -w "%{time_total}\n" -o /dev/null http://localhost:$PORT)
if (( $(echo "$RESPONSE_TIME < 2.0" | bc -l) )); then
  echo "✅ Response time test passed: $RESPONSE_TIME seconds"
else
  echo "❌ Response time test failed: $RESPONSE_TIME seconds"
  exit 1
fi

# Clean up port forwarding
kill $PF_PID

echo "✨ All tests passed successfully!"