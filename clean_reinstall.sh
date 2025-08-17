#!/bin/bash

# Creative Energy Complete Clean Reinstall Script
# Web Server와 App Server를 완전히 제거하고 재설치하는 스크립트
# 사용법: sudo bash clean_reinstall.sh

set -e  # 오류 발생 시 스크립트 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

info() {
    echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
   error "이 스크립트는 root 권한으로 실행되어야 합니다."
   exit 1
fi

# 현재 디렉토리 확인
CURRENT_DIR=$(pwd)
if [[ ! -f "$CURRENT_DIR/web-server/install_web_server.sh" ]] || [[ ! -f "$CURRENT_DIR/app-server/install_app_server.sh" ]]; then
    error "ceweb 루트 디렉토리에서 실행해주세요."
    error "web-server/install_web_server.sh와 app-server/install_app_server.sh가 있는 디렉토리여야 합니다."
    exit 1
fi

log "================================================================"
log "Creative Energy Complete Clean Reinstall"
log "================================================================"
log ""
log "🔄 이 스크립트는 다음 작업을 수행합니다:"
log "1. 기존 Web Server 완전 제거"
log "2. 기존 App Server 완전 제거" 
log "3. Web Server 재설치"
log "4. App Server 재설치"
log "5. 시스템 연결 테스트"
log ""
warn "⚠️  모든 기존 설정과 데이터가 제거됩니다!"
warn "⚠️  DB 서버는 영향받지 않습니다 (데이터 유지됨)"
echo ""

# 사용자 확인
read -p "정말로 완전한 Clean Reinstall을 진행하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "재설치 작업이 취소되었습니다."
    exit 0
fi

echo ""
log "🧹 Clean Reinstall 작업을 시작합니다..."
echo ""

# 1. Web Server 제거
log "================================================================"
log "1단계: Web Server 제거"
log "================================================================"

if [[ -f "$CURRENT_DIR/web-server/uninstall_web_server.sh" ]]; then
    info "Web Server uninstall 스크립트 실행 중..."
    cd "$CURRENT_DIR/web-server"
    
    # 자동 응답을 위한 입력 준비 (모두 y로 응답)
    echo -e "y\ny\ny\ny\ny" | bash uninstall_web_server.sh
    
    log "✅ Web Server 제거 완료"
else
    warn "Web Server uninstall 스크립트를 찾을 수 없습니다. 수동 정리를 진행합니다..."
    
    # 수동 정리
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    dnf remove -y nginx 2>/dev/null || true
    rm -rf /etc/nginx /var/log/nginx /var/cache/nginx 2>/dev/null || true
    
    log "✅ Web Server 수동 정리 완료"
fi

cd "$CURRENT_DIR"

# 2. App Server 제거
log ""
log "================================================================"
log "2단계: App Server 제거"
log "================================================================"

if [[ -f "$CURRENT_DIR/app-server/uninstall_app_server.sh" ]]; then
    info "App Server uninstall 스크립트 실행 중..."
    cd "$CURRENT_DIR/app-server"
    
    # 자동 응답을 위한 입력 준비 (모두 y로 응답)
    echo -e "y\ny\ny\ny\ny\ny" | bash uninstall_app_server.sh
    
    log "✅ App Server 제거 완료"
else
    warn "App Server uninstall 스크립트를 찾을 수 없습니다. 수동 정리를 진행합니다..."
    
    # 수동 정리
    sudo -u rocky pm2 kill 2>/dev/null || true
    systemctl stop pm2-rocky 2>/dev/null || true
    systemctl disable pm2-rocky 2>/dev/null || true
    rm -f /etc/systemd/system/pm2-rocky.service 2>/dev/null || true
    systemctl daemon-reload
    
    log "✅ App Server 수동 정리 완료"
fi

cd "$CURRENT_DIR"

# 3. 시스템 정리 및 대기
log ""
log "================================================================"
log "3단계: 시스템 정리 및 대기"
log "================================================================"

log "시스템 정리 중..."
dnf clean all >/dev/null 2>&1 || true
systemctl daemon-reload

log "서비스 정리를 위해 5초 대기..."
sleep 5

# 4. Web Server 재설치
log ""
log "================================================================"
log "4단계: Web Server 재설치"
log "================================================================"

if [[ -f "$CURRENT_DIR/web-server/install_web_server.sh" ]]; then
    info "Web Server install 스크립트 실행 중..."
    cd "$CURRENT_DIR/web-server"
    
    # 웹서버 설치 실행
    bash install_web_server.sh
    
    if [[ $? -eq 0 ]]; then
        log "✅ Web Server 재설치 완료"
    else
        error "❌ Web Server 재설치 실패"
        exit 1
    fi
else
    error "Web Server install 스크립트를 찾을 수 없습니다: $CURRENT_DIR/web-server/install_web_server.sh"
    exit 1
fi

cd "$CURRENT_DIR"

# 5. App Server 재설치
log ""
log "================================================================"
log "5단계: App Server 재설치"
log "================================================================"

if [[ -f "$CURRENT_DIR/app-server/install_app_server.sh" ]]; then
    info "App Server install 스크립트 실행 중..."
    cd "$CURRENT_DIR/app-server"
    
    # 앱서버 설치 실행
    bash install_app_server.sh
    
    if [[ $? -eq 0 ]]; then
        log "✅ App Server 재설치 완료"
    else
        error "❌ App Server 재설치 실패"
        exit 1
    fi
else
    error "App Server install 스크립트를 찾을 수 없습니다: $CURRENT_DIR/app-server/install_app_server.sh"
    exit 1
fi

cd "$CURRENT_DIR"

# 6. 시스템 연결 테스트
log ""
log "================================================================"
log "6단계: 시스템 연결 테스트"
log "================================================================"

log "서비스 시작을 위해 10초 대기..."
sleep 10

# Web Server 테스트
log "Web Server 테스트 중..."
if systemctl is-active --quiet nginx; then
    if curl -f -s http://localhost >/dev/null 2>&1; then
        log "✅ Web Server 정상 동작"
    else
        warn "⚠️ Web Server가 실행 중이지만 HTTP 응답이 없습니다"
    fi
else
    error "❌ Web Server(Nginx)가 실행되지 않습니다"
fi

# App Server 테스트
log "App Server 테스트 중..."
if sudo -u rocky pm2 list 2>/dev/null | grep -q "online"; then
    if curl -f -s http://localhost:3000/health >/dev/null 2>&1; then
        log "✅ App Server 정상 동작"
    else
        warn "⚠️ App Server가 실행 중이지만 API 응답이 없습니다"
    fi
else
    error "❌ App Server(PM2)가 실행되지 않습니다"
fi

# API 프록시 테스트
log "API 프록시 테스트 중..."
if curl -f -s http://localhost/health >/dev/null 2>&1; then
    log "✅ API 프록시 정상 동작"
else
    warn "⚠️ API 프록시 연결에 문제가 있습니다"
fi

# 7. 최종 결과 및 정보
log ""
log "================================================================"
log "Creative Energy Complete Clean Reinstall 완료!"
log "================================================================"
log ""
log "🎉 재설치 결과:"
log "- ✅ Web Server (Nginx): 재설치 완료"
log "- ✅ App Server (Node.js + PM2): 재설치 완료"
log "- ✅ 시스템 구성: 3-Tier Architecture"
log ""
log "🌐 서비스 접속 정보:"
log "- 메인 웹사이트: http://$(hostname -I | awk '{print $1}')/"
log "- API 서버: http://$(hostname -I | awk '{print $1}'):3000/health"
log "- API 프록시: http://$(hostname -I | awk '{print $1}')/health"
log ""
log "🔧 서비스 상태 확인 명령어:"
log "- Web Server: systemctl status nginx"
log "- App Server: sudo -u rocky pm2 status"
log "- 전체 연결: curl http://localhost/api/orders/products"
log ""
log "📁 디렉토리 구조:"
log "- Web 파일: /home/rocky/ceweb/"
log "- App 파일: /home/rocky/ceweb/"
log "- 로그 파일: /var/log/nginx/, ~/.pm2/logs/"
log ""
log "🔄 Load Balancer 환경:"
log "- VM 정보: /home/rocky/ceweb/vm-info.json"
log "- 서버 상태: 웹페이지에서 서버정보 아이콘 클릭"
log ""
info "Clean Reinstall이 성공적으로 완료되었습니다!"
log "================================================================"