#!/bin/sh
set -e

INTERFACE="awg10"

echo "[1/5] Update packages"
opkg update

echo "[2/5] Install required packages"
opkg install curl jq || true

echo "[3/5] Install AmneziaWG"
opkg install kmod-amneziawg amneziawg-tools || {
    echo "❌ Failed to install amneziawg packages"
    exit 1
}

echo "[4/5] Generate WARP config"

CONFIG_RAW=""
CONFIG=""

SOURCES="
https://warp-gen.vercel.app/generate-config
https://warp-gen2.vercel.app/generate-config
https://amnezia-warp.vercel.app/api/config
https://warp-generator.pages.dev/api/config
"

for URL in $SOURCES; do
    echo "Trying $URL"
    CONFIG_RAW=$(curl -fsL --max-time 60 "$URL" 2>/dev/null || true)
    [ -n "$CONFIG_RAW" ] && break
done

[ -z "$CONFIG_RAW" ] && {
    echo "❌ Failed to generate config"
    exit 1
}

# JSON → config
if echo "$CONFIG_RAW" | grep -q '"config"'; then
    CONFIG=$(echo "$CONFIG_RAW" | jq -r '.config')
else
    CONFIG="$CONFIG_RAW"
fi

echo "✔ Config received"

getval() {
    echo "$CONFIG" | sed -n "s/^$1 *= *//p" | head -n1
}

PrivateKey=$(getval "PrivateKey")
PublicKey=$(getval "PublicKey")
Address=$(getval "Address" | cut -d',' -f1)
Endpoint=$(getval "Endpoint")

EndpointIP=${Endpoint%:*}
EndpointPort=${Endpoint##*:}

[ -z "$PrivateKey" ] || [ -z "$PublicKey" ] && {
    echo "❌ Invalid config"
    exit 1
}

echo "[5/5] Configure interface $INTERFACE"

# --- UCI ---
uci batch <<EOF
delete network.$INTERFACE

set network.$INTERFACE=interface
set network.$INTERFACE.proto='amneziawg'
set network.$INTERFACE.private_key='$PrivateKey'
add_list network.$INTERFACE.addresses='$Address'
set network.$INTERFACE.mtu='1280'

# peer
add network amneziawg
set network.@amneziawg[-1].interface='$INTERFACE'
set network.@amneziawg[-1].public_key='$PublicKey'
set network.@amneziawg[-1].endpoint_host='$EndpointIP'
set network.@amneziawg[-1].endpoint_port='$EndpointPort'
set network.@amneziawg[-1].allowed_ips='0.0.0.0/0'
set network.@amneziawg[-1].persistent_keepalive='25'
set network.@amneziawg[-1].route_allowed_ips='0'
EOF

uci commit network

echo "Reload network"
ifdown "$INTERFACE" 2>/dev/null || true
/etc/init.d/network reload
sleep 3
ifup "$INTERFACE"

echo "✅ awg10 created and started"
