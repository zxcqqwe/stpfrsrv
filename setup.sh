#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для красивого вывода
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка на root
if [ "$EUID" -eq 0 ]; then
    print_error "Не запускай скрипт от root! Запускай от обычного пользователя."
    exit 1
fi

print_status "🚀 Начинаем полную установку и настройку сервера..."

# ============================================================================
# ШАГ 1: ОБНОВЛЕНИЕ СИСТЕМЫ
# ============================================================================
print_status "1. Обновляем систему..."
sudo apt update && sudo apt upgrade -y

# ============================================================================
# ШАГ 2: УСТАНОВКА ВСЕХ ПАКЕТОВ
# ============================================================================
print_status "2. Устанавливаем все необходимые пакеты..."

# Базовые утилиты
sudo apt install -y \
    curl wget git htop nano vim tmux \
    net-tools tree pv progress \
    software-properties-common \
    build-essential cmake \
    ca-certificates gnupg lsb-release

# Мониторинг и диагностика
sudo apt install -y \
    htop iotop iftop nethogs \
    lm-sensors psensor \
    smartmontools hddtemp \
    nmon dstat sysstat \
    ncdu dfc

# Сеть и безопасность
sudo apt install -y \
    ufw fail2ban \
    tcpdump nmap netcat \
    iptables-persistent \
    wireguard-tools resolvconf \
    dnsutils whois \
    openssh-server openssh-client

# Веб-сервер и PHP
sudo apt install -y \
    nginx php-fpm php-cli \
    php-mysql php-pgsql php-sqlite3 \
    php-curl php-gd php-mbstring \
    php-xml php-zip php-json \
    php-bcmath php-gmp

# Python
sudo apt install -y python3-pip python3-venv

# Дополнительные утилиты
sudo apt install -y \
    jq unzip zip rar unrar \
    rclone rsync \
    at cron anacron \
    logrotate

print_success "Все пакеты установлены!"

# ============================================================================
# ШАГ 3: УСТАНОВКА DOCKER
# ============================================================================
print_status "3. Устанавливаем Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Устанавливаем Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

print_success "Docker установлен!"

# ============================================================================
# ШАГ 4: УСТАНОВКА PYTHON ПАКЕТОВ
# ============================================================================
print_status "4. Устанавливаем Python пакеты..."

pip3 install \
    psutil requests flask \
    python-socketio flask-socketio \
    pytelegrambotapi python-dotenv \
    speedtest-cli ping3 \
    docker python-dateutil \
    cryptography

print_success "Python пакеты установлены!"

# ============================================================================
# ШАГ 5: НАСТРОЙКА БАЗЫ ДАННЫХ (MySQL)
# ============================================================================
print_status "5. Настраиваем базу данных MySQL..."

# Устанавливаем MySQL
sudo apt install -y mysql-server

# Запускаем MySQL
sudo systemctl enable mysql --now

# Создаем базу данных для дашборда
sudo mysql -e "CREATE DATABASE IF NOT EXISTS server_dashboard;"
sudo mysql -e "CREATE USER IF NOT EXISTS 'dashboard_user'@'localhost' IDENTIFIED BY 'dashboard_password123';"
sudo mysql -e "GRANT ALL PRIVILEGES ON server_dashboard.* TO 'dashboard_user'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Создаем таблицы для мониторинга
sudo mysql server_dashboard <<EOF
CREATE TABLE IF NOT EXISTS system_stats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    cpu_percent FLOAT,
    memory_percent FLOAT,
    disk_percent FLOAT,
    network_up BIGINT,
    network_down BIGINT
);

