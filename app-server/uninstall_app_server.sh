#!/bin/bash
# ==============================================================================
# Copyright (c) 2025 Stan H. All rights reserved.
#
# This software and its source code are the exclusive property of Stan H.
#
# Use is strictly limited to 2025 SCPv2 Advance training and education only.
# Any reproduction, modification, distribution, or other use beyond this scope is
# strictly prohibited without prior written permission from the copyright holder.
#
# Unauthorized use may lead to legal action under applicable law.
#
# Contact: ars4mundus@gmail.com
# ==============================================================================

# Creative Energy App Server Uninstall Script
# Rocky Linux 9.4 App Server 완전 제거 스크립트 (Node.js + PM2 + 애플리케이션)
# 사용법: sudo bash uninstall_app_server.sh

set -e  # 오류 발생 시 스크립트 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
   error "이 스크립트는 root 권한으로 실행되어야 합니다."
   exit 1
fi

# 변수 설정
APP_USER="rocky"
APP_DIR="/home/$APP_USER/ceweb"

log "================================================================"
log "Creative Energy App Server 제거를 시작합니다..."
log "================================================================"
log ""
log "⚠️  경고: 이 스크립트는 다음 항목들을 완전히 제거합니다:"
log "- Node.js 런타임 환경"
log "- PM2 프로세스 매니저 및 모든 프로세스"
log "- Creative Energy 애플리케이션 디렉토리 (/home/$APP_USER/ceweb)"
log "- VM Bootstrap 스크립트"
log "- 환경 변수 파일 (.env)"
log "- 로그 파일들"
log ""

# 사용자 확인
read -p "정말로 App Server를 제거하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "제거 작업이 취소되었습니다."
    exit 0
fi

log "App Server 제거 작업을 시작합니다..."

# 1. PM2 프로세스 중지 및 제거
log "1. PM2 프로세스 중지 및 제거..."
if id "$APP_USER" &>/dev/null; then
    # PM2 프로세스 목록 확인
    if sudo -u $APP_USER pm2 list 2>/dev/null | grep -q "creative-energy-api"; then
        log "Creative Energy API 프로세스 중지 중..."
        sudo -u $APP_USER pm2 stop creative-energy-api 2>/dev/null || true
        sudo -u $APP_USER pm2 delete creative-energy-api 2>/dev/null || true
        log "✅ Creative Energy API 프로세스 제거됨"
    else
        log "Creative Energy API 프로세스가 실행되지 않음"
    fi
    
    # 모든 PM2 프로세스 제거
    if sudo -u $APP_USER pm2 list 2>/dev/null | grep -v "No processes" >/dev/null; then
        echo ""
        warn "다른 PM2 프로세스가 실행 중입니다:"
        sudo -u $APP_USER pm2 list 2>/dev/null || true
        echo ""
        read -p "모든 PM2 프로세스를 제거하시겠습니까? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo -u $APP_USER pm2 kill 2>/dev/null || true
            log "✅ 모든 PM2 프로세스 제거됨"
        else
            log "다른 PM2 프로세스는 유지됨"
        fi
    else
        sudo -u $APP_USER pm2 kill 2>/dev/null || true
        log "✅ PM2 데몬 종료됨"
    fi
    
    # PM2 startup 설정 제거
    sudo -u $APP_USER pm2 unstartup systemd 2>/dev/null || true
    log "✅ PM2 자동 시작 설정 제거됨"
else
    log "$APP_USER 사용자가 존재하지 않습니다"
fi

# 2. systemd PM2 서비스 제거
log "2. systemd PM2 서비스 제거..."
PM2_SERVICE="pm2-$APP_USER"

if systemctl list-units --type=service | grep -q "$PM2_SERVICE"; then
    if systemctl is-active --quiet "$PM2_SERVICE"; then
        systemctl stop "$PM2_SERVICE"
        log "✅ $PM2_SERVICE 서비스 중지됨"
    fi
    
    if systemctl is-enabled --quiet "$PM2_SERVICE" 2>/dev/null; then
        systemctl disable "$PM2_SERVICE"
        log "✅ $PM2_SERVICE 서비스 자동 시작 비활성화됨"
    fi
    
    # 서비스 파일 제거
    if [ -f "/etc/systemd/system/$PM2_SERVICE.service" ]; then
        rm -f "/etc/systemd/system/$PM2_SERVICE.service"
        systemctl daemon-reload
        log "✅ $PM2_SERVICE 서비스 파일 제거됨"
    fi
else
    log "$PM2_SERVICE 서비스가 존재하지 않습니다"
fi

