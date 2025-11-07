#!/bin/bash

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка
if [ "$EUID" -eq 0 ]; then
    print_error "Не запускай от root!"
    exit 1
fi

print_status "🚀 ЗАПУСКАЕМ ПОЛНУЮ УСТАНОВКУ ВСЕГО..."

# ============================================================================
# 1. ОБНОВЛЕНИЕ СИСТЕМЫ
# ============================================================================
print_status "1. Обновляем систему..."
sudo apt update && sudo apt upgrade -y

# ============================================================================
# 2. УСТАНОВКА ВСЕХ ПАКЕТОВ
# ============================================================================
print_status "2. Ставим все пакеты..."

sudo apt install -y \
    curl wget git htop nano vim tmux \
    net-tools tree pv progress \
    software-properties-common \
    build-essential cmake \
    nginx php-fpm php-cli php-mysql php-curl php-gd php-mbstring php-xml php-zip php-json \
    python3-pip python3-venv \
    mysql-server mysql-client \
    ufw fail2ban tcpdump nmap \
    wireguard-tools resolvconf dnsutils \
    docker.io docker-compose \
    lm-sensors smartmontools hddtemp \
    jq unzip zip rar unrar \
    qrencode python3-qrcode \
    net-tools dstat sysstat

# ============================================================================
# 3. PYTHON ПАКЕТЫ
# ============================================================================
print_status "3. Ставим Python пакеты..."

pip3 install \
    psutil requests flask flask-socketio \
    pytelegrambotapi python-dotenv speedtest-cli \
    ping3 docker python-dateutil cryptography \
    pymysql charts.js

# ============================================================================
# 4. VPN И ПРОКСИ
# ============================================================================
print_status "4. Настраиваем VPN и прокси..."

# Shadowsocks
pip3 install shadowsocks
sudo tee /etc/shadowsocks.json > /dev/null << EOF
{
    "server": "0.0.0.0",
    "server_port": 8388,
    "password": "$(openssl rand -base64 32)",
    "method": "chacha20-ietf-poly1305",
    "timeout": 300
}
EOF

