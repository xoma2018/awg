#!/bin/sh
set -e

INTERFACE="awg10"

echo "[1/5] Update packages"
opkg update

echo "[2/5] Install required packages"
opkg install curl jq coreutils-base64 || true

echo "[3/5] Install AmneziaWG"
opkg install kmod-amneziawg amneziawg-tools || {
    echo "Failed to install amneziawg packages"
    exit 1
}

echo "[4/5] Generate WARP config (with fallback)"

CONFIG=""

SOURCES="
https://warp-gen.vercel.app/generate-config
https://warp-gen2.vercel.app/generate-config
https://amnezia-warp.vercel.app/api/config
https://warp-generator.pages.dev/api/config
"

for URL in $SOURCES; do
    echo "Trying $URL"
    CONFIG=$(curl -fsL --max-time 60 "$URL" 2>/dev/null || true)
    [ -n "$CONFIG" ] && break
done

[ -z "$CONFIG" ] && {
    echo "❌ Failed to generate WARP config from all sources"
    exit 1
}

echo "✔ Config received"

# парсим KEY=VALUE формат
while IFS='=' read -r k v; do
    [ -n "$k" ] && eval "$k=\"$v\""
done <<EOF
$CONFIG
EOF

Address=$(echo "$Address" | cut -d',' -f1)
DNS=$(echo "$DNS" | cut -d',' -f1)
EndpointIP=$(echo "$Endpoint" | cut -d':' -f1)
EndpointPort=$(echo "$Endpoint" | cut -d':' -f2)

echo "[5/5] Configure interface $INTERFACE"

uci -q delete network.$INTERFACE

uci set network.$INTERFACE=interface
uci set network.$INTERFACE.proto='amneziawg'
uci set network.$INTERFACE.private_key="$PrivateKey"
uci add_list network.$INTERFACE.addresses="$Address"
uci set network.$INTERFACE.mtu='1280'

uci set network.$INTERFACE.awg_jc="$Jc"
uci set network.$INTERFACE.awg_jmin="$Jmin"
uci set network.$INTERFACE.awg_jmax="$Jmax"
uci set network.$INTERFACE.awg_s1="$S1"
uci set network.$INTERFACE.awg_s2="$S2"
uci set network.$INTERFACE.awg_h1="$H1"
uci set network.$INTERFACE.awg_h2="$H2"
uci set network.$INTERFACE.awg_h3="$H3"
uci set network.$INTERFACE.awg_h4="$H4"

uci add network amneziawg
uci set network.@amneziawg[-1].public_key="$PublicKey"
uci set network.@amneziawg[-1].endpoint_host="$EndpointIP"
uci set network.@amneziawg[-1].endpoint_port="$EndpointPort"
uci set network.@amneziawg[-1].allowed_ips='0.0.0.0/0'
uci set network.@amneziawg[-1].persistent_keepalive='25'
uci set network.@amneziawg[-1].route_allowed_ips='0'

uci commit network

echo "Restart interface"
ifdown $INTERFACE 2>/dev/null || true
sleep 2
ifup $INTERFACE

echo "✅ $INTERFACE configured and started"
