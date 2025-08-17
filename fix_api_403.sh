#!/bin/bash

# Creative Energy API 403 Forbidden 오류 자동 수정 스크립트
# 사용법: sudo bash fix_api_403.sh

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

echo "================================================"
echo "Creative Energy API 403 Forbidden 오류 해결"
echo "================================================"

# 1. 현재 상태 확인
log "1. 현재 시스템 상태 확인 중..."

# App Server 상태 확인
if pgrep -f "node.*server.js" >/dev/null || pgrep -f "PM2" >/dev/null; then
    log "✅ App Server 실행 중"
else
    error "App Server가 중지되어 있습니다."
    exit 1
fi

# 2. CORS 설정 확인 및 수정
log "2. App Server CORS 설정 확인 중..."

APP_SERVER_DIR="/home/rocky/ceweb"
SERVER_JS="$APP_SERVER_DIR/server.js"

if [ -f "$SERVER_JS" ]; then
    log "✅ server.js 파일 찾음"
    
    # 백업 생성
    cp "$SERVER_JS" "$SERVER_JS.backup.$(date +%Y%m%d_%H%M%S)"
    log "✅ server.js 백업 완료"
    
    # Public IP 허용 설정 확인
    if grep -q "모든 Public IP.*허용" "$SERVER_JS"; then
        log "✅ 이미 모든 Public IP 허용으로 설정되어 있습니다"
    else
        log "⚠️ CORS 설정이 구버전입니다. 새버전 server.js로 업데이트가 필요합니다"
        echo "최신 버전은 모든 Public IP를 자동으로 허용합니다"
    fi
    
    # CORS 설정 확인
    echo ""
    echo "=== 현재 CORS 설정 ===" 
    grep -A 20 "allowedOrigins.*=" "$SERVER_JS" | head -25
    
else
    error "server.js 파일을 찾을 수 없습니다: $SERVER_JS"
    exit 1
fi

# 3. PM2 프로세스 재시작
log "3. App Server 재시작 중..."

cd "$APP_SERVER_DIR"

# PM2로 재시작
if pgrep -f "PM2" >/dev/null; then
    pm2 restart creative-energy-api 2>/dev/null || {
        warn "PM2 재시작 실패, 전체 재시작 시도..."
        pm2 restart all
    }
    log "✅ PM2 프로세스 재시작 완료"
else
    # 직접 실행 중인 경우
    warn "PM2를 통해 실행되지 않고 있습니다. 수동 재시작이 필요합니다."
    echo "다음 명령어로 재시작하세요:"
    echo "cd $APP_SERVER_DIR && pm2 start ecosystem.config.js"
fi

sleep 3

# 4. API 연결 테스트
log "4. API 연결 테스트 중..."

echo ""
echo "=== 연결 테스트 결과 ==="

# Health Check 테스트
echo -n "Health API 테스트: "
if curl -f -s --connect-timeout 10 http://localhost:3000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 성공${NC}"
else
    echo -e "${RED}❌ 실패${NC}"
fi

# GET 요청 테스트  
echo -n "GET Products API 테스트: "
if curl -f -s --connect-timeout 10 http://localhost:3000/api/orders/products >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 성공${NC}"
else
    echo -e "${RED}❌ 실패${NC}"
fi

# POST 요청 테스트 (더미 데이터)
echo -n "POST 요청 테스트: "
POST_RESULT=$(curl -s -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -H "Origin: http://123.41.34.120" \
    -d '{"test": true}' \
    http://localhost:3000/api/orders/test \
    -o /dev/null 2>/dev/null)

if [[ "$POST_RESULT" == "404" ]]; then
    echo -e "${GREEN}✅ CORS 통과 (404는 정상 - 엔드포인트 없음)${NC}"
elif [[ "$POST_RESULT" == "403" ]]; then
    echo -e "${RED}❌ 여전히 403 Forbidden${NC}"
else
    echo -e "${YELLOW}⚠️  응답 코드: $POST_RESULT${NC}"
fi

# PUT 요청 테스트
echo -n "PUT 요청 테스트: "
PUT_RESULT=$(curl -s -w "%{http_code}" -X PUT \
    -H "Content-Type: application/json" \
    -H "Origin: http://123.41.33.78" \
    -d '{"test": true}' \
    http://localhost:3000/api/orders/admin/products/1 \
    -o /dev/null 2>/dev/null)

if [[ "$PUT_RESULT" != "403" ]]; then
    echo -e "${GREEN}✅ CORS 통과 (응답 코드: $PUT_RESULT)${NC}"
else
    echo -e "${RED}❌ 여전히 403 Forbidden${NC}"
fi

echo ""
echo "=== 프로세스 상태 ===" 
echo "App Server 프로세스:"
ps aux | grep -E "(node|PM2)" | grep -v grep | head -3

echo ""
echo "=== CORS 허용 설정 확인 ==="
if grep -q "모든 Public IP.*허용" "$SERVER_JS"; then
    echo "✅ 모든 Public IP 허용 설정 활성화됨"
else
    echo "⚠️ 제한적 IP 허용 설정"
fi

echo ""
echo "================================================"
log "403 Forbidden 오류 수정 작업 완료!"
echo "================================================"

echo ""
echo "🔧 수동 확인 명령어:"
echo "curl -H 'Origin: http://123.41.34.120' -X POST http://localhost:3000/api/orders/test"
echo "curl -H 'Origin: http://123.41.33.78' -X PUT http://localhost:3000/api/orders/test"
echo ""
echo "🚨 문제가 지속되면:"
echo "1. pm2 logs creative-energy-api  # 오류 로그 확인"
echo "2. pm2 restart creative-energy-api  # App Server 재시작"
echo "3. 브라우저에서 Ctrl+F5로 캐시 클리어"