# 3. Node.js 애플리케이션 디렉토리 제거
log "3. Node.js 애플리케이션 디렉토리 제거..."
if [ -d "$APP_DIR" ]; then
    # 중요한 파일 확인
    echo ""
    warn "애플리케이션 디렉토리에 중요한 데이터가 있을 수 있습니다:"
    warn "$APP_DIR"
    if [ -f "$APP_DIR/.env" ]; then
        warn "- 환경 변수 파일 (.env)"
    fi
    if [ -d "$APP_DIR/files" ]; then
        warn "- 업로드된 파일들 (/files)"
    fi
    if [ -d "$APP_DIR/logs" ]; then
        warn "- 로그 파일들 (/logs)"
    fi
    echo ""
    
    read -p "백업 없이 애플리케이션 디렉토리를 완전히 제거하시겠습니까? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$APP_DIR"
        log "✅ 애플리케이션 디렉토리 제거됨: $APP_DIR"
    else
        log "애플리케이션 디렉토리 제거를 건너뛰었습니다: $APP_DIR"
    fi
else
    log "애플리케이션 디렉토리가 존재하지 않습니다: $APP_DIR"
fi

# 4. PM2 글로벌 설치 제거
log "4. PM2 글로벌 패키지 제거..."
if command -v npm &> /dev/null; then
    if npm list -g pm2 2>/dev/null | grep -q "pm2@"; then
        npm uninstall -g pm2
        log "✅ PM2 글로벌 패키지 제거됨"
    else
        log "PM2 글로벌 패키지가 설치되어 있지 않습니다"
    fi
else
    log "npm이 설치되어 있지 않습니다"
fi

# 5. Node.js 제거
log "5. Node.js 제거..."
echo ""
warn "Node.js를 제거하면 다른 Node.js 애플리케이션에 영향을 줄 수 있습니다."
echo ""
read -p "Node.js를 완전히 제거하시겠습니까? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # NodeSource repository에서 설치된 Node.js 제거
    if rpm -q nodejs &>/dev/null; then
        dnf remove -y nodejs npm
        log "✅ Node.js 패키지 제거됨"
    else
        log "Node.js 패키지가 설치되어 있지 않습니다"
    fi
    
    # NodeSource repository 제거
    if [ -f "/etc/yum.repos.d/nodesource-el9.repo" ]; then
        rm -f /etc/yum.repos.d/nodesource-el9.repo
        log "✅ NodeSource repository 제거됨"
    fi
    
    # Node.js 관련 디렉토리 제거
    NODE_DIRS=(
        "/usr/lib/node_modules"
        "/usr/share/doc/nodejs"
        "/var/cache/npm"
    )
    
    for dir in "${NODE_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir"
            log "✅ 제거됨: $dir"
        fi
    done
else
    log "Node.js 제거를 건너뛰었습니다"
fi

# 6. 사용자별 Node.js 설정 제거
log "6. 사용자별 Node.js 설정 제거..."
if id "$APP_USER" &>/dev/null; then
    USER_NODE_DIRS=(
        "/home/$APP_USER/.npm"
        "/home/$APP_USER/.pm2"
        "/home/$APP_USER/.node_repl_history"
        "/home/$APP_USER/.config/yarn"
    )
    
    for dir in "${USER_NODE_DIRS[@]}"; do
        if [ -d "$dir" ] || [ -f "$dir" ]; then
            rm -rf "$dir"
            log "✅ 제거됨: $dir"
        fi
    done
    
    log "✅ $APP_USER 사용자의 Node.js 설정 제거됨"
fi

# 7. VM Bootstrap 스크립트 제거
log "7. VM Bootstrap 스크립트 제거..."
BOOTSTRAP_FILES=(
    "/usr/local/bin/bootstrap_app_vm.sh"
)

for file in "${BOOTSTRAP_FILES[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file"
        log "✅ 제거됨: $file"
    else
        log "존재하지 않음: $file"
    fi
done

# rc.local에서 bootstrap 관련 라인 제거
if [ -f "/etc/rc.local" ] && grep -q "bootstrap_app_vm.sh" "/etc/rc.local"; then
    sed -i '/bootstrap_app_vm.sh/d' /etc/rc.local
    log "✅ rc.local에서 Bootstrap 스크립트 제거됨"
fi

# 8. 테스트 및 모니터링 스크립트 제거
log "8. 테스트 및 모니터링 스크립트 제거..."
if id "$APP_USER" &>/dev/null; then
    TEST_SCRIPTS=(
        "/home/$APP_USER/test_db_connection.sh"
        "/home/$APP_USER/monitor_app.sh"
    )
    
    for script in "${TEST_SCRIPTS[@]}"; do
        if [ -f "$script" ]; then
            rm -f "$script"
            log "✅ 제거됨: $script"
        fi
    done
fi

# 9. Object Storage 설정 파일 제거 (S3 App Server 전용)
log "9. Object Storage 설정 파일 제거..."
if id "$APP_USER" &>/dev/null; then
    S3_CONFIG_FILES=(
        "/home/$APP_USER/ceweb/credentials.json"
        "/home/$APP_USER/ceweb/bucket_id.json"
        "/home/$APP_USER/ceweb/s3-config.json"
    )
    
    for s3_file in "${S3_CONFIG_FILES[@]}"; do
        if [ -f "$s3_file" ]; then
            rm -f "$s3_file"
            log "✅ Object Storage 설정 제거됨: $s3_file"
        fi
    done
fi

