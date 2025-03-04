#!/bin/bash

# Define color codes
NC='\033[0m'           # Text Reset
BGreen='\033[1;32m'    # Bright Green
BYellow='\033[1;33m'   # Bright Yellow

# Retrieve the Gateway IP
export GATEWAY=$(oc get gateway hello-gateway -n istio-ingress -o template --template='{{(index .status.addresses 0).value}}' 2>/dev/null)

# Check if GATEWAY is retrieved successfully
if [ -z "$GATEWAY" ]; then
    echo -e "${BYellow}Error: Unable to retrieve Gateway IP. Please check if the gateway 'hello-gateway' exists in namespace 'istio-ingress'.${NC}"
    exit 1
fi

SLEEP=20
V1_WEIGHT=100

# Initial service check
response=$(curl -s -o /dev/null -w "%{http_code}" $GATEWAY/hello-service)
echo -e "Initial response code: ${BGreen}$response${NC}"

# Loop through different weights
for V2_WEIGHT in 10 25 50 75 100
do
    # Calculate the weight for v1
    V1_WEIGHT_NEW=$((V1_WEIGHT - V2_WEIGHT))

    # Apply the new traffic split configuration
    cat <<EOF | oc apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: service-b
  namespace: rest-api-with-mesh
spec:
  hosts:
    - service-b
  http:
  - route:
    - destination:
        host: service-b
        subset: v1
        port:
          number: 8080
      weight: ${V1_WEIGHT_NEW}
    - destination:
        host: service-b
        subset: v2
        port:
          number: 8080
      weight: ${V2_WEIGHT}
EOF

    # Print traffic routing information
    echo -e "${BGreen}${V1_WEIGHT_NEW}%${NC} traffic is routed to ${BGreen}v1${NC}, ${BYellow}${V2_WEIGHT}%${NC} to ${BYellow}v2${NC}"

    # Wait before applying the next rule
    sleep $SLEEP
done

# Final service check
response=$(curl -s -o /dev/null -w "%{http_code}" $GATEWAY/hello-service)
echo -e "Final response code: ${BGreen}$response${NC}"
