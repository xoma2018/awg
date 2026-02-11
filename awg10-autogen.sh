#!/bin/sh

### =========================
### WARP CONFIG GENERATORS
### =========================

requestConfWARP1() {
	curl --connect-timeout 20 --max-time 60 -w "%{http_code}" \
	'https://warp.llimonix.pw/api/warp' \
	-H 'Accept: */*' \
	-H 'Content-Type: application/json' \
	--data-raw '{"selectedServices":[],"siteMode":"all","deviceType":"computer"}'
}

requestConfWARP2() {
	curl --connect-timeout 20 --max-time 60 -w "%{http_code}" \
	'https://topor-warp.vercel.app/generate' \
	-H 'Accept: */*' \
	-H 'Content-Type: application/json' \
	--data-raw '{"platform":"all"}'
}

requestConfWARP3() {
	curl --connect-timeout 20 --max-time 60 -w "%{http_code}" \
	'https://warp-gen.vercel.app/generate-config'
}

requestConfWARP4() {
	curl --connect-timeout 20 --max-time 60 -w "%{http_code}" \
	'https://config-generator-warp.vercel.app/warp'
}

### =========================
### RESPONSE HANDLER
### =========================

check_request() {
	response="$1"
	choice="$2"

	code="${response: -3}"
	body="${response%???}"

	[ "$code" != "200" ] && { echo "Error"; return; }

	case "$choice" in
	1)
		[ "$(echo "$body" | jq -r '.success')" = "true" ] || { echo "Error"; return; }
		echo "$body" | jq -r '.content.configBase64' | base64 -d
		;;
	2)
		echo "$body"
		;;
	3)
		echo "$body" | jq -r '.config'
		;;
	4)
		echo "$body" | jq -r '.content' | base64 -d
		;;
	esac
}

### =========================
### GET WARP CONFIG
### =========================

warp_config="Error"

result=$(requestConfWARP1)
warpGen=$(check_request "$result" 1)

[ "$warpGen" = "Error" ] && {
	result=$(requestConfWARP2)
	warpGen=$(check_request "$result" 2)
}

[ "$warpGen" = "Error" ] && {
	result=$(requestConfWARP3)
	warpGen=$(check_request "$result" 3)
}

[ "$warpGen" = "Error" ] && {
	result=$(requestConfWARP4)
	warpGen=$(check_request "$result" 4)
}

[ "$warpGen" = "Error" ] && {
	echo "WARP config generation failed"
	exit 1
}

warp_config="$warpGen"

### =========================
### PARSE WARP CONFIG
### =========================

while IFS=' = ' read -r line; do
	echo "$line" | grep -q "=" || continue
	key=$(echo "$line" | cut -d'=' -f1 | xargs)
	value=$(echo "$line" | cut -d'=' -f2- | xargs)
	eval "$key=\"$value\""
done < <(echo "$warp_config")

Address=$(echo "$Address" | cut -d',' -f1)
DNS=$(echo "$DNS" | cut -d',' -f1)
AllowedIPs=$(echo "$AllowedIPs" | cut -d',' -f1)
EndpointIP=$(echo "$Endpoint" | cut -d':' -f1)
EndpointPort=$(echo "$Endpoint" | cut -d':' -f2)

### =========================
### CREATE AWG INTERFACE
### =========================

INTERFACE_NAME="awg10"
CONFIG_NAME="amneziawg_awg10"
PROTO="amneziawg"
ZONE_NAME="awg"

uci set network.${INTERFACE_NAME}=interface
uci set network.${INTERFACE_NAME}.proto=$PROTO

if ! uci show network | grep -q ${CONFIG_NAME}; then
	uci add network ${CONFIG_NAME}
fi

uci set network.${INTERFACE_NAME}.private_key=$PrivateKey
uci del network.${INTERFACE_NAME}.addresses
uci add_list network.${INTERFACE_NAME}.addresses=$Address
uci set network.${INTERFACE_NAME}.mtu=$MTU

uci set network.${INTERFACE_NAME}.awg_jc=$Jc
uci set network.${INTERFACE_NAME}.awg_jmin=$Jmin
uci set network.${INTERFACE_NAME}.awg_jmax=$Jmax
uci set network.${INTERFACE_NAME}.awg_s1=$S1
uci set network.${INTERFACE_NAME}.awg_s2=$S2
uci set network.${INTERFACE_NAME}.awg_h1=$H1
uci set network.${INTERFACE_NAME}.awg_h2=$H2
uci set network.${INTERFACE_NAME}.awg_h3=$H3
uci set network.${INTERFACE_NAME}.awg_h4=$H4

uci set network.${INTERFACE_NAME}.nohostroute='1'

uci set network.@${CONFIG_NAME}[-1].description="${INTERFACE_NAME}_peer"
uci set network.@${CONFIG_NAME}[-1].public_key=$PublicKey
uci set network.@${CONFIG_NAME}[-1].endpoint_host=$EndpointIP
uci set network.@${CONFIG_NAME}[-1].endpoint_port=$EndpointPort
uci set network.@${CONFIG_NAME}[-1].persistent_keepalive='25'
uci set network.@${CONFIG_NAME}[-1].allowed_ips='0.0.0.0/0'
uci set network.@${CONFIG_NAME}[-1].route_allowed_ips='0'

uci commit network

### =========================
### FIREWALL (MINIMAL)
### =========================

if ! uci show firewall | grep -q "@zone.*name='${ZONE_NAME}'"; then
	uci add firewall zone
	uci set firewall.@zone[-1].name=$ZONE_NAME
	uci set firewall.@zone[-1].network=$INTERFACE_NAME
	uci set firewall.@zone[-1].forward='REJECT'
	uci set firewall.@zone[-1].output='ACCEPT'
	uci set firewall.@zone[-1].input='REJECT'
	uci set firewall.@zone[-1].masq='1'
	uci set firewall.@zone[-1].mtu_fix='1'
	uci set firewall.@zone[-1].family='ipv4'
	uci commit firewall
fi

if ! uci show firewall | grep -q "@forwarding.*name='${ZONE_NAME}'"; then
	uci add firewall forwarding
	uci set firewall.@forwarding[-1].name="${ZONE_NAME}"
	uci set firewall.@forwarding[-1].src='lan'
	uci set firewall.@forwarding[-1].dest=$ZONE_NAME
	uci set firewall.@forwarding[-1].family='ipv4'
	uci commit firewall
fi

### =========================
### APPLY
### =========================

service firewall restart
ifdown $INTERFACE_NAME 2>/dev/null
sleep 2
ifup $INTERFACE_NAME

echo "AWG WARP interface awg10 configured successfully"
