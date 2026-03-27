#!/bin/bash

# Run the PMG monitor script every 30 minutes to prevent latency false positives
#*/30 * * * * /root/check_pmg.sh

# Configuration variables
PD_ROUTING_KEY="AAAABBBBCCCCDDDEEEFFFF"
# IP from your Tailscale status output
PMG_IP="100.64.0.1"
STATE_FILE="/tmp/pmg_tailscale_state"
# Deduplication key to group alerts in PagerDuty
DEDUP_KEY="pmg-vpn-connection-loss"
# Retry logic variables
MAX_RETRIES=3
RETRY_WAIT=10
PING_SUCCESS=false

# Function to send PagerDuty event via Events API v2
send_pagerduty_event() {
    local event_action=$1
    local summary=$2

    # Create JSON payload for PagerDuty
    local payload=$(cat <<EOF
    {
      "routing_key": "${PD_ROUTING_KEY}",
      "event_action": "${event_action}",
      "dedup_key": "${DEDUP_KEY}",
      "payload": {
        "summary": "${summary}",
        "source": "$(hostname)",
        "severity": "critical",
        "component": "Tailscale VPN",
        "group": "Network",
        "class": "Connectivity"
      }
    }
EOF
    )

    # Send POST request to PagerDuty endpoint
    curl -s -X POST "https://events.pagerduty.com/v2/enqueue" \
        -H "Content-Type: application/json" \
        -d "$payload" > /dev/null
}

# Loop to attempt pinging multiple times before confirming failure
for ((i=1; i<=MAX_RETRIES; i++)); do
    # Perform a ping test sending 3 packets with a 3-second timeout
    if ping -c 3 -W 3 "$PMG_IP" > /dev/null 2>&1; then
        PING_SUCCESS=true
        # Exit the loop immediately if ping is successful
        break
    fi

    # If it is not the last attempt, wait before trying again
    if [ $i -lt $MAX_RETRIES ]; then
        sleep "$RETRY_WAIT"
    fi
done

# Evaluate the final result after all retries
if [ "$PING_SUCCESS" = true ]; then
    # Ping successful. Check if it was previously down by looking for the state file.
    if [ -f "$STATE_FILE" ]; then
        # The connection has been restored. Resolve the PagerDuty incident.
        send_pagerduty_event "resolve" "Connection to PMG ($PMG_IP) restored."

        # Remove the state file to reset the monitor
        rm -f "$STATE_FILE"
    fi
else
    # Ping failed after all retries. Check if we have already alerted.
    if [ ! -f "$STATE_FILE" ]; then
        # Create state file to prevent alert spamming on subsequent runs
        touch "$STATE_FILE"

        # Trigger PagerDuty critical incident
        send_pagerduty_event "trigger" "CRITICAL: Lost connection to PMG ($PMG_IP) via Tailscale after $MAX_RETRIES attempts!"
    fi
fi
