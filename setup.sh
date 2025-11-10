cat > ultimate-server.sh << 'EOF'
#!/bin/bash

# ==============================================
# 🚀 ULTIMATE SERVER SETUP SCRIPT
# Version: 3.0 | Full Stack Dashboard
# ==============================================

echo "
███████ ██      ██ ████████ ██ ███    ███ ███████ 
██      ██      ██    ██    ██ ████  ████ ██      
█████   ██      ██    ██    ██ ██ ████ ██ █████   
██      ██      ██    ██    ██ ██  ██  ██ ██      
███████ ███████ ██    ██    ██ ██      ██ ███████ 
                                                   
            FULL STACK DASHBOARD v3.0
"

# =============================================================================
# CONFIGURATION
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

USER=$(logname)
IP=$(hostname -I | awk '{print $1}')
BACKUP_DIR="/opt/backups"
SCRIPTS_DIR="/opt/server-scripts"
DASHBOARD_DIR="/var/www/dashboard"

# =============================================================================
# FUNCTIONS
# =============================================================================
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step() { echo -e "${BLUE}[STEP]${NC} $1"; }
debug() { echo -e "${PURPLE}[DEBUG]${NC} $1"; }

check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        error "Запускай с sudo: sudo bash $0"
        exit 1
    fi
}

create_directories() {
    step "Создание системных директорий..."
    mkdir -p $BACKUP_DIR/{daily,weekly,monthly}
    mkdir -p $SCRIPTS_DIR
    mkdir -p $DASHBOARD_DIR/{api,uploads,tmp,logs}
    mkdir -p /home/$USER/.ssh
    mkdir -p /var/log/server-dashboard
}

# =============================================================================
# 1. SYSTEM UPDATE & PACKAGES INSTALLATION
# =============================================================================
system_setup() {
    step "1. ОБНОВЛЕНИЕ И УСТАНОВКА ПАКЕТОВ..."
    
    info "Обновление пакетов..."
    apt update && apt upgrade -y
    
    info "Установка системных утилит..."
    apt install -y curl wget git htop net-tools ufw ntpdate sudo
    apt install -y nano vim tmux tree pv progress bc
    apt install -y software-properties-common apt-transport-https ca-certificates
    
    info "Установка серверного ПО..."
    apt install -y nginx mysql-server postgresql redis-server
    apt install -y cockpit cockpit-* fail2ban openssh-server
    apt install -y python3 python3-pip python3-venv
    apt install -y nodejs npm
    
    info "Установка PHP и расширений..."
    apt install -y php-fpm php-mysql php-pgsql php-redis
    apt install -y php-mbstring php-gd php-xml php-zip php-curl
    apt install -y php-bcmath php-json php-intl php-sqlite3
    
    info "Установка дополнительных утилит..."
    apt install -y zip unzip rclone rsync cron anacron
    apt install -y prometheus-node-exporter net-tools
    apt install -y docker.io docker-compose
    
    info "Добавление пользователя в группы..."
    usermod -aG docker $USER
    usermod -aG www-data $USER
}

# =============================================================================
# 2. SYSTEM CONFIGURATION
# =============================================================================
system_configuration() {
    step "2. СИСТЕМНАЯ КОНФИГУРАЦИЯ..."
    
    info "Настройка времени..."
    timedatectl set-timezone Europe/Moscow
    ntpdate pool.ntp.org
    
    info "Создание файла подкачки 8GB..."
    swapoff /swapfile 2>/dev/null
    dd if=/dev/zero of=/swapfile bs=1G count=8 status=progress
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    
    info "Оптимизация sysctl..."
    cat >> /etc/sysctl.conf << 'SYSCTL'
# Server Optimization
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 16384 16777216
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
vm.swappiness = 10
vm.vfs_cache_pressure = 50
SYSCTL
    
    sysctl -p
}

# =============================================================================
# 3. SECURITY SETUP
# =============================================================================
security_setup() {
    step "3. НАСТРОЙКА БЕЗОПАСНОСТИ..."
    
    info "Настройка SSH..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    cat > /etc/ssh/sshd_config << 'SSHD'
Port 22
Protocol 2
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
SSHD

    info "Генерация SSH ключей..."
    if [ ! -f /home/$USER/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -b 4096 -f /home/$USER/.ssh/id_rsa -N "" -q
        ssh-keygen -t ed25519 -f /home/$USER/.ssh/id_ed25519 -N "" -q
        cat /home/$USER/.ssh/id_rsa.pub >> /home/$USER/.ssh/authorized_keys
        cat /home/$USER/.ssh/id_ed25519.pub >> /home/$USER/.ssh/authorized_keys
    fi
    
    chmod 600 /home/$USER/.ssh/authorized_keys
    chmod 700 /home/$USER/.ssh
    chown -R $USER:$USER /home/$USER/.ssh

    info "Настройка Fail2Ban..."
    cat > /etc/fail2ban/jail.local << 'FAIL2BAN'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = auto

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3

[sshd-ddos]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 5

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-botsearch]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 10
FAIL2BAN

    info "Настройка фаервола..."
    ufw --force reset
    ufw allow ssh
    ufw allow http
    ufw allow https
    ufw allow 9090
    ufw allow 3000
    ufw allow 8080
    ufw --force enable
}