CREATE TABLE IF NOT EXISTS vpn_clients (
    id INT AUTO_INCREMENT PRIMARY KEY,
    client_name VARCHAR(100),
    mac_address VARCHAR(17),
    ip_address VARCHAR(15),
    connected_at DATETIME,
    last_seen DATETIME,
    total_traffic BIGINT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS system_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    event_type ENUM('info', 'warning', 'critical'),
    message TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
EOF

print_success "База данных настроена!"

# ============================================================================
# ШАГ 6: НАСТРОЙКА ВЕБ-СЕРВЕРА
# ============================================================================
print_status "6. Настраиваем веб-сервер..."

# Создаем директорию для дашборда
sudo mkdir -p /var/www/html
sudo chown -R $USER:$USER /var/www/html

# Создаем базовый index.php
cat > /var/www/html/index.php << 'EOF'
<?php
phpinfo();
?>
EOF

# Настраиваем Nginx
sudo tee /etc/nginx/sites-available/dashboard > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.html index.php;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
    }

    location /api/ {
        try_files $uri $uri/ /api/index.php;
    }

    # WebSocket для реального времени
    location /ws/ {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
EOF

# Активируем сайт
sudo ln -sf /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Перезапускаем Nginx
sudo systemctl enable nginx php8.1-fpm --now
sudo systemctl restart nginx

print_success "Веб-сервер настроен!"

# ============================================================================
# ШАГ 7: НАСТРОЙКА БЕЗОПАСНОСТИ
# ============================================================================
print_status "7. Настраиваем безопасность..."

# Настраиваем фаервол
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 51820/udp
echo "y" | sudo ufw enable

# Настраиваем Fail2Ban
sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 3600
EOF

sudo systemctl enable fail2ban --now

print_success "Безопасность настроена!"

# ============================================================================
# ШАГ 8: СОЗДАЕМ СТРУКТУРУ ДАШБОРДА
# ============================================================================
print_status "8. Создаем структуру дашборда..."

# Создаем директории
mkdir -p /home/$USER/server-dashboard/{api,scripts,config,backups}

# Создаем основной скрипт мониторинга
cat > /home/$USER/server-dashboard/scripts/monitor.py << 'EOF'
#!/usr/bin/env python3
import psutil
import json
import time
import mysql.connector
from datetime import datetime

def get_db_connection():
    return mysql.connector.connect(
        host="localhost",
        user="dashboard_user",
        password="dashboard_password123",
        database="server_dashboard"
    )

def log_system_stats():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        stats = get_system_stats()
        net_io = psutil.net_io_counters()
        
        cursor.execute("""
            INSERT INTO system_stats 
            (cpu_percent, memory_percent, disk_percent, network_up, network_down)
            VALUES (%s, %s, %s, %s, %s)
        """, (stats['cpu']['percent'], stats['memory']['percent'], 
              stats['disk']['percent'], net_io.bytes_sent, net_io.bytes_recv))
        
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Database error: {e}")
        return False

def get_system_stats():
    return {
        'cpu': {
            'percent': psutil.cpu_percent(interval=1),
            'freq': psutil.cpu_freq().current if psutil.cpu_freq() else 0,
            'cores': psutil.cpu_count(),
            'temp': get_cpu_temp()
        },
        'memory': {
            'total': psutil.virtual_memory().total,
            'used': psutil.virtual_memory().used,
            'free': psutil.virtual_memory().free,
            'percent': psutil.virtual_memory().percent,
            'swap_total': psutil.swap_memory().total,
            'swap_used': psutil.swap_memory().used
        },
        'disk': {
            'total': psutil.disk_usage('/').total,
            'used': psutil.disk_usage('/').used,
            'free': psutil.disk_usage('/').free,
            'percent': psutil.disk_usage('/').percent
        },
        'network': get_network_stats(),
        'timestamp': datetime.now().isoformat()
    }

def get_cpu_temp():
    try:
        with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
            return float(f.read().strip()) / 1000
    except:
        return 0

def get_network_stats():
    net_io = psutil.net_io_counters()
    return {
        'bytes_sent': net_io.bytes_sent,
        'bytes_recv': net_io.bytes_recv,
        'packets_sent': net_io.packets_sent,
        'packets_recv': net_io.packets_recv
    }

if __name__ == "__main__":
    stats = get_system_stats()
    print(json.dumps(stats, indent=2))
    log_system_stats()
EOF

# Делаем скрипт исполняемым
chmod +x /home/$USER/server-dashboard/scripts/monitor.py

# Создаем API endpoint для дашборда
mkdir -p /var/www/html/api
cat > /var/www/html/api/stats.php << 'EOF'
<?php
header('Content-Type: application/json');

$db = new mysqli('localhost', 'dashboard_user', 'dashboard_password123', 'server_dashboard');

if ($db->connect_error) {
    die(json_encode(['error' => 'Database connection failed']));
}

// Получаем последние статистики
$result = $db->query("
    SELECT * FROM system_stats 
    ORDER BY timestamp DESC 
    LIMIT 1
");

$stats = $result->fetch_assoc();
$result->close();

// Получаем системную информацию
$cpu_usage = sys_getloadavg()[0] * 100;
$memory_usage = shell_exec("free | grep Mem | awk '{print $3/$2 * 100.0}'");
$disk_usage = shell_exec("df / | awk 'NR==2{print $5}' | sed 's/%//'");

echo json_encode([
    'cpu' => [
        'usage' => round($cpu_usage, 1),
        'cores' => (int)shell_exec("nproc"),
        'load' => sys_getloadavg()
    ],
    'memory' => [
        'usage' => round((float)$memory_usage, 1),
        'total' => (int)shell_exec("free -b | grep Mem | awk '{print $2}'"),
        'used' => (int)shell_exec("free -b | grep Mem | awk '{print $3}'")
    ],
    'disk' => [
        'usage' => (int)$disk_usage,
        'total' => (int)shell_exec("df -B1 / | awk 'NR==2{print $2}'"),
        'used' => (int)shell_exec("df -B1 / | awk 'NR==2{print $3}'")
    ],
    'timestamp' => date('Y-m-d H:i:s')
], JSON_PRETTY_PRINT);

$db->close();
?>
EOF

print_success "Структура дашборда создана!"

# ============================================================================
# ШАГ 9: НАСТРОЙКА СИСТЕМНЫХ СЕРВИСОВ
# ============================================================================
print_status "9. Настраиваем системные сервисы..."

# Создаем systemd сервис для мониторинга
sudo tee /etc/systemd/system/server-monitor.service > /dev/null << EOF
[Unit]
Description=Server Monitoring Daemon
After=network.target mysql.service

[Service]
Type=simple
User=$USER
WorkingDirectory=/home/$USER/server-dashboard
ExecStart=/usr/bin/python3 /home/$USER/server-dashboard/scripts/monitor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Создаем cron задание для мониторинга
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/bin/python3 /home/$USER/server-dashboard/scripts/monitor.py") | crontab -

# Включаем сервисы
sudo systemctl daemon-reload
sudo systemctl enable server-monitor --now

print_success "Системные сервисы настроены!"

# ============================================================================
# ШАГ 10: УСТАНОВКА VPN ИНСТРУМЕНТОВ
# ============================================================================
print_status "10. Устанавливаем VPN инструменты..."

# Устанавливаем V2Ray
sudo bash -c "$(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)"

# Устанавливаем Shadowsocks
pip3 install shadowsocks

# Создаем базовые конфиги
mkdir -p /home/$USER/vpn-configs

# Базовый конфиг V2Ray
sudo tee /usr/local/etc/v2ray/config.json > /dev/null << 'EOF'
{
  "log": {"loglevel": "warning"},
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

# Запускаем V2Ray
sudo systemctl enable v2ray --now

print_success "VPN инструменты установлены!"

# ============================================================================
# ШАГ 11: ФИНАЛЬНАЯ НАСТРОЙКА
# ============================================================================
print_status "11. Финальная настройка..."

# Даем права на веб-директорию
sudo chown -R $USER:$USER /var/www/html

# Создаем бэкап конфигов
mkdir -p /home/$USER/backups
tar -czf /home/$USER/backups/initial-setup-$(date +%Y%m%d).tar.gz \
    /etc/nginx /etc/php /home/$USER/server-dashboard /home/$USER/vpn-configs 2>/dev/null || true

# ============================================================================
# ЗАВЕРШЕНИЕ
# ============================================================================
print_success "🎉 УСТАНОВКА ЗАВЕРШЕНА!"
echo ""
echo "📊 ЧТО БЫЛО СДЕЛАНО:"
echo "   ✅ Обновлена система"
echo "   ✅ Установлены все необходимые пакеты"
echo "   ✅ Установлен Docker и Docker Compose"
echo "   ✅ Настроена MySQL база данных"
echo "   ✅ Настроен Nginx + PHP"
echo "   ✅ Настроена безопасность (UFW + Fail2Ban)"
echo "   ✅ Создана структура дашборда"
echo "   ✅ Настроены системные сервисы"
echo "   ✅ Установлены VPN инструменты"
echo ""
echo "🌐 ДОСТУП К ДАШБОРДУ:"
echo "   http://$(hostname -I | awk '{print $1}')"
echo ""
echo "🔧 ДОПОЛНИТЕЛЬНЫЕ КОМАНДЫ:"
echo "   Статус сервисов: sudo systemctl status nginx mysql server-monitor"
echo "   Просмотр логов: sudo journalctl -u server-monitor -f"
echo "   MySQL консоль: sudo mysql -u root"
echo ""
echo "🚀 ПЕРЕЗАГРУЗИ СИСТЕМУ ДЛЯ ПРИМЕНЕНИЯ ВСЕХ ИЗМЕНЕНИЙ:"
echo "   sudo reboot"
echo ""
print_warning "⚠️  НЕ ЗАБУДЬ СМЕНИТЬ ПАРОЛЬ В БАЗЕ ДАННЫХ!"
echo "   Текущий пароль: dashboard_password123"
echo "   Смени командой: sudo mysql -e \"ALTER USER 'dashboard_user'@'localhost' IDENTIFIED BY 'НОВЫЙ_СЛОЖНЫЙ_ПАРОЛЬ';\""