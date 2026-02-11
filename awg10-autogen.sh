#!/bin/sh
set -e

INTERFACE="awg10"

echo "[1/5] Update packages"
opkg update

echo "[2/5] Install required packages"
opkg install curl jq coreutils-base64 || true

echo "[3/5] Install AmneziaWG"
opkg install kmod-amneziawg amneziawg-tools || {
    echo "❌ Failed to install amneziawg packages"
    exit 1
}

echo "[4/5] Generate WARP config (with fallback)"

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
    echo "❌ Failed to generate WARP config from all sources"
    exit 1
}

# если JSON — извлекаем поле config
if echo "$CONFIG_RAW" | grep -q '"config"'; then
    CONFIG=$(echo "$CONFIG_RAW" | jq -r '.config')
else
    CONFIG="$CONFIG_RAW"
fi

[ -z "$CONFIG" ] && {
    echo "❌ Empty config received"
    exit 1
}

echo "✔ Config received"

# ---------- Парсинг WG / AmneziaWG конфига ----------

getval() {
    echo "$CONFIG" | sed -n "s/^$1 *= *//p" | head -n1
}

PrivateKey=$(getval "PrivateKey")
PublicKey=$(getval "PublicKey")
Address=$(getval "Address" | cut -d',' -f1)
DNS=$(getval "DNS" | cut -d',' -f1)
Endpoint=$(getval "Endpoint")

# параметры AmneziaWG (могут отсутствовать)
Jc=$(getval "Jc")
Jmin=$(getval "Jmin")
Jmax=$(getval "Jmax")
S1=$(getval "S1")
S2=$(getval "S2")
H1=$(getval "H1")
H2=$(getval "H2")
H3=$(getval "H3")
H4=$(getval "H4")

EndpointIP=${Endpoint%:*}
EndpointPort=${Endpoint##*:}

[ -z "$PrivateKey" ] || [ -z "$PublicKey" ] || [ -z "$EndpointIP" ] && {
    echo "❌ Invalid config data"
    exit 1
}

echo "[5/5] Configure interface $INTERFACE"

uci -q delete network.$INTERFACE

uci set network.$INTERFACE=interface
uci set network.$INTERFACE.proto='amneziawg'
uci set network.$INTERFACE.private_key="$PrivateKey"
uci add_list network.$INTERFACE.addresses="$Address"
uci set network.$INTERFACE.mtu='1280'

# AmneziaWG параметры (устанавливаются только если есть)
[ -n "$Jc" ]   && uci set network.$INTERFACE.awg_jc="$Jc"
[ -n "$Jmin" ] && uci set network.$INTERFACE.awg_jmin="$Jmin"
[ -n "$Jmax" ] && uci set network.$INTERFACE.awg_jmax="$Jmax"
[ -n "$S1" ]   && uci set network.$INTERFACE.awg_s1="$S1"
[ -n "$S2" ]   && uci set network.$INTERFACE.awg_s2="$S2"
[ -n "$H1" ]   && uci set network.$INTERFACE.awg_h1="$H1"
[ -n "$H2" ]   && uci set network.$INTERFACE.awg_h2="$H2"
[ -n "$H3" ]   && uci set network.$INTERFACE.awg_h3="$H3"
[ -n "$H4" ]   && uci set network.$INTERFACE.awg_h4="$H4"

uci add network amneziawg
uci set network.@amneziawg[-1].public_key="$PublicKey"
uci set network.@amneziawg[-1].endpoint_host="$EndpointIP"
uci set network.@amneziawg[-1].endpoint_port="$EndpointPort"
uci set network.@amneziawg[-1].allowed_ips='0.0.0.0/0'
uci set network.@amneziawg[-1].persistent_keepalive='25'
uci set network.@amneziawg[-1].route_allowed_ips='0'

uci commit network

echo "Restart interface"
ifdown "$INTERFACE" 2>/dev/null || true
sleep 2
ifup "$INTERFACE"

echo "✅ $INTERFACE configured and started"