# 10. 환경 변수 파일 제거
log "10. 환경 변수 파일 제거..."
if id "$APP_USER" &>/dev/null; then
    ENV_FILES=(
        "/home/$APP_USER/.ceweb/.env"
        "/home/$APP_USER/.ceweb"
    )
    
    for env_file in "${ENV_FILES[@]}"; do
        if [ -f "$env_file" ] || [ -d "$env_file" ]; then
            rm -rf "$env_file"
            log "✅ 제거됨: $env_file"
        fi
    done
fi

# 11. 방화벽 설정 정리
log "11. 방화벽 설정 확인..."
if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
    echo ""
    warn "방화벽에서 App Server 포트(3000)를 제거할지 선택하세요:"
    warn "다른 Node.js 서비스가 실행 중인 경우 제거하지 마세요."
    echo ""
    read -p "방화벽에서 포트 3000을 제거하시겠습니까? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        firewall-cmd --permanent --remove-port=3000/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        log "✅ 방화벽에서 포트 3000 제거됨"
    else
        log "방화벽 설정 변경을 건너뛰었습니다"
    fi
else
    log "방화벽이 비활성화되어 있거나 설치되지 않았습니다"
fi

# 12. 사용자 권한 정리 (rocky 사용자는 유지)
log "12. 사용자 권한 정리..."
if id "$APP_USER" &>/dev/null; then
    echo ""
    warn "$APP_USER 사용자가 존재합니다."
    warn "이 사용자는 다른 서비스에서 사용될 수 있으므로 자동으로 제거하지 않습니다."
    warn "필요한 경우 다음 명령어로 수동 제거하세요:"
    warn "  userdel -r $APP_USER"
    echo ""
fi

# 13. 임시 파일 및 캐시 정리
log "13. 임시 파일 및 캐시 정리..."
dnf clean all >/dev/null 2>&1 || true
log "✅ 패키지 캐시 정리됨"

# 14. 프로세스 확인
log "14. 관련 프로세스 확인..."
if pgrep -f "node.*server.js" >/dev/null; then
    warn "⚠️ Node.js 서버 프로세스가 여전히 실행 중입니다"
    warn "수동으로 종료하세요: pkill -f 'node.*server.js'"
elif pgrep -f "PM2" >/dev/null; then
    warn "⚠️ PM2 관련 프로세스가 여전히 실행 중입니다"
    warn "수동으로 종료하세요: pkill -f PM2"
else
    log "✅ Node.js/PM2 프로세스가 완전히 종료됨"
fi

# 15. 포트 사용 상태 확인
log "15. 포트 사용 상태 확인..."
if netstat -tulpn 2>/dev/null | grep ":3000 " >/dev/null; then
    warn "⚠️ 포트 3000이 여전히 사용 중입니다"
    warn "다음 명령어로 확인하세요:"
    warn "  netstat -tulpn | grep :3000"
else
    log "✅ App Server 포트(3000)가 해제됨"
fi

# 제거 완료 메시지
log ""
log "================================================================"
log "Creative Energy App Server 제거가 완료되었습니다!"
log "================================================================"
log ""
log "🗑️ 제거된 구성요소:"
log "- ✅ PM2 프로세스 매니저 및 모든 프로세스"
log "- ✅ Node.js 런타임 (선택적)"
log "- ✅ Creative Energy 애플리케이션 디렉토리 (선택적)"
log "- ✅ VM Bootstrap 스크립트"
log "- ✅ 테스트 및 모니터링 스크립트"
log "- ✅ Object Storage 설정 파일 (credentials.json, bucket_id.json)"
log "- ✅ 환경 변수 파일"
log "- ✅ 사용자별 Node.js 설정"
log ""
log "🔧 시스템 상태:"
log "- PM2 프로세스: 제거됨"
log "- Node.js 서버: 중지됨"
log "- App Server 포트(3000): 해제됨"
log "- $APP_USER 사용자: 유지됨 (수동 제거 가능)"
log ""
log "🚀 재설치 방법:"
log "표준 3Tier 환경:"
log "1. 애플리케이션 파일을 서버에 업로드"
log "2. sudo bash install_app_server.sh"
log ""
log "Object Storage 환경:"
log "1. 애플리케이션 파일을 서버에 업로드"
log "2. bucket_id.json 파일 설정 후 업로드"
log "3. sudo bash install_app_server_s3.sh"
log ""
log "⚠️ 참고사항:"
log "- $APP_USER 사용자는 다른 서비스에서 사용될 수 있으므로 유지되었습니다"
log "- 필요한 경우 'userdel -r $APP_USER'로 수동 제거하세요"
log "- Node.js는 다른 애플리케이션 영향을 고려하여 선택적으로 제거되었습니다"
log "- 방화벽 설정은 다른 서비스 영향을 고려하여 선택적으로 제거되었습니다"
log ""
log "🔄 DB 서버 연결:"
log "- DB 서버는 영향받지 않으며 계속 실행됩니다"
log "- 재설치 시 기존 데이터베이스를 그대로 사용할 수 있습니다"
log ""
log "================================================================"