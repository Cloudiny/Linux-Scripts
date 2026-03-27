#!/bin/bash

# Run the GeoIP update script once a week (Sunday at 3:00 AM)
#0 3 * * 0 /root/update_mx_ips.sh

# Define the source URL for the Mexican IP blocks (CIDR format)
ZONE_URL="http://www.ipdeny.com/ipblocks/data/countries/mx.zone"
TMP_FILE="/tmp/mx-zone.txt"

# Download the latest zone file silently
wget -qO "$TMP_FILE" "$ZONE_URL"

# Verify if the download was successful and the file is not empty
if [ ! -s "$TMP_FILE" ]; then
    exit 1
fi

# Ensure the primary ipset exists, create it if it doesn't
ipset list mx_ips >/dev/null 2>&1 || ipset create mx_ips hash:net

# Create a temporary ipset for loading the new rules
ipset create mx_ips_temp hash:net

# Populate the temporary ipset with the downloaded CIDR blocks
while read -r CIDR; do
    ipset add mx_ips_temp "$CIDR"
done < "$TMP_FILE"

# Atomically swap the temporary set with the active set to prevent downtime
ipset swap mx_ips_temp mx_ips

# Destroy the temporary set as it is no longer needed (it now holds the old data)
ipset destroy mx_ips_temp

# Clean up the temporary file
rm -f "$TMP_FILE"
