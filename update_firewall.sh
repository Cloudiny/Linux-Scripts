#!/bin/bash

# Run the firewall update script every 5 minutes as root
#*/5 * * * * /root/update_firewall.sh

# Define your unified dynamic DNS domain
DDNS_DOMAIN=""

# Resolve the current IP for Home/Veeam/PMG
TRUSTED_IP=$(getent ahosts $DDNS_DOMAIN | awk '{ print $1 }' | head -n 1)

# Validate that we received a valid IPv4 address
if [[ ! $TRUSTED_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    exit 1
fi

# Ensure the Mexico ipset exists to prevent iptables syntax errors
ipset list mx_ips >/dev/null 2>&1 || ipset create mx_ips hash:net

# ==========================================
# 1. DOCKER CONTAINERS PROTECTION
# ==========================================
iptables -F DOCKER-USER
iptables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow trusted IP to Portainer agent (PORTAINER_PORT) and drop the rest
iptables -A DOCKER-USER -p tcp ! -s "$TRUSTED_IP" -m conntrack --ctorigdstport PORTAINER_PORT -j DROP

# GEOLOCK EXAMPLE: Allow only Mexico to access specific Docker application ports
# Replace APP_PORT_1 APP_PORT_2 with actual container ports (e.g., 8080 9090)
for PORT in APP_PORT_1 APP_PORT_2; do
    iptables -A DOCKER-USER -p tcp -m set ! --match-set mx_ips src -m conntrack --ctorigdstport $PORT -j DROP
done

# Return unmatched traffic to continue normal Docker processing
iptables -A DOCKER-USER -j RETURN

# ==========================================
# 2. HOST PROCESSES PROTECTION (VEEAM & TAILSCALE)
# ==========================================
iptables -N HOST-CUSTOM 2>/dev/null
iptables -C INPUT -j HOST-CUSTOM 2>/dev/null || iptables -I INPUT 1 -j HOST-CUSTOM
iptables -F HOST-CUSTOM

iptables -A HOST-CUSTOM -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow trusted IP to Veeam services (6160, 6162)
for PORT in 6160 6162; do
    iptables -A HOST-CUSTOM -p tcp -s "$TRUSTED_IP" --dport $PORT -j ACCEPT
    iptables -A HOST-CUSTOM -p tcp --dport $PORT -j DROP
done

# Allow trusted IP to Tailscale peer-to-peer port (41641 UDP)
iptables -A HOST-CUSTOM -p udp -s "$TRUSTED_IP" --dport 41641 -j ACCEPT
iptables -A HOST-CUSTOM -p udp --dport 41641 -j DROP

# Return unmatched traffic (Ports for SMTP and SSH will naturally fall through here and stay open)
iptables -A HOST-CUSTOM -j RETURN