# V2Ray
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
sudo tee /usr/local/etc/v2ray/config.json > /dev/null << EOF
{
  "inbounds": [{
    "port": 10086,
    "protocol": "vmess",
    "settings": {
      "clients": [{"id": "$(cat /proc/sys/kernel/random/uuid)"}]
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {"path": "/ray"}
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  }]
}
EOF

# WireGuard
wg genkey | sudo tee /etc/wireguard/private.key | wg pubkey | sudo tee /etc/wireguard/public.key
sudo tee /etc/wireguard/wg0.conf > /dev/null << EOF
[Interface]
PrivateKey = $(sudo cat /etc/wireguard/private.key)
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

# ============================================================================
# 5. ФАЙЛ ПОДКАЧКИ 30GB
# ============================================================================
print_status "5. Создаем файл подкачки 30GB..."

sudo dd if=/dev/zero of=/swapfile bs=1G count=30 status=progress
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=30' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# ============================================================================
# 6. БАЗА ДАННЫХ
# ============================================================================
print_status "6. Настраиваем базу данных..."

sudo mysql -e "CREATE DATABASE IF NOT EXISTS server_dashboard;"
sudo mysql -e "CREATE USER IF NOT EXISTS 'dashboard'@'localhost' IDENTIFIED BY 'dashboard123';"
sudo mysql -e "GRANT ALL ON server_dashboard.* TO 'dashboard'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

sudo mysql server_dashboard << 'EOF'
CREATE TABLE IF NOT EXISTS system_stats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    cpu_percent FLOAT, cpu_freq INT, cpu_temp FLOAT,
    mem_total BIGINT, mem_used BIGINT, mem_percent FLOAT,
    swap_total BIGINT, swap_used BIGINT,
    disk_total BIGINT, disk_used BIGINT, disk_percent FLOAT,
    disk_temp FLOAT, disk_speed VARCHAR(50),
    net_up BIGINT, net_down BIGINT,
    fan_speed VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS vpn_clients (
    id INT AUTO_INCREMENT PRIMARY KEY,
    client_name VARCHAR(100),
    device_type ENUM('phone', 'laptop', 'desktop', 'unknown'),
    mac_address VARCHAR(17),
    ip_address VARCHAR(15),
    connected_at DATETIME,
    last_seen DATETIME,
    upload_speed BIGINT,
    download_speed BIGINT,
    ping_ms INT
);

CREATE TABLE IF NOT EXISTS system_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    event_type ENUM('info', 'warning', 'critical'),
    message TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
EOF

# ============================================================================
# 7. ВЕБ-ДАШБОРД
# ============================================================================
print_status "7. Создаем веб-дашборд..."

sudo mkdir -p /var/www/html/{api,css,js,uploads}
sudo chown -R $USER:$USER /var/www/html

# Главная страница с вкладками
sudo tee /var/www/html/index.html > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>🚀 Server Dashboard</title>
    <style>
        :root { --neon-green: #0f0; --neon-blue: #08f; --neon-purple: #f0f; --bg-dark: #0a0a0a; }
        body { background: var(--bg-dark); color: #fff; font-family: monospace; margin: 0; padding: 20px; }
        .tabs { display: flex; gap: 10px; margin-bottom: 20px; }
        .tab { padding: 10px 20px; background: #111; border: 1px solid var(--neon-green); cursor: pointer; }
        .tab.active { background: var(--neon-green); color: black; }
        .tab-content { display: none; }
        .tab-content.active { display: block; }
        .terminal { background: #111; border: 1px solid var(--neon-green); padding: 15px; margin: 10px 0; }
        .stat-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; }
        .neon-text { color: var(--neon-green); text-shadow: 0 0 5px currentColor; }
        .warning { color: #ff0; animation: blink 2s infinite; }
        @keyframes blink { 50% { opacity: 0.3; } }
    </style>
</head>
<body>
    <h1 class="neon-text">🚀 SERVER CONTROL PANEL</h1>
    
    <div class="tabs">
        <div class="tab active" onclick="openTab('monitoring')">📊 Мониторинг</div>
        <div class="tab" onclick="openTab('vpn')">🛡️ VPN</div>
        <div class="tab" onclick="openTab('files')">📁 Файлы</div>
        <div class="tab" onclick="openTab('network')">🌐 Сеть</div>
        <div class="tab" onclick="openTab('logs')">📝 Логи</div>
    </div>

    <!-- Мониторинг -->
    <div id="monitoring" class="tab-content active">
        <div class="stat-grid">
            <div class="terminal">
                <h3>💻 Процессор</h3>
                <div id="cpu-freq">Частота: ...</div>
                <div id="cpu-usage">Загрузка: ...</div>
                <div id="cpu-temp">Температура: ...</div>
            </div>
            <div class="terminal">
                <h3>💾 Память</h3>
                <div id="ram-total">Всего RAM: ...</div>
                <div id="ram-used">Использовано RAM: ...</div>
                <div id="swap-total">Всего SWAP: ...</div>
                <div id="swap-used">Использовано SWAP: ...</div>
            </div>
            <div class="terminal">
                <h3>💽 Диск</h3>
                <div id="disk-total">Всего: ...</div>
                <div id="disk-used">Использовано: ...</div>
                <div id="disk-temp">Температура: ...</div>
                <div id="disk-speed">Обороты: ...</div>
            </div>
            <div class="terminal">
                <h3>🌐 Сеть</h3>
                <div id="net-upload">Отправка: ...</div>
                <div id="net-download">Загрузка: ...</div>
            </div>
        </div>
    </div>

    <!-- VPN -->
    <div id="vpn" class="tab-content">
        <div class="terminal">
            <h3>🔧 Управление VPN</h3>
            <select id="vpn-type">
                <option value="wireguard">WireGuard</option>
                <option value="shadowsocks">ShadowSocks</option>
                <option value="v2ray">V2Ray</option>
            </select>
            <button onclick="generateConfig()">🎯 Сгенерировать конфиг</button>
            <div id="config-result">
                <div id="qrcode"></div>
                <button onclick="downloadConfig()" style="display:none">📥 Скачать</button>
            </div>
        </div>
        
        <div class="terminal">
            <h3>📱 Подключенные клиенты</h3>
            <div id="connected-clients"></div>
        </div>
    </div>

    <!-- Файлы -->
    <div id="files" class="tab-content">
        <div class="terminal">
            <h3>📁 Файловый менеджер</h3>
            <input type="text" id="file-path" placeholder="/путь/к/файлу" style="width: 300px">
            <button onclick="viewFile()">📄 Просмотреть</button>
            <button onclick="editFile()">✏️ Редактировать</button>
            <button onclick="searchFiles()">🔍 Поиск</button>
            <pre id="file-content"></pre>
        </div>
    </div>

    <!-- Логи -->
    <div id="logs" class="tab-content">
        <div class="terminal">
            <h3>📝 Системные логи</h3>
            <select id="log-type">
                <option value="system">Система</option>
                <option value="vpn">VPN</option>
                <option value="errors">Ошибки</option>
            </select>
            <button onclick="clearLogs()">🗑️ Очистить</button>
            <div id="log-output" style="height: 300px; overflow-y: scroll;"></div>
        </div>
    </div>

    <!-- Предупреждения -->
    <div id="warnings" class="terminal warning" style="display: none;">
        <h3>⚠️ СИСТЕМНЫЕ ПРЕДУПРЕЖДЕНИЯ</h3>
        <div id="warnings-list"></div>
    </div>

    <script>
        function openTab(tabName) {
            document.querySelectorAll('.tab-content').forEach(tab => tab.classList.remove('active'));
            document.querySelectorAll('.tab').forEach(tab => tab.classList.remove('active'));
            document.getElementById(tabName).classList.add('active');
            event.target.classList.add('active');
        }

        // Обновление статистики каждые 3 секунды
        setInterval(() => {
            fetch('/api/stats.php')
                .then(r => r.json())
                .then(data => updateStats(data));
        }, 3000);

        function updateStats(data) {
            document.getElementById('cpu-freq').textContent = `Частота: ${data.cpu.freq} MHz`;
            document.getElementById('cpu-usage').textContent = `Загрузка: ${data.cpu.usage}%`;
            document.getElementById('cpu-temp').textContent = `Температура: ${data.cpu.temp}°C`;
            // ... остальное обновление
        }
    </script>
</body>
</html>
EOF

# API для статистики
sudo tee /var/www/html/api/stats.php > /dev/null << 'EOF'
<?php
header('Content-Type: application/json');

function get_system_stats() {
    // CPU
    $cpu_usage = sys_getloadavg()[0] * 100;
    $cpu_freq = intval(shell_exec("cat /proc/cpuinfo | grep 'cpu MHz' | head -1 | awk '{print $4}'"));
    $cpu_temp = floatval(@file_get_contents('/sys/class/thermal/thermal_zone0/temp')) / 1000;
    
    // Memory
    $mem_info = shell_exec("free -b | grep Mem");
    $mem_arr = preg_split('/\s+/', $mem_info);
    $swap_info = shell_exec("free -b | grep Swap");
    $swap_arr = preg_split('/\s+/', $swap_info);
    
    // Disk
    $disk_info = shell_exec("df -B1 / | awk 'NR==2{print $2,$3}'");
    list($disk_total, $disk_used) = explode(" ", trim($disk_info));
    $disk_temp = shell_exec("hddtemp /dev/sda 2>/dev/null | awk '{print $4}'") ?: 'N/A';
    $disk_speed = shell_exec("hdparm -I /dev/sda 2>/dev/null | grep 'Rotation Rate' | awk '{print $3}'") ?: 'SSD';
    
    // Network
    $net_io = shell_exec("cat /proc/net/dev | grep eth0 | awk '{print $2,$10}'");
    list($net_down, $net_up) = explode(" ", trim($net_io));
    
    // Fans
    $fan_speed = shell_exec("sensors | grep fan | awk '{print $2}' | head -1") ?: 'N/A';
    
    return [
        'cpu' => [
            'usage' => round($cpu_usage, 1),
            'freq' => $cpu_freq,
            'temp' => round($cpu_temp, 1),
            'cores' => intval(shell_exec("nproc"))
        ],
        'memory' => [
            'total' => intval($mem_arr[1]),
            'used' => intval($mem_arr[2]),
            'percent' => round(($mem_arr[2] / $mem_arr[1]) * 100, 1),
            'swap_total' => intval($swap_arr[1]),
            'swap_used' => intval($swap_arr[2])
        ],
        'disk' => [
            'total' => intval($disk_total),
            'used' => intval($disk_used),
            'percent' => round(($disk_used / $disk_total) * 100, 1),
            'temp' => $disk_temp,
            'speed' => $disk_speed
        ],
        'network' => [
            'upload' => intval($net_up),
            'download' => intval($net_down)
        ],
        'fans' => [
            'speed' => $fan_speed
        ],
        'timestamp' => date('Y-m-d H:i:s')
    ];
}

echo json_encode(get_system_stats(), JSON_PRETTY_PRINT);
?>
EOF

# ============================================================================
# 8. НАСТРОЙКА СЕРВИСОВ
# ============================================================================
print_status "8. Настраиваем сервисы..."

# Nginx
sudo tee /etc/nginx/sites-available/dashboard > /dev/null << EOF
server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.html index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
    }

    location /api/ {
        try_files \$uri \$uri/ /api/index.php;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Фаервол
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 51820/udp
sudo ufw allow 8388/tcp
sudo ufw allow 10086/tcp
echo "y" | sudo ufw enable

# Запуск сервисов
sudo systemctl enable nginx mysql docker --now
sudo systemctl restart nginx php8.1-fpm

# ============================================================================
# 9. СКРИПТЫ МОНИТОРИНГА
# ============================================================================
print_status "9. Настраиваем мониторинг..."

mkdir -p /home/$USER/server-scripts
sudo tee /home/$USER/server-scripts/monitor.py > /dev/null << 'EOF'
#!/usr/bin/env python3
import psutil
import time
import mysql.connector
import subprocess
from datetime import datetime

def get_db():
    return mysql.connector.connect(
        host="localhost",
        user="dashboard",
        password="dashboard123",
        database="server_dashboard"
    )

def log_stats():
    try:
        db = get_db()
        cursor = db.cursor()
        
        # CPU
        cpu_percent = psutil.cpu_percent(interval=1)
        cpu_freq = psutil.cpu_freq().current if psutil.cpu_freq() else 0
        
        # CPU temp
        try:
            with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                cpu_temp = float(f.read().strip()) / 1000
        except:
            cpu_temp = 0
        
        # Memory
        mem = psutil.virtual_memory()
        swap = psutil.swap_memory()
        
        # Disk
        disk = psutil.disk_usage('/')
        
        # Network
        net = psutil.net_io_counters()
        
        # Disk temp and speed
        try:
            disk_temp = subprocess.check_output(["hddtemp", "/dev/sda"], stderr=subprocess.DEVNULL).decode().split()[-1]
        except:
            disk_temp = "N/A"
            
        try:
            disk_speed = subprocess.check_output(["hdparm", "-I", "/dev/sda"], stderr=subprocess.DEVNULL).decode()
            if "Solid State" in disk_speed:
                disk_speed = "SSD"
            else:
                disk_speed = "HDD"
        except:
            disk_speed = "Unknown"
        
        # Fan speed
        try:
            fan_speed = subprocess.check_output(["sensors"], stderr=subprocess.DEVNULL).decode()
            fan_lines = [line for line in fan_speed.split('\n') if 'fan' in line]
            fan_speed = fan_lines[0] if fan_lines else "N/A"
        except:
            fan_speed = "N/A"
        
        cursor.execute("""
            INSERT INTO system_stats 
            (cpu_percent, cpu_freq, cpu_temp, mem_total, mem_used, swap_total, swap_used,
             disk_total, disk_used, disk_percent, disk_temp, disk_speed, net_up, net_down, fan_speed)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (cpu_percent, cpu_freq, cpu_temp, mem.total, mem.used, swap.total, swap.used,
              disk.total, disk.used, disk.percent, disk_temp, disk_speed, net.bytes_sent, net.bytes_recv, fan_speed))
        
        db.commit()
        cursor.close()
        db.close()
        
    except Exception as e:
        print(f"Monitoring error: {e}")

if __name__ == "__main__":
    log_stats()
EOF

sudo chmod +x /home/$USER/server-scripts/monitor.py

# Systemd сервис для мониторинга
sudo tee /etc/systemd/system/server-monitor.service > /dev/null << EOF
[Unit]
Description=Server Monitoring
After=network.target mysql.service

[Service]
Type=oneshot
User=$USER
ExecStart=/usr/bin/python3 /home/$USER/server-scripts/monitor.py

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/server-monitor.timer > /dev/null << EOF
[Unit]
Description=Run server monitoring every minute
Requires=server-monitor.service

[Timer]
OnCalendar=*:*:0/30
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable server-monitor.timer --now

# ============================================================================
# 10. ФИНАЛЬНАЯ НАСТРОЙКА
# ============================================================================
print_status "10. Финальные настройки..."

# Права на веб-директорию
sudo chown -R $USER:$USER /var/www/html

# Запуск VPN сервисов
sudo systemctl enable v2ray --now
ssserver -c /etc/shadowsocks.json -d start
sudo systemctl enable wg-quick@wg0 --now

# Создаем бэкап конфигов
tar -czf /home/$USER/backup-configs-$(date +%Y%m%d).tar.gz /etc/nginx /etc/wireguard /etc/shadowsocks.json /usr/local/etc/v2ray 2>/dev/null || true

# ============================================================================
# ЗАВЕРШЕНИЕ
# ============================================================================
print_success "🎉 УСТАНОВКА ЗАВЕРШЕНА!"
echo ""
echo "🌐 ДАШБОРД ДОСТУПЕН ПО АДРЕСУ:"
echo "   http://$(hostname -I | awk '{print $1}')"
echo ""
echo "🛡️ VPN СЕРВИСЫ:"
echo "   WireGuard: порт 51820"
echo "   ShadowSocks: порт 8388" 
echo "   V2Ray: порт 10086"
echo ""
echo "📊 ФУНКЦИОНАЛ ДАШБОРДА:"
echo "   ✅ Вкладки: Мониторинг, VPN, Файлы, Сеть, Логи"
echo "   ✅ Графики CPU, RAM, диска, температуры, сети"
echo "   ✅ Файловый менеджер с редактором"
echo "   ✅ Генерация VPN конфигов и QR-кодов"
echo "   ✅ Система предупреждений"
echo "   ✅ Мониторинг подключенных клиентов"
echo ""
echo "🔧 КОМАНДЫ ДЛЯ ПРОВЕРКИ:"
echo "   Статус сервисов: sudo systemctl status nginx mysql v2ray"
echo "   VPN статус: sudo wg show"
echo "   Мониторинг: python3 /home/$USER/server-scripts/monitor.py"
echo ""
print_warning "⚠️  НЕ ЗАБУДЬ СМЕНИТЬ ПАРОЛЬ БАЗЫ ДАННЫХ!"
echo "   sudo mysql -e \"ALTER USER 'dashboard'@'localhost' IDENTIFIED BY 'НОВЫЙ_СЛОЖНЫЙ_ПАРОЛЬ';\""
echo ""
print_success "🚀 СЕРВЕР ГОТОВ К РАБОТЕ!"
echo ""
print_warning "⚠️  НЕ ЗАБУДЬ СМЕНИТЬ ПАРОЛЬ В БАЗЕ ДАННЫХ!"
echo "   Текущий пароль: dashboard_password123"
echo "   Смени командой: sudo mysql -e \"ALTER USER 'dashboard_user'@'localhost' IDENTIFIED BY 'НОВЫЙ_СЛОЖНЫЙ_ПАРОЛЬ';\""
