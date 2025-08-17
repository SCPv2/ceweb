#!/bin/bash

# Creative Energy Web Server Uninstall Script
# Rocky Linux 9.4 Web Server 완전 제거 스크립트 (Nginx + 설정 파일)
# 사용법: sudo bash uninstall_web_server.sh

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

log "================================================================"
log "Creative Energy Web Server 제거를 시작합니다..."
log "================================================================"
log ""
log "⚠️  경고: 이 스크립트는 다음 항목들을 완전히 제거합니다:"
log "- Nginx 웹서버 및 모든 설정 파일"
log "- Creative Energy 웹 디렉토리 (/home/rocky/ceweb)"
log "- VM Bootstrap 스크립트"
log "- 로그 파일들"
log ""

# 사용자 확인
read -p "정말로 Web Server를 제거하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "제거 작업이 취소되었습니다."
    exit 0
fi

log "Web Server 제거 작업을 시작합니다..."

# 1. Nginx 서비스 중지 및 비활성화
log "1. Nginx 서비스 중지 및 비활성화..."
if systemctl is-active --quiet nginx; then
    systemctl stop nginx
    log "✅ Nginx 서비스 중지됨"
else
    log "Nginx 서비스가 이미 중지되어 있습니다"
fi

if systemctl is-enabled --quiet nginx 2>/dev/null; then
    systemctl disable nginx
    log "✅ Nginx 서비스 자동 시작 비활성화됨"
else
    log "Nginx 서비스 자동 시작이 이미 비활성화되어 있습니다"
fi

# 2. Nginx 패키지 제거
log "2. Nginx 패키지 제거..."
if rpm -q nginx &>/dev/null; then
    dnf remove -y nginx
    log "✅ Nginx 패키지 제거됨"
else
    log "Nginx 패키지가 설치되어 있지 않습니다"
fi

# 3. Nginx 설정 파일 및 디렉토리 제거
log "3. Nginx 설정 파일 제거..."
NGINX_DIRS=(
    "/etc/nginx"
    "/var/log/nginx"
    "/var/cache/nginx"
    "/usr/share/nginx"
    "/var/lib/nginx"
)

for dir in "${NGINX_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        log "✅ 제거됨: $dir"
    else
        log "존재하지 않음: $dir"
    fi
done

# 4. Creative Energy 웹 디렉토리 제거
log "4. Creative Energy 웹 디렉토리 제거..."
WEB_DIR="/home/rocky/ceweb"

if [ -d "$WEB_DIR" ]; then
    # 사용자 데이터 백업 여부 확인
    echo ""
    warn "웹 디렉토리에 중요한 사용자 파일이 있을 수 있습니다:"
    warn "$WEB_DIR"
    echo ""
    read -p "백업 없이 완전히 제거하시겠습니까? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$WEB_DIR"
        log "✅ 웹 디렉토리 제거됨: $WEB_DIR"
    else
        log "웹 디렉토리 제거를 건너뛰었습니다: $WEB_DIR"
    fi
else
    log "웹 디렉토리가 존재하지 않습니다: $WEB_DIR"
fi

# 5. VM Bootstrap 스크립트 제거
log "5. VM Bootstrap 스크립트 제거..."
BOOTSTRAP_FILES=(
    "/usr/local/bin/bootstrap_web_vm.sh"
    "/etc/rc.local"
)

for file in "${BOOTSTRAP_FILES[@]}"; do
    if [ -f "$file" ]; then
        if [[ "$file" == "/etc/rc.local" ]]; then
            # rc.local에서 bootstrap 관련 라인만 제거
            if grep -q "bootstrap_web_vm.sh" "$file"; then
                sed -i '/bootstrap_web_vm.sh/d' "$file"
                log "✅ rc.local에서 Bootstrap 스크립트 제거됨"
            else
                log "rc.local에 Bootstrap 스크립트가 없습니다"
            fi
        else
            rm -f "$file"
            log "✅ 제거됨: $file"
        fi
    else
        log "존재하지 않음: $file"
    fi
done

# 6. 테스트 스크립트 제거
log "6. 테스트 스크립트 제거..."
TEST_SCRIPTS=(
    "/root/test_app_server.sh"
)

for script in "${TEST_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        rm -f "$script"
        log "✅ 제거됨: $script"
    else
        log "존재하지 않음: $script"
    fi
done