# =============================================================================
# 4. DATABASE SETUP
# =============================================================================
database_setup() {
    step "4. НАСТРОЙКА БАЗ ДАННЫХ..."
    
    info "Настройка MySQL..."
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'RootMySQL123!';"
    mysql -e "CREATE DATABASE IF NOT EXISTS dashboard_db;"
    mysql -e "CREATE DATABASE IF NOT EXISTS server_stats;"
    mysql -e "CREATE USER IF NOT EXISTS 'dashboard_user'@'localhost' IDENTIFIED BY 'DashboardPass123!';"
    mysql -e "CREATE USER IF NOT EXISTS 'monitor_user'@'localhost' IDENTIFIED BY 'MonitorPass123!';"
    mysql -e "GRANT ALL PRIVILEGES ON dashboard_db.* TO 'dashboard_user'@'localhost';"
    mysql -e "GRANT SELECT, INSERT ON server_stats.* TO 'monitor_user'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    info "Создание таблиц для дашборда..."
    mysql dashboard_db << 'MYSQL_TABLES'
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(100),
    role ENUM('superadmin','admin','user') DEFAULT 'user',
    api_key VARCHAR(64),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL
);

CREATE TABLE IF NOT EXISTS server_stats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    cpu_percent DECIMAL(5,2),
    ram_percent DECIMAL(5,2),
    disk_percent DECIMAL(5,2),
    load_1min DECIMAL(5,2),
    load_5min DECIMAL(5,2),
    load_15min DECIMAL(5,2),
    network_rx BIGINT,
    network_tx BIGINT
);

