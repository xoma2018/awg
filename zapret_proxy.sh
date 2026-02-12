#!/bin/sh

# Скрипт настройки zapret + Opera Proxy для обхода блокировок Discord/Roblox
# Для роутеров OpenWRT (RouteRich, Keenetic и др.)

echo "=========================================="
echo "Установка zapret + Opera Proxy"
echo "=========================================="

# Обновление списка пакетов
echo "Обновление списка пакетов..."
opkg update

# Установка необходимых пакетов
echo "Установка необходимых пакетов..."
opkg install curl jq opera-proxy zapret luci-app-zapret sing-box-tiny

# Проверка установки dnsmasq-full
if ! opkg list-installed | grep -q dnsmasq-full; then
    echo "Установка dnsmasq-full..."
    cd /tmp
    opkg download dnsmasq-full
    opkg remove dnsmasq
    opkg install dnsmasq-full --cache /tmp
fi

# Настройка sing-box для работы с Opera Proxy
echo "Настройка sing-box..."
cat > /etc/sing-box/config.json << 'EOF'
{
  "log": {
    "disabled": true,
    "level": "error"
  },
  "inbounds": [
    {
      "type": "tproxy",
      "listen": "::",
      "listen_port": 1100,
      "sniff": false
    }
  ],
  "outbounds": [
    {
      "type": "http",
      "server": "127.0.0.1",
      "server_port": 18080
    }
  ],
  "route": {
    "auto_detect_interface": true
  }
}
EOF

uci set sing-box.main.enabled='1'
uci set sing-box.main.user='root'
uci add_list sing-box.main.ifaces='wan'
uci add_list sing-box.main.ifaces='wan2'
uci add_list sing-box.main.ifaces='wan6'
uci add_list sing-box.main.ifaces='wwan'
uci add_list sing-box.main.ifaces='wwan0'
uci add_list sing-box.main.ifaces='modem'
uci commit sing-box

# Настройка firewall - блокировка QUIC (UDP 80/443)
echo "Настройка firewall - блокировка QUIC..."
if ! uci show firewall | grep -q "BlockUDP443"; then
    uci add firewall rule
    uci set firewall.@rule[-1].name='BlockUDP80'
    uci add_list firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].dest='wan'
    uci set firewall.@rule[-1].dest_port='80'
    uci set firewall.@rule[-1].target='REJECT'
    
    uci add firewall rule
    uci set firewall.@rule[-1].name='BlockUDP443'
    uci add_list firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].dest='wan'
    uci set firewall.@rule[-1].dest_port='443'
    uci set firewall.@rule[-1].target='REJECT'
    
    uci commit firewall
fi

# Настройка zapret для Discord/Roblox
echo "Настройка zapret..."

# Создание списка доменов для zapret
cat > /opt/zapret/ipset/zapret-hosts-user.txt << 'EOF'
discord.com
discordapp.com
discord.gg
discord.media
discord.co
roblox.com
rbxcdn.com
robloxlabs.com
EOF

# Создание скрипта для Discord Media
cat > /opt/zapret/init.d/openwrt/custom.d/50-discord-media << 'EOF'
#!/bin/sh

# Специальная обработка Discord Media для голосовой связи
zapret_custom_daemons()
{
    local MODE="--hostlist=/opt/zapret/ipset/zapret-hosts-user.txt"
    
    # UDP для Discord Voice/Video
    do_nfqws 100 1 "$MODE" \
        --filter-udp=50000-65535 \
        --hostlist=/opt/zapret/ipset/zapret-hosts-user.txt \
        --dpi-desync=fake \
        --dpi-desync-any-protocol \
        --dpi-desync-cutoff=d3 \
        --dpi-desync-repeats=6
    
    # TCP для Discord (дополнительно)
    do_nfqws 100 2 "$MODE" \
        --filter-tcp=443 \
        --hostlist=/opt/zapret/ipset/zapret-hosts-user.txt \
        --dpi-desync=split2 \
        --dpi-desync-split-pos=1 \
        --dpi-desync-fooling=badsum
}

zapret_custom_firewall()
{
    # Перехват UDP трафика Discord Media
    fw_nfqws_post 100 1 "$1" "--protocol udp --dport 50000:65535"
    
    # Перехват TCP трафика Discord
    fw_nfqws_post 100 2 "$1" "--protocol tcp --dport 443"
}
EOF

chmod +x /opt/zapret/init.d/openwrt/custom.d/50-discord-media

# Синхронизация конфигурации zapret
sh /opt/zapret/sync_config.sh

# Настройка DNS
echo "Настройка DNS..."
uci set dhcp.@dnsmasq[0].strictorder='1'
uci set dhcp.@dnsmasq[0].filteraaaa='1'
uci commit dhcp

# Запуск сервисов
echo "Запуск сервисов..."
service opera-proxy enable
service opera-proxy start

service sing-box enable
service sing-box restart

service zapret enable
service zapret restart

service firewall restart
service dnsmasq restart

# Проверка работоспособности
echo ""
echo "=========================================="
echo "Проверка работоспособности..."
echo "=========================================="

sleep 5

# Проверка Opera Proxy
echo "Проверка Opera Proxy..."
if curl --proxy http://127.0.0.1:18080 --connect-timeout 10 -s ipinfo.io/ip > /dev/null; then
    echo "✓ Opera Proxy работает"
else
    echo "✗ Opera Proxy не работает"
fi

# Проверка zapret
echo "Проверка zapret..."
if curl -f -o /dev/null -k --connect-to google.com -L \
    -H "Host: mirror.gcr.io" --max-time 30 \
    https://test.googlevideo.com 2>/dev/null; then
    echo "✓ zapret работает"
else
    echo "✗ zapret не работает"
fi

echo ""
echo "=========================================="
echo "Настройка завершена!"
echo "=========================================="
echo ""
echo "Рекомендуется перезагрузить роутер:"
echo "  reboot"
echo ""
echo "После перезагрузки Discord и Roblox должны работать."
echo ""
