#!/bin/bash

# Creative Energy API 404 오류 자동 수정 스크립트
# 사용법: sudo bash fix_api_404.sh

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $1${NC}"
}

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
   error "이 스크립트는 root 권한으로 실행되어야 합니다."
   exit 1
fi

echo "================================================"
echo "Creative Energy API 404 오류 자동 수정"
echo "================================================"

# 1. 현재 상태 확인
log "1. 현재 시스템 상태 확인 중..."

# Nginx 상태 확인
if systemctl is-active --quiet nginx; then
    log "✅ Nginx 실행 중"
else
    warn "Nginx가 중지되어 있습니다. 시작합니다..."
    systemctl start nginx
fi

# 2. Nginx 설정 파일 수정
log "2. Nginx 프록시 설정 수정 중..."

NGINX_CONF="/etc/nginx/conf.d/creative-energy.conf"
if [ -f "$NGINX_CONF" ]; then
    # 백업 생성
    cp "$NGINX_CONF" "$NGINX_CONF.backup.$(date +%Y%m%d_%H%M%S)"
    log "✅ 설정 파일 백업 완료"
    
    # 잘못된 proxy_pass 설정 수정
    if grep -q "proxy_pass.*3000/;" "$NGINX_CONF"; then
        sed -i 's|proxy_pass http://app.cesvc.net:3000/;|proxy_pass http://app.cesvc.net:3000;|g' "$NGINX_CONF"
        log "✅ Nginx 프록시 설정 수정 완료"
        
        # 수정 결과 확인
        echo "수정된 설정:"
        grep -A 1 -B 1 "proxy_pass.*3000" "$NGINX_CONF" | head -3
    else
        log "Nginx 프록시 설정이 이미 올바릅니다"
    fi
    
    # Nginx 설정 테스트
    log "3. Nginx 설정 검증 중..."
    if nginx -t; then
        log "✅ Nginx 설정 문법 정상"
    else
        error "❌ Nginx 설정 문법 오류 - 백업 파일로 복구하세요"
        echo "복구 명령어: cp $NGINX_CONF.backup.* $NGINX_CONF"
        exit 1
    fi
else
    error "Nginx 설정 파일을 찾을 수 없습니다: $NGINX_CONF"
    error "먼저 웹서버 설치 스크립트를 실행하세요"
    exit 1
fi

# 4. App Server 상태 확인 및 시작
log "4. App Server 상태 확인 중..."

if pgrep -f "node.*server.js" >/dev/null || pgrep -f "PM2" >/dev/null; then
    log "✅ App Server 실행 중"
else
    warn "App Server가 중지되어 있습니다. 시작을 시도합니다..."
    
    # rocky 사용자 확인
    if id "rocky" &>/dev/null; then
        # ceweb 디렉토리 확인
        if [ -d "/home/rocky/ceweb" ]; then
            cd /home/rocky/ceweb
            
            # PM2로 앱 시작
            if [ -f "ecosystem.config.js" ] && [ -f "server.js" ]; then
                sudo -u rocky pm2 start ecosystem.config.js 2>/dev/null || {
                    warn "PM2 시작 실패, 직접 Node.js 실행을 시도합니다..."
                    sudo -u rocky nohup node server.js > logs/app.log 2>&1 &
                    sleep 2
                }
                log "✅ App Server 시작 시도 완료"
            else
                warn "App Server 파일이 없습니다 (server.js 또는 ecosystem.config.js)"
            fi
        else
            warn "/home/rocky/ceweb 디렉토리가 없습니다"
        fi
    else
        warn "rocky 사용자가 없습니다"
    fi
fi

# 5. 서비스 재시작
log "5. Nginx 설정 적용 중..."
systemctl reload nginx
sleep 2

# 6. 연결 테스트
log "6. API 연결 테스트 중..."

echo ""
echo "=== 연결 테스트 결과 ==="

# Health Check 테스트
echo -n "Health API 테스트: "
if curl -f -s --connect-timeout 5 http://localhost/health >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 성공${NC}"
else
    echo -e "${RED}❌ 실패${NC}"
fi

# Products API 테스트  
echo -n "Products API 테스트: "
if curl -f -s --connect-timeout 5 http://localhost/api/orders/products >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 성공${NC}"
    PRODUCTS_COUNT=$(curl -s http://localhost/api/orders/products | grep -o '"products":\[.*\]' | grep -o '\[.*\]' | grep -o '{}' | wc -l)
    echo "  → 상품 수: $PRODUCTS_COUNT"
else
    echo -e "${RED}❌ 실패${NC}"
    
    # 추가 진단
    echo ""
    echo "=== 추가 진단 ==="
    
    echo -n "포트 3000 사용 여부: "
    if netstat -tulpn 2>/dev/null | grep ":3000 " >/dev/null; then
        echo -e "${GREEN}✅ 사용 중${NC}"
    else
        echo -e "${RED}❌ 사용 안됨${NC}"
    fi
    
    echo -n "앱서버 직접 연결: "
    if curl -f -s --connect-timeout 5 http://localhost:3000/health >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 성공 (Nginx 프록시 문제)${NC}"
    else
        echo -e "${RED}❌ 실패 (App Server 문제)${NC}"
    fi
fi

echo ""
echo "=== 프로세스 상태 ==="
echo "Nginx: $(systemctl is-active nginx)"
echo "App Server 프로세스:"
ps aux | grep -E "(nginx|node|PM2)" | grep -v grep | head -3

echo ""
echo "================================================"
log "수정 작업 완료!"
echo "================================================"

echo ""
echo "🔧 수동 확인 명령어:"
echo "curl http://localhost/health"
echo "curl http://localhost/api/orders/products"
echo ""
echo "🚨 문제가 지속되면:"
echo "1. bash diagnose_api_404.sh   # 상세 진단"
echo "2. sudo systemctl restart nginx"
echo "3. pm2 restart all"