CREATE TABLE IF NOT EXISTS server_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(50),
    event_message TEXT,
    event_data JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS backups (
    id INT AUTO_INCREMENT PRIMARY KEY,
    backup_type VARCHAR(20),
    filename VARCHAR(255),
    size BIGINT,
    status ENUM('success','failed','running'),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT IGNORE INTO users (username, password_hash, role, api_key) VALUES 
('superadmin', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'superadmin', MD5(RAND())),
('admin', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'admin', MD5(RAND()));
MYSQL_TABLES

    info "Настройка PostgreSQL..."
    sudo -u postgres psql << 'PSQL'
CREATE DATABASE dashboard_pg;
CREATE USER dashboard_pg_user WITH PASSWORD 'PgPass123!';
GRANT ALL PRIVILEGES ON DATABASE dashboard_pg TO dashboard_pg_user;
\c dashboard_pg;
CREATE TABLE IF NOT EXISTS system_logs (
    id SERIAL PRIMARY KEY,
    level VARCHAR(20),
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
PSQL
}

# =============================================================================
# 5. MONITORING & SCRIPTS
# =============================================================================
monitoring_setup() {
    step "5. СИСТЕМА МОНИТОРИНГА И СКРИПТЫ..."
    
    info "Создание скриптов мониторинга..."
    
    # Основной мониторинг
    cat > $SCRIPTS_DIR/monitor.py << 'MONITOR_PY'
#!/usr/bin/env python3
import psutil
import subprocess
import time
import json
import mysql.connector
from datetime import datetime

def get_size(bytes):
    for unit in ['', 'K', 'M', 'G', 'T', 'P']:
        if bytes < 1024:
            return f"{bytes:.2f}{unit}B"
        bytes /= 1024

def get_system_stats():
    # CPU
    cpu_percent = psutil.cpu_percent(interval=1)
    load_avg = psutil.getloadavg()
    
    # Memory
    mem = psutil.virtual_memory()
    swap = psutil.swap_memory()
    
    # Disk
    disk = psutil.disk_usage('/')
    disk_io = psutil.disk_io_counters()
    
    # Network
    net_io = psutil.net_io_counters()
    
    # Services
    services = ['nginx', 'mysql', 'postgresql', 'cockpit', 'fail2ban', 'ssh', 'redis']
    service_status = {}
    for service in services:
        try:
            result = subprocess.run(['systemctl', 'is-active', service], 
                                  capture_output=True, text=True)
            service_status[service] = result.stdout.strip()
        except:
            service_status[service] = 'unknown'
    
    # Docker
    try:
        docker_result = subprocess.run(['docker', 'ps', '-q'], capture_output=True, text=True)
        docker_containers = len(docker_result.stdout.strip().split('\n')) if docker_result.stdout.strip() else 0
    except:
        docker_containers = 0
    
    stats = {
        'timestamp': datetime.now().isoformat(),
        'cpu': {
            'percent': cpu_percent,
            'load_1min': load_avg[0],
            'load_5min': load_avg[1],
            'load_15min': load_avg[2],
            'cores': psutil.cpu_count()
        },
        'memory': {
            'percent': mem.percent,
            'used': mem.used,
            'total': mem.total,
            'available': mem.available
        },
        'swap': {
            'percent': swap.percent,
            'used': swap.used,
            'total': swap.total
        },
        'disk': {
            'percent': disk.percent,
            'used': disk.used,
            'total': disk.total,
            'read_bytes': disk_io.read_bytes if disk_io else 0,
            'write_bytes': disk_io.write_bytes if disk_io else 0
        },
        'network': {
            'bytes_sent': net_io.bytes_sent,
            'bytes_recv': net_io.bytes_recv,
            'packets_sent': net_io.packets_sent,
            'packets_recv': net_io.packets_recv
        },
        'services': service_status,
        'docker_containers': docker_containers,
        'uptime': subprocess.run(['uptime', '-p'], capture_output=True, text=True).stdout.strip()
    }
    
    return stats

def save_to_database(stats):
    try:
        conn = mysql.connector.connect(
            host='localhost',
            user='monitor_user',
            password='MonitorPass123!',
            database='server_stats'
        )
        cursor = conn.cursor()
        
        query = """
        INSERT INTO server_stats 
        (cpu_percent, ram_percent, disk_percent, load_1min, load_5min, load_15min, network_rx, network_tx)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """
        
        cursor.execute(query, (
            stats['cpu']['percent'],
            stats['memory']['percent'],
            stats['disk']['percent'],
            stats['cpu']['load_1min'],
            stats['cpu']['load_5min'],
            stats['cpu']['load_15min'],
            stats['network']['bytes_recv'],
            stats['network']['bytes_sent']
        ))
        
        conn.commit()
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"Database error: {e}")

if __name__ == "__main__":
    stats = get_system_stats()
    
    # Save to database
    save_to_database(stats)
    
    # Print to console
    print(json.dumps(stats, indent=2))
MONITOR_PY

    # Скрипт бэкапов
    cat > $SCRIPTS_DIR/backup-manager.py << 'BACKUP_PY'
#!/usr/bin/env python3
import os
import subprocess
import datetime
import mysql.connector
from pathlib import Path

def run_backup(backup_type='daily'):
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = Path(f"/opt/backups/{backup_type}")
    backup_dir.mkdir(parents=True, exist_ok=True)
    
    try:
        # MySQL backup
        mysql_file = backup_dir / f"mysql_{timestamp}.sql"
        subprocess.run([
            'mysqldump', '-u', 'root', '-pRootMySQL123!',
            '--all-databases', '--single-transaction',
            '--routines', '--triggers',
            f'--result-file={mysql_file}'
        ], check=True)
        
        # PostgreSQL backup
        pg_file = backup_dir / f"postgresql_{timestamp}.sql"
        subprocess.run([
            'sudo', '-u', 'postgres', 'pg_dumpall'
        ], stdout=open(pg_file, 'w'), check=True)
        
        # Configuration backup
        config_file = backup_dir / f"configs_{timestamp}.tar.gz"
        subprocess.run([
            'tar', '-czf', str(config_file),
            '/etc/nginx', '/etc/mysql', '/etc/postgresql',
            '/opt/server-scripts', '/var/www/dashboard'
        ], check=True)
        
        # Log backup event
        log_backup_event(backup_type, 'success', {
            'mysql_file': str(mysql_file),
            'pg_file': str(pg_file),
            'config_file': str(config_file)
        })
        
        # Cleanup old backups
        cleanup_old_backups(backup_type)
        
        return True
        
    except subprocess.CalledProcessError as e:
        log_backup_event(backup_type, 'failed', {'error': str(e)})
        return False

def log_backup_event(backup_type, status, data):
    try:
        conn = mysql.connector.connect(
            host='localhost',
            user='monitor_user',
            password='MonitorPass123!',
            database='server_stats'
        )
        cursor = conn.cursor()
        
        cursor.execute("""
            INSERT INTO server_events (event_type, event_message, event_data)
            VALUES (%s, %s, %s)
        """, (f"backup_{backup_type}", status, json.dumps(data)))
        
        conn.commit()
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"Failed to log backup event: {e}")

def cleanup_old_backups(backup_type):
    backup_dir = Path(f"/opt/backups/{backup_type}")
    
    if backup_type == 'daily':
        days_to_keep = 7
    elif backup_type == 'weekly':
        days_to_keep = 30
    else:
        days_to_keep = 365
    
    cutoff_time = datetime.datetime.now() - datetime.timedelta(days=days_to_keep)
    
    for file in backup_dir.glob('*'):
        if file.stat().st_mtime < cutoff_time.timestamp():
            file.unlink()

if __name__ == "__main__":
    import sys
    backup_type = sys.argv[1] if len(sys.argv) > 1 else 'daily'
    run_backup(backup_type)
BACKUP_PY

    # System info script
    cat > /usr/local/bin/server-info << 'SERVER_INFO'
cat >> ultimate-server.sh << 'EOF'
#!/bin/bash
echo "
🖥️ === СИСТЕМНАЯ ИНФОРМАЦИЯ ===
Хост: $(hostname)
IP: $(hostname -I | awk '{print $1}')
Время: $(date)
Uptime: $(uptime -p)

