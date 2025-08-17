#!/bin/bash

# Creative Energy CORS Public IP 허용 스크립트
# 환경변수 ALLOWED_ORIGINS를 주석 처리하여 Public IP 허용 활성화
# 사용법: sudo bash fix_cors_public_ip.sh

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
echo "Creative Energy CORS Public IP 허용 활성화"
echo "================================================"

# 1. App Server 디렉토리 확인
APP_SERVER_DIR="/home/rocky/ceweb"
ENV_FILE="$APP_SERVER_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    error ".env 파일을 찾을 수 없습니다: $ENV_FILE"
    exit 1
fi

log "✅ .env 파일 찾음: $ENV_FILE"

# 2. .env 파일 백업
log "환경설정 파일 백업 중..."
cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
log "✅ .env 파일 백업 완료"

# 3. 현재 ALLOWED_ORIGINS 설정 확인
log "현재 CORS 설정 확인 중..."
if grep -q "^ALLOWED_ORIGINS=" "$ENV_FILE"; then
    CURRENT_ORIGINS=$(grep "^ALLOWED_ORIGINS=" "$ENV_FILE" | cut -d'=' -f2)
    log "현재 ALLOWED_ORIGINS: $CURRENT_ORIGINS"
    
    # ALLOWED_ORIGINS 주석 처리
    log "ALLOWED_ORIGINS 환경변수를 주석 처리 중..."
    sed -i 's/^ALLOWED_ORIGINS=/#ALLOWED_ORIGINS=/' "$ENV_FILE"
    log "✅ ALLOWED_ORIGINS 주석 처리 완료"
    
elif grep -q "^#ALLOWED_ORIGINS=" "$ENV_FILE"; then
    log "✅ ALLOWED_ORIGINS가 이미 주석 처리되어 있습니다"
else
    warn "ALLOWED_ORIGINS 설정을 찾을 수 없습니다"
fi

# 4. Public IP 허용 설명 추가
log "Public IP 허용 설명 추가 중..."
cat >> "$ENV_FILE" << 'EOF'

# CORS Public IP 허용 설정
# ALLOWED_ORIGINS가 주석 처리되면 모든 Public IP가 자동으로 허용됩니다
# 필요시 특정 도메인만 허용하려면 위의 ALLOWED_ORIGINS 주석을 해제하세요
CORS_PUBLIC_IP_ENABLED=true
EOF

log "✅ Public IP 허용 설정 추가 완료"

# 5. App Server 재시작
log "App Server 재시작 중..."
cd "$APP_SERVER_DIR"

# PM2로 재시작
if pgrep -f "PM2" >/dev/null; then
    sudo -u rocky pm2 restart creative-energy-api 2>/dev/null || {
        warn "PM2 재시작 실패, 전체 재시작 시도..."
        sudo -u rocky pm2 restart all
    }
    log "✅ PM2 프로세스 재시작 완료"
else
    warn "PM2를 통해 실행되지 않고 있습니다. 수동 재시작이 필요합니다."
    echo "다음 명령어로 재시작하세요:"
    echo "cd $APP_SERVER_DIR && pm2 start ecosystem.config.js"
fi

sleep 3

# 6. API 연결 테스트
log "API 연결 테스트 중..."

echo ""
echo "=== 연결 테스트 결과 ==="

# Health Check 테스트
echo -n "Health API 테스트: "
if curl -f -s --connect-timeout 10 http://localhost:3000/health >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 성공${NC}"
else
    echo -e "${RED}❌ 실패${NC}"
fi

# POST 요청 테스트 (Public IP Origin으로)
echo -n "POST 요청 테스트 (Public IP): "
POST_RESULT=$(curl -s -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -H "Origin: http://123.41.33.78" \
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

# 다른 Public IP로도 테스트
echo -n "POST 요청 테스트 (다른 Public IP): "
POST_RESULT2=$(curl -s -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -H "Origin: http://123.41.34.120" \
    -d '{"test": true}' \
    http://localhost:3000/api/orders/create \
    -o /dev/null 2>/dev/null)

if [[ "$POST_RESULT2" != "403" ]]; then
    echo -e "${GREEN}✅ CORS 통과 (응답 코드: $POST_RESULT2)${NC}"
else
    echo -e "${RED}❌ 여전히 403 Forbidden${NC}"
fi

echo ""
echo "=== 현재 설정 상태 ==="
echo "환경변수 ALLOWED_ORIGINS: $(grep -E "^#?ALLOWED_ORIGINS=" "$ENV_FILE" || echo "설정 없음")"
echo "Public IP 허용: $(grep "CORS_PUBLIC_IP_ENABLED" "$ENV_FILE" || echo "설정 없음")"

echo ""
echo "=== 프로세스 상태 ===" 
echo "App Server 프로세스:"
ps aux | grep -E "(node|PM2)" | grep -v grep | head -3

echo ""
echo "================================================"
log "Public IP 허용 설정 완료!"
echo "================================================"

echo ""
echo "🔧 테스트 명령어:"
echo "curl -H 'Origin: http://123.41.33.78' -X POST http://localhost:3000/api/orders/create"
echo "curl -H 'Origin: http://123.41.34.120' -X PUT http://localhost:3000/api/orders/admin/products/1"
echo ""
echo "🚨 여전히 403 오류가 발생하면:"
echo "1. pm2 logs creative-energy-api  # 서버 로그 확인"
echo "2. 브라우저에서 Ctrl+F5로 캐시 클리어"
echo "3. 다른 Public IP로 테스트"
echo ""
echo "💡 특정 도메인만 허용하려면:"
echo "1. .env 파일에서 #ALLOWED_ORIGINS= 라인의 주석 해제"
echo "2. pm2 restart creative-energy-api"