# 7. 방화벽 설정 초기화 (필요한 경우)
log "7. 방화벽 설정 확인..."
if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
    # HTTP/HTTPS 포트 제거 (다른 서비스에서 사용할 수 있으므로 주의깊게)
    echo ""
    warn "방화벽에서 HTTP/HTTPS 포트를 제거할지 선택하세요:"
    warn "다른 웹 서비스가 실행 중인 경우 제거하지 마세요."
    echo ""
    read -p "방화벽에서 HTTP(80)/HTTPS(443) 포트를 제거하시겠습니까? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        firewall-cmd --permanent --remove-service=http 2>/dev/null || true
        firewall-cmd --permanent --remove-service=https 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        log "✅ 방화벽에서 HTTP/HTTPS 포트 제거됨"
    else
        log "방화벽 설정 변경을 건너뛰었습니다"
    fi
else
    log "방화벽이 비활성화되어 있거나 설치되지 않았습니다"
fi

# 8. SELinux 설정 초기화
log "8. SELinux 설정 초기화..."
if command -v getenforce &> /dev/null && getenforce | grep -q "Enforcing"; then
    # 웹 서버 관련 SELinux boolean 초기화
    setsebool -P httpd_read_user_content off 2>/dev/null || true
    setsebool -P httpd_can_network_connect off 2>/dev/null || true
    log "✅ SELinux 웹서버 설정 초기화됨"
else
    log "SELinux가 비활성화되어 있거나 설치되지 않았습니다"
fi

# 9. 사용자 권한 정리 (rocky 사용자는 유지)
log "9. 사용자 권한 정리..."
# rocky 사용자는 다른 용도로 사용될 수 있으므로 제거하지 않음
# 필요한 경우에만 수동으로 제거하도록 안내
if id "rocky" &>/dev/null; then
    echo ""
    warn "rocky 사용자가 존재합니다."
    warn "이 사용자는 다른 서비스에서 사용될 수 있으므로 자동으로 제거하지 않습니다."
    warn "필요한 경우 다음 명령어로 수동 제거하세요:"
    warn "  userdel -r rocky"
    echo ""
fi

# 10. 임시 파일 및 캐시 정리
log "10. 임시 파일 및 캐시 정리..."
dnf clean all >/dev/null 2>&1 || true
log "✅ 패키지 캐시 정리됨"

# 11. 프로세스 확인
log "11. 관련 프로세스 확인..."
if pgrep -f "nginx" >/dev/null; then
    warn "⚠️ Nginx 프로세스가 여전히 실행 중입니다"
    warn "수동으로 종료하세요: pkill -f nginx"
else
    log "✅ Nginx 프로세스가 완전히 종료됨"
fi

# 12. 포트 사용 상태 확인
log "12. 포트 사용 상태 확인..."
if netstat -tulpn 2>/dev/null | grep -E ":80 |:443 " >/dev/null; then
    warn "⚠️ 포트 80 또는 443이 여전히 사용 중입니다"
    warn "다음 명령어로 확인하세요:"
    warn "  netstat -tulpn | grep -E ':80 |:443 '"
else
    log "✅ 웹서버 포트(80, 443)가 해제됨"
fi

# 제거 완료 메시지
log ""
log "================================================================"
log "Creative Energy Web Server 제거가 완료되었습니다!"
log "================================================================"
log ""
log "🗑️ 제거된 구성요소:"
log "- ✅ Nginx 웹서버 (패키지 및 모든 설정)"
log "- ✅ Creative Energy 웹 디렉토리 (선택적)"
log "- ✅ VM Bootstrap 스크립트"
log "- ✅ 테스트 스크립트"
log "- ✅ 로그 파일"
log "- ✅ SELinux 웹서버 설정"
log ""
log "🔧 시스템 상태:"
log "- Nginx 서비스: 제거됨"
log "- 웹서버 포트(80, 443): 해제됨"
log "- rocky 사용자: 유지됨 (수동 제거 가능)"
log ""
log "🚀 재설치 방법:"
log "1. 웹 파일을 서버에 업로드"
log "2. sudo bash install_web_server.sh"
log ""
log "⚠️ 참고사항:"
log "- rocky 사용자는 다른 서비스에서 사용될 수 있으므로 유지되었습니다"
log "- 필요한 경우 'userdel -r rocky'로 수동 제거하세요"
log "- 방화벽 설정은 다른 서비스 영향을 고려하여 선택적으로 제거되었습니다"
log ""
log "================================================================"