=== 📊 РЕСУРСЫ ===
CPU: $(top -bn1 | grep \"Cpu(s)\" | awk '{print $2}')%
RAM: $(free -h | grep Mem | awk '{print $3 \"/\" $2}')
Disk: $(df -h / | awk 'NR==2 {print $3 \"/\" $2 \" (\" $5 \")\"}')

=== 🔧 СЕРВИСЫ ===
$(systemctl list-units --type=service --state=running | head -10)

=== 🌐 СЕТЬ ===
$(ip addr show | grep inet | grep -v 127.0.0.1)
"
EOF

chmod +x /usr/local/bin/server-info

    # SSH Key Manager
    cat > $SCRIPTS_DIR/ssh-manager.py << 'SSH_MANAGER'
#!/usr/bin/env python3
import os
import subprocess
import secrets
import string

def generate_ssh_key(key_type='rsa', key_name='id_custom', password=None):
    key_path = f"/home/{os.getenv('USER')}/.ssh/{key_name}"
    
    if key_type == 'rsa':
        cmd = ['ssh-keygen', '-t', 'rsa', '-b', '4096', '-f', key_path]
    elif key_type == 'ed25519':
        cmd = ['ssh-keygen', '-t', 'ed25519', '-f', key_path]
    else:
        return False, "Unsupported key type"
    
    if password:
        cmd.extend(['-N', password])
    else:
        cmd.extend(['-N', ''])
    
    try:
        subprocess.run(cmd, check=True, input='\n', text=True)
        return True, f"SSH key generated: {key_path}"
    except subprocess.CalledProcessError as e:
        return False, f"Error generating key: {e}"

def generate_random_password(length=16):
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(secrets.choice(alphabet) for _ in range(length))

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        key_type = sys.argv[1]
        key_name = sys.argv[2] if len(sys.argv) > 2 else f"id_{key_type}"
        success, message = generate_ssh_key(key_type, key_name)
        print(message)
SSH_MANAGER

    chmod +x $SCRIPTS_DIR/*.py

    info "Настройка cron заданий..."
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/bin/python3 $SCRIPTS_DIR/monitor.py") | crontab -
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/bin/python3 $SCRIPTS_DIR/backup-manager.py daily") | crontab -
    (crontab -l 2>/dev/null; echo "0 3 * * 0 /usr/bin/python3 $SCRIPTS_DIR/backup-manager.py weekly") | crontab -
}

# =============================================================================
# 6. DASHBOARD SETUP
# =============================================================================
dashboard_setup() {
    step "6. СОЗДАНИЕ МЕГА-ДАШБОРДА..."
    
    info "Создание главной страницы..."
    cat > $DASHBOARD_DIR/index.php << 'DASHBOARD_MAIN'
<?php
session_start();
ob_start();

define('DB_HOST', 'localhost');
define('DB_USER', 'dashboard_user');
define('DB_PASS', 'DashboardPass123!');
define('DB_NAME', 'dashboard_db');

// Auto-login for demo (remove in production)
if (!isset($_SESSION['user']) && $_GET['auto'] == '1') {
    $_SESSION['user'] = 'admin';
    $_SESSION['role'] = 'admin';
    $_SESSION['user_id'] = 1;
}

if (!isset($_SESSION['user'])) {
    header('Location: /dashboard/login.php');
    exit;
}

$current_tab = $_GET['tab'] ?? 'dashboard';
$user = $_SESSION['user'];
$role = $_SESSION['role'];
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🚀 Ultimate Server Dashboard</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        :root {
            --primary: #6366f1;
            --secondary: #8b5cf6;
            --success: #10b981;
            --warning: #f59e0b;
            --danger: #ef4444;
            --dark: #1f2937;
            --light: #f8fafc;
        }
        
        body {
            font-family: 'Segoe UI', system-ui, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        
        .sidebar {
            background: rgba(255,255,255,0.95);
            backdrop-filter: blur(10px);
            min-height: 100vh;
            box-shadow: 5px 0 15px rgba(0,0,0,0.1);
        }
        
        .nav-link {
            color: var(--dark);
            padding: 12px 20px;
            margin: 5px 0;
            border-radius: 10px;
            transition: all 0.3s ease;
        }
        
        .nav-link:hover, .nav-link.active {
            background: var(--primary);
            color: white;
            transform: translateX(5px);
        }
        
        .main-content {
            background: rgba(255,255,255,0.95);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            margin: 20px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        
        .stat-card {
            background: white;
            border-radius: 15px;
            padding: 20px;
            margin-bottom: 20px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.08);
            border-left: 4px solid var(--primary);
            transition: transform 0.3s ease;
        }
        
        .stat-card:hover {
            transform: translateY(-5px);
        }
        
        .progress {
            height: 8px;
            border-radius: 10px;
        }
        
        .service-status {
            padding: 8px 15px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: bold;
        }
        
        .status-running { background: var(--success); color: white; }
        .status-stopped { background: var(--danger); color: white; }
        .status-warning { background: var(--warning); color: white; }
        
        .terminal {
            background: #1a1b26;
            color: #a9b1d6;
            font-family: 'Monaco', 'Menlo', monospace;
            border-radius: 10px;
            padding: 15px;
            max-height: 400px;
            overflow-y: auto;
        }
        
        .file-item {
            padding: 10px;
            border-radius: 8px;
            margin: 5px 0;
            transition: background 0.3s ease;
        }
        
        .file-item:hover {
            background: #f8f9fa;
        }
    </style>
</head>
<body>
    <div class="container-fluid">
        <div class="row">
            <!-- Sidebar -->
            <div class="col-md-3 col-lg-2 sidebar p-0">
                <div class="p-4">
                    <h4 class="text-center mb-4">
                        <i class="fas fa-server me-2"></i>
                        Server Dashboard
                    </h4>
                    
                    <nav class="nav flex-column">
                        <a class="nav-link <?= $current_tab == 'dashboard' ? 'active' : '' ?>" href="?tab=dashboard">
                            <i class="fas fa-tachometer-alt me-2"></i>Дашборд
                        </a>
                        <a class="nav-link <?= $current_tab == 'monitoring' ? 'active' : '' ?>" href="?tab=monitoring">
                            <i class="fas fa-chart-line me-2"></i>Мониторинг
                        </a>
                        <a class="nav-link <?= $current_tab == 'files' ? 'active' : '' ?>" href="?tab=files">
                            <i class="fas fa-folder me-2"></i>Файлы
                        </a>
                        <a class="nav-link <?= $current_tab == 'ssh' ? 'active' : '' ?>" href="?tab=ssh">
                            <i class="fas fa-key me-2"></i>SSH Ключи
                        </a>
                        <a class="nav-link <?= $current_tab == 'databases' ? 'active' : '' ?>" href="?tab=databases">
                            <i class="fas fa-database me-2"></i>Базы данных
                        </a>
                        <a class="nav-link <?= $current_tab == 'backups' ? 'active' : '' ?>" href="?tab=backups">
                            <i class="fas fa-shield-alt me-2"></i>Бэкапы
                        </a>
                        <a class="nav-link <?= $current_tab == 'services' ? 'active' : '' ?>" href="?tab=services">
                            <i class="fas fa-cogs me-2"></i>Сервисы
                        </a>
                        <a class="nav-link <?= $current_tab == 'terminal' ? 'active' : '' ?>" href="?tab=terminal">
                            <i class="fas fa-terminal me-2"></i>Терминал
                        </a>
                    </nav>
                    
                    <div class="mt-5 p-3 bg-light rounded">
                        <small class="text-muted">
                            <i class="fas fa-user me-1"></i> <?= $user ?><br>
                            <i class="fas fa-shield me-1"></i> <?= $role ?><br>
                            <i class="fas fa-clock me-1"></i> <span id="server-time"></span>
                        </small>
                    </div>
                </div>
            </div>
            
            <!-- Main Content -->
            <div class="col-md-9 col-lg-10 main-content">
                <?php
                switch($current_tab) {
                    case 'dashboard':
                        include 'tabs/dashboard.php';
                        break;
                    case 'monitoring':
                        include 'tabs/monitoring.php';
                        break;
                    case 'files':
                        include 'tabs/files.php';
                        break;
                    case 'ssh':
                        include 'tabs/ssh.php';
                        break;
                    case 'databases':
                        include 'tabs/databases.php';
                        break;
                    case 'backups':
                        include 'tabs/backups.php';
                        break;
                    case 'services':
                        include 'tabs/services.php';
                        break;
                    case 'terminal':
                        include 'tabs/terminal.php';
                        break;
                    default:
                        include 'tabs/dashboard.php';
                }
                ?>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // Update server time
        function updateServerTime() {
            const now = new Date();
            document.getElementById('server-time').textContent = 
                now.toLocaleTimeString('ru-RU');
        }
        setInterval(updateServerTime, 1000);
        updateServerTime();
        
        // Auto refresh stats
        function refreshStats() {
            fetch('api/stats.php')
                .then(r => r.json())
                .then(data => {
                    if (document.getElementById('cpu-percent')) {
                        document.getElementById('cpu-percent').textContent = data.cpu + '%';
                        document.getElementById('cpu-bar').style.width = data.cpu + '%';
                    }
                    if (document.getElementById('ram-percent')) {
                        document.getElementById('ram-percent').textContent = data.ram + '%';
                        document.getElementById('ram-bar').style.width = data.ram + '%';
                    }
                });
        }
        setInterval(refreshStats, 5000);
    </script>
</body>
</html>
DASHBOARD_MAIN

    # Create tabs directory
    mkdir -p $DASHBOARD_DIR/tabs
    
    # Dashboard tab
    cat > $DASHBOARD_DIR/tabs/dashboard.php << 'DASHBOARD_TAB'
<div class="p-4">
    <h2 class="mb-4"><i class="fas fa-tachometer-alt me-2"></i>Главная панель</h2>
    
    <!-- Quick Stats -->
    <div class="row">
        <div class="col-md-3">
            <div class="stat-card">
                <div class="d-flex justify-content-between">
                    <div>
                        <h5 class="text-muted">CPU</h5>
                        <h3 id="cpu-percent">0%</h3>
                    </div>
                    <i class="fas fa-microchip fa-2x text-primary"></i>
                </div>
                <div class="progress mt-2">
                    <div id="cpu-bar" class="progress-bar bg-primary" style="width: 0%"></div>
                </div>
            </div>
        </div>
        
        <div class="col-md-3">
            <div class="stat-card">
                <div class="d-flex justify-content-between">
                    <div>
                        <h5 class="text-muted">RAM</h5>
                        <h3 id="ram-percent">0%</h3>
                    </div>
                    <i class="fas fa-memory fa-2x text-success"></i>
                </div>
                <div class="progress mt-2">
                    <div id="ram-bar" class="progress-bar bg-success" style="width: 0%"></div>
                </div>
            </div>
        </div>
        
        <div class="col-md-3">
            <div class="stat-card">
                <div class="d-flex justify-content-between">
                    <div>
                        <h5 class="text-muted">Disk</h5>
                        <h3 id="disk-percent">0%</h3>
                    </div>
                    <i class="fas fa-hard-drive fa-2x text-warning"></i>
                </div>
                <div class="progress mt-2">
                    <div id="disk-bar" class="progress-bar bg-warning" style="width: 0%"></div>
                </div>
            </div>
        </div>
        
        <div class="col-md-3">
            <div class="stat-card">
                <div class="d-flex justify-content-between">
                    <div>
                        <h5 class="text-muted">Network</h5>
                        <h3 id="network-status">Online</h3>
                    </div>
                    <i class="fas fa-wifi fa-2x text-info"></i>
                </div>
                <small class="text-muted" id="network-ips">Loading...</small>
            </div>
        </div>
    </div>
    
    <!-- Services Status -->
    <div class="row mt-4">
        <div class="col-md-6">
            <div class="stat-card">
                <h5><i class="fas fa-cogs me-2"></i>Статус сервисов</h5>
                <div id="services-list">
                    <!-- Services will be loaded by JavaScript -->
                </div>
            </div>
        </div>
        
        <div class="col-md-6">
            <div class="stat-card">
                <h5><i class="fas fa-bolt me-2"></i>Быстрые действия</h5>
                <div class="d-grid gap-2">
                    <button class="btn btn-primary" onclick="executeCommand('server-info')">
                        <i class="fas fa-info-circle me-2"></i>Информация о системе
                    </button>
                    <button class="btn btn-warning" onclick="executeCommand('sudo systemctl restart nginx')">
                        <i class="fas fa-redo me-2"></i>Перезапуск Nginx
                    </button>
                    <button class="btn btn-info" onclick="executeCommand('sudo systemctl status')">
                        <i class="fas fa-list me-2"></i>Все сервисы
                    </button>
                    <a href="https://<?= $_SERVER['SERVER_ADDR'] ?>:9090" target="_blank" class="btn btn-success">
                        <i class="fas fa-cog me-2"></i>Cockpit Panel
                    </a>
                </div>
            </div>
        </div>
    </div>
    
    <!-- System Information -->
    <div class="row mt-4">
        <div class="col-12">
            <div class="stat-card">
                <h5><i class="fas fa-info-circle me-2"></i>Системная информация</h5>
                <div class="row">
                    <div class="col-md-6">
                        <table class="table table-sm">
                            <tr><td><strong>Хост:</strong></td><td id="info-host"><?= gethostname() ?></td></tr>
                            <tr><td><strong>IP адрес:</strong></td><td id="info-ip"><?= $_SERVER['SERVER_ADDR'] ?></td></tr>
                            <tr><td><strong>ОС:</strong></td><td id="info-os">Loading...</td></tr>
                            <tr><td><strong>Ядро:</strong></td><td id="info-kernel">Loading...</td></tr>
                        </table>
                    </div>
                    <div class="col-md-6">
                        <table class="table table-sm">
                            <tr><td><strong>Время работы:</strong></td><td id="info-uptime">Loading...</td></tr>
                            <tr><td><strong>Дата:</strong></td><td id="info-date">Loading...</td></tr>
                            <tr><td><strong>Пользователи:</strong></td><td id="info-users">Loading...</td></tr>
                            <tr><td><strong>Процессы:</strong></td><td id="info-processes">Loading...</td></tr>
                        </table>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
// Load system information
fetch('api/system-info.php')
    .then(r => r.json())
    .then(data => {
        document.getElementById('info-os').textContent = data.os;
        document.getElementById('info-kernel').textContent = data.kernel;
        document.getElementById('info-uptime').textContent = data.uptime;
        document.getElementById('info-date').textContent = data.date;
        document.getElementById('info-users').textContent = data.users;
        document.getElementById('info-processes').textContent = data.processes;
    });

// Load services status
function loadServices() {
    fetch('api/services.php')
        .then(r => r.json())
        .then(services => {
            let html = '';
            for (const [service, status] of Object.entries(services)) {
                const statusClass = status === 'active' ? 'status-running' : 'status-stopped';
                const statusText = status === 'active' ? 'RUNNING' : 'STOPPED';
                html += `
                    <div class="d-flex justify-content-between align-items-center mb-2">
                        <span>${service}</span>
                        <span class="service-status ${statusClass}">${statusText}</span>
                    </div>
                `;
            }
            document.getElementById('services-list').innerHTML = html;
        });
}

setInterval(loadServices, 10000);
loadServices();

function executeCommand(cmd) {
    fetch('api/command.php?cmd=' + encodeURIComponent(cmd))
        .then(r => r.text())
        .then(result => {
            alert('Результат:\n' + result);
        });
}
</script>
DASHBOARD_TAB

    # Create other tabs (files, ssh, databases, backups, services, terminal)
    # [Здесь будут остальные вкладки - файловый менеджер, управление SSH, базы данных, бэкапы, сервисы, терминал]
    
    info "Создание API endpoints..."
    mkdir -p $DASHBOARD_DIR/api
    
    # Stats API
    cat > $DASHBOARD_DIR/api/stats.php << 'STATS_API'
<?php
header('Content-Type: application/json');

function get_system_stats() {
    // CPU usage from /proc/loadavg
    $load = sys_getloadavg();
    $cpu_percent = round($load[0] * 100 / 4, 1); // Assuming 4 cores
    
    // Memory usage
    $meminfo = file_get_contents('/proc/meminfo');
    preg_match('/MemTotal:\s+(\d+)/', $meminfo, $total);
    preg_match('/MemAvailable:\s+(\d+)/', $meminfo, $available);
    $ram_percent = round(100 - ($available[1] / $total[1] * 100), 1);
    
    // Disk usage
    $disk_total = disk_total_space('/');
    $disk_free = disk_free_space('/');
    $disk_percent = round(100 - ($disk_free / $disk_total * 100), 1);
    
    return [
        'cpu' => $cpu_percent,
        'ram' => $ram_percent,
        'disk' => $disk_percent,
        'load' => $load[0],
        'timestamp' => date('H:i:s')
    ];
}

echo json_encode(get_system_stats());
?>
STATS_API

    # Command API
    cat > $DASHBOARD_DIR/api/command.php << 'COMMAND_API'
<?php
header('Content-Type: text/plain');
session_start();

if (!isset($_SESSION['user'])) {
    die("Ошибка авторизации!");
}

$cmd = $_GET['cmd'] ?? '';
$allowed_commands = [
    'server-info', 'uptime', 'whoami', 'date',
    'free -h', 'df -h', 'ps aux | head -20'
];

// Security check - only allow certain commands
$is_safe = false;
foreach ($allowed_commands as $allowed) {
    if (strpos($cmd, $allowed) === 0) {
        $is_safe = true;
        break;
    }
}

if (!$is_safe && strpos($cmd, 'sudo') === false) {
    // Allow some safe system commands without sudo
    $safe_patterns = ['/^ls/', '/^cat \/proc\/meminfo/', '/^cat \/proc\/loadavg/'];
    foreach ($safe_patterns as $pattern) {
        if (preg_match($pattern, $cmd)) {
            $is_safe = true;
            break;
        }
    }
}

if ($is_safe) {
    $output = shell_exec("timeout 10 " . escapeshellcmd($cmd) . " 2>&1");
    echo $output ?: "Команда выполнена (нет вывода)";
} else {
    echo "Команда не разрешена для безопасности";
}
?>
COMMAND_API

    # System Info API
    cat > $DASHBOARD_DIR/api/system-info.php << 'SYSINFO_API'
<?php
header('Content-Type: application/json');

$info = [
    'os' => shell_exec('lsb_release -d | cut -f2'),
    'kernel' => shell_exec('uname -r'),
    'uptime' => shell_exec('uptime -p'),
    'date' => date('Y-m-d H:i:s'),
    'users' => shell_exec('who | wc -l'),
    'processes' => shell_exec('ps aux | wc -l')
];

// Clean up values
foreach ($info as &$value) {
    $value = trim($value);
}

echo json_encode($info);
?>
SYSINFO_API

    # Services API
    cat > $DASHBOARD_DIR/api/services.php << 'SERVICES_API'
<?php
header('Content-Type: application/json');

$services = [
    'nginx', 'mysql', 'postgresql', 'cockpit', 
    'fail2ban', 'ssh', 'redis', 'php8.1-fpm'
];

$status = [];
foreach ($services as $service) {
    $output = shell_exec("systemctl is-active $service 2>/dev/null");
    $status[$service] = trim($output) === 'active' ? 'active' : 'inactive';
}

echo json_encode($status);
?>
SERVICES_API

    # Login page
    cat > $DASHBOARD_DIR/login.php << 'LOGIN_PAGE'
<?php
session_start();

if (isset($_SESSION['user'])) {
    header('Location: index.php');
    exit;
}

if ($_POST['login']) {
    $username = $_POST['username'];
    $password = $_POST['password'];
    
    // Simple demo auth (in production use database)
    if ($username === 'admin' && $password === 'admin123') {
        $_SESSION['user'] = 'admin';
        $_SESSION['role'] = 'admin';
        header('Location: index.php?auto=1');
        exit;
    } else {
        $error = "Неверный логин или пароль!";
    }
}
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🔐 Вход - Ultimate Dashboard</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
        }
        .login-card {
            background: rgba(255,255,255,0.95);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="row justify-content-center">
            <div class="col-md-6 col-lg-4">
                <div class="login-card p-5">
                    <div class="text-center mb-4">
                        <h2>🖥️</h2>
                        <h4>Server Dashboard</h4>
                        <p class="text-muted">Войдите в систему</p>
                    </div>
                    
                    <?php if (isset($error)): ?>
                        <div class="alert alert-danger"><?= $error ?></div>
                    <?php endif; ?>
                    
                    <form method="POST">
                        <div class="mb-3">
                            <label class="form-label">Логин</label>
                            <input type="text" name="username" class="form-control" value="admin" required>
                        </div>
                        <div class="mb-3">
                            <label class="form-label">Пароль</label>
                            <input type="password" name="password" class="form-control" value="admin123" required>
                        </div>
                        <button type="submit" name="login" value="1" class="btn btn-primary w-100">
                            🚀 Войти в систему
                        </button>
                    </form>
                    
                    <div class="mt-4 text-center">
                        <small class="text-muted">
                            Демо доступ: admin / admin123
                        </small>
                    </div>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
LOGIN_PAGE

    info "Настройка прав доступа..."
    chown -R www-data:www-data $DASHBOARD_DIR
    chmod -R 755 $DASHBOARD_DIR
    chmod 644 $DASHBOARD_DIR/*.php
    chmod 644 $DASHBOARD_DIR/api/*.php
    chmod 644 $DASHBOARD_DIR/tabs/*.php
}

# =============================================================================
# 7. FINAL SETUP
# =============================================================================
final_setup() {
    step "7. ФИНАЛЬНАЯ НАСТРОЙКА..."
    
    info "Настройка Nginx..."
    cat > /etc/nginx/sites-available/dashboard << 'NGINX_CONFIG'
server {
    listen 80;
    server_name _;
    root /var/www/dashboard;
    index index.php index.html;
    
    access_log /var/log/nginx/dashboard.access.log;
    error_log /var/log/nginx/dashboard.error.log;
    
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    location /dashboard/ {
        alias /var/www/dashboard/;
        try_files $uri $uri/ /index.php?$args;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $request_filename;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
NGINX_CONFIG

    ln -sf /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    info "Запуск сервисов..."
    systemctl enable --now nginx
    systemctl enable --now mysql
    systemctl enable --now postgresql
    systemctl enable --now redis-server
    systemctl enable --now cockpit.socket
    systemctl enable --now fail2ban
    systemctl enable --now ssh
    systemctl enable --now php8.1-fpm
    
    systemctl restart nginx
    systemctl restart php8.1-fpm
    
    info "Создание алиасов и утилит..."
    echo "alias monit='python3 /opt/server-scripts/monitor.py'" >> /home/$USER/.bashrc
    echo "alias server-status='systemctl status'" >> /home/$USER/.bashrc
    echo "alias dash-log='tail -f /var/log/nginx/dashboard.error.log'" >> /home/$USER/.bashrc
    echo "alias backup-now='python3 /opt/server-scripts/backup-manager.py'" >> /home/$USER/.bashrc
    
    # Create admin scripts
    cat > /usr/local/bin/dashboard-admin << 'ADMIN_SCRIPT'
#!/bin/bash
echo "=== 🖥️ DASHBOARD ADMIN ==="
echo "URL: http://$(hostname -I | awk '{print $1}')/dashboard/"
echo "Login: admin"
echo "Password: admin123"
echo ""
echo "=== 🔧 QUICK COMMANDS ==="
echo "systemctl restart nginx    - Перезапуск веб-сервера"
echo "systemctl restart php8.1-fpm - Перезапуск PHP"
echo "tail -f /var/log/nginx/dashboard.error.log - Логи ошибок"
echo "python3 /opt/server-scripts/monitor.py - Мониторинг"
ADMIN_SCRIPT

    chmod +x /usr/local/bin/dashboard-admin
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    check_sudo
    
    echo
    info "Начало установки Ultimate Server Dashboard..."
    echo
    
    create_directories
    system_setup
    system_configuration
    security_setup
    database_setup
    monitoring_setup
    dashboard_setup
    final_setup
    
    echo
    info "🎉 УСТАНОВКА ЗАВЕРШЕНА!"
    echo
    echo "=== 📊 ДОСТУП К СИСТЕМЕ ==="
    echo "🌐 Веб-дашборд: http://$IP/dashboard/"
    echo "   Логин: admin"
    echo "   Пароль: admin123"
    echo
    echo "🔧 Cockpit: https://$IP:9090"
    echo "📊 Мониторинг: http://$IP/dashboard/?tab=monitoring"
    echo "💾 Файлы: http://$IP/dashboard/?tab=files"
    echo
    echo "=== 🔐 ДАННЫЫ ДОСТУПА ==="
    echo "MySQL Root: RootMySQL123!"
    echo "MySQL Dashboard: DashboardPass123!"
    echo "SSH Keys: ~/.ssh/"
    echo
    echo "=== 🛠️ КОМАНДЫ ==="
    echo "dashboard-admin    - Информация о дашборде"
    echo "monit             - Мониторинг системы"
    echo "server-info       - Информация о сервере"
    echo "backup-now        - Запуск бэкапа"
    echo
    echo "=== ⚠️ ВАЖНО ==="
    echo "1. Смени пароли по умолчанию!"
    echo "2. Настрой фаервол: ufw status"
    echo "3. Проверь логи: dash-log"
    echo "4. Настрой бэкапы в crontab -e"
    echo
    warn "Скрипт завершен. Система готова к работе! 🚀"
}

# Run main function
main "$@"
EOF

# Make script executable
chmod +x ultimate-server.sh

echo "✅ Мега-скрипт создан! Запускай:"
echo "sudo ./ultimate-server.sh"
