#!/bin/bash

# Creative Energy Media 경로 Nginx 설정 수정 스크립트
# 현재 실행 중인 서버의 nginx 설정에 /media/ 경로 추가
# 사용법: sudo bash fix_media_nginx.sh

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
echo "Creative Energy Media 경로 Nginx 설정 수정"
echo "================================================"

# 1. Nginx 설정 파일 확인
NGINX_CONF="/etc/nginx/conf.d/creative-energy.conf"
log "1. Nginx 설정 파일 확인 중..."

if [ ! -f "$NGINX_CONF" ]; then
    error "Nginx 설정 파일을 찾을 수 없습니다: $NGINX_CONF"
    exit 1
fi

log "✅ Nginx 설정 파일 찾음: $NGINX_CONF"

# 2. 설정 파일 백업
log "2. 설정 파일 백업 중..."
cp "$NGINX_CONF" "$NGINX_CONF.backup.$(date +%Y%m%d_%H%M%S)"
log "✅ 설정 파일 백업 완료"

# 3. /media/ 경로 설정 확인 및 추가
log "3. /media/ 경로 설정 확인 중..."

if grep -q "location /media/" "$NGINX_CONF"; then
    log "✅ /media/ 경로 설정이 이미 존재합니다"
else
    log "/media/ 경로 설정을 추가 중..."
    
    # # Health Check 엔드포인트 섹션 다음에 /media/ 설정 추가
    sed -i '/# Health Check.*App Load Balancer/,/}/a\    \
    # Media 폴더 - 이미지 파일 서빙용\
    location /media/ {\
        root /home/rocky/ceweb;\
        expires 1y;\
        add_header Cache-Control "public, immutable";\
        \
        # 이미지 파일만 허용\
        location ~* /media/.*\\.(jpg|jpeg|png|gif|ico|svg|webp)$ {\
            expires 1y;\
            add_header Cache-Control "public, immutable";\
        }\
        \
        # 실행 파일 및 기타 파일 차단\
        location ~* /media/.*\\.(php|php3|php4|php5|phtml|pl|py|jsp|asp|sh|cgi|exe|bat|com|txt|md)$ {\
            deny all;\
            return 403;\
        }\
    }' "$NGINX_CONF"
    
    log "✅ /media/ 경로 설정 추가 완료"
fi

# 4. /media/img/ 디렉토리 확인 및 생성
log "4. /media/img/ 디렉토리 확인 중..."
MEDIA_DIR="/home/rocky/ceweb/media"
IMG_DIR="/home/rocky/ceweb/media/img"

if [ ! -d "$MEDIA_DIR" ]; then
    mkdir -p "$MEDIA_DIR"
    chown rocky:rocky "$MEDIA_DIR"
    chmod 755 "$MEDIA_DIR"
    log "✅ /media/ 디렉토리 생성 완료"
fi

if [ ! -d "$IMG_DIR" ]; then
    mkdir -p "$IMG_DIR"
    chown rocky:rocky "$IMG_DIR"
    chmod 755 "$IMG_DIR"
    log "✅ /media/img/ 디렉토리 생성 완료"
else
    log "✅ /media/img/ 디렉토리가 이미 존재합니다"
fi

# 5. 이미지 파일이 있는지 확인
log "5. 이미지 파일 확인 중..."
if find "/home/rocky/ceweb" -maxdepth 2 -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.gif" | grep -q .; then
    log "이미지 파일을 발견했습니다. /media/img/ 로 이동이 필요할 수 있습니다."
    
    echo ""
    echo "발견된 이미지 파일들:"
    find "/home/rocky/ceweb" -maxdepth 2 -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.gif"
    echo ""
    
    read -p "이미지 파일들을 /media/img/로 이동하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # media 디렉토리 직하위의 이미지 파일들을 img로 이동
        find "/home/rocky/ceweb" -maxdepth 2 \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.gif" -o -name "*.ico" -o -name "*.svg" \) -not -path "*/media/img/*" -exec mv {} "$IMG_DIR/" \;
        log "✅ 이미지 파일 이동 완료"
    else
        log "이미지 파일 이동을 건너뜁니다"
    fi
else
    log "이미지 파일을 찾을 수 없습니다"
fi

# 6. 파일 권한 설정
log "6. 파일 권한 설정 중..."
chown -R rocky:rocky "/home/rocky/ceweb/media"
chmod -R 755 "/home/rocky/ceweb/media"
log "✅ 파일 권한 설정 완료"

# 7. Nginx 설정 테스트
log "7. Nginx 설정 검증 중..."
if nginx -t; then
    log "✅ Nginx 설정 문법 정상"
else
    error "❌ Nginx 설정 문법 오류"
    echo "복구 명령어: cp $NGINX_CONF.backup.* $NGINX_CONF"
    exit 1
fi

# 8. Nginx 설정 적용
log "8. Nginx 설정 적용 중..."
systemctl reload nginx
sleep 2
log "✅ Nginx 설정 적용 완료"

# 9. 테스트 이미지 파일 생성 (테스트용)
log "9. 테스트 이미지 파일 생성 중..."
TEST_IMG="$IMG_DIR/test.png"
if [ ! -f "$TEST_IMG" ]; then
    # 1x1 투명 PNG 생성 (base64 디코딩)
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" | base64 -d > "$TEST_IMG"
    chown rocky:rocky "$TEST_IMG"
    chmod 644 "$TEST_IMG"
    log "✅ 테스트 이미지 파일 생성 완료"
fi

# 10. 연결 테스트
log "10. /media/img/ 경로 접근 테스트 중..."

echo ""
echo "=== 연결 테스트 결과 ==="

# 로컬 테스트
echo -n "/media/img/test.png 테스트: "
if curl -f -s --connect-timeout 5 "http://localhost/media/img/test.png" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 성공${NC}"
else
    echo -e "${RED}❌ 실패${NC}"
fi

# 실제 이미지 파일 테스트 (존재하는 경우)
if find "$IMG_DIR" -name "*.png" -o -name "*.jpg" | head -1 | grep -q .; then
    SAMPLE_IMG=$(find "$IMG_DIR" -name "*.png" -o -name "*.jpg" | head -1 | sed "s|/home/rocky/ceweb||")
    echo -n "실제 이미지 파일 테스트$SAMPLE_IMG: "
    if curl -f -s --connect-timeout 5 "http://localhost$SAMPLE_IMG" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 성공${NC}"
    else
        echo -e "${RED}❌ 실패${NC}"
    fi
fi

echo ""
echo "=== 디렉토리 구조 확인 ==="
echo "미디어 디렉토리:"
ls -la "/home/rocky/ceweb/media/" 2>/dev/null || echo "디렉토리 없음"
echo ""
echo "이미지 디렉토리:"
ls -la "$IMG_DIR" 2>/dev/null || echo "디렉토리 없음"

echo ""
echo "=== 현재 Nginx 설정 확인 ===" 
echo "/media/ 경로 설정:"
grep -A 15 "location /media/" "$NGINX_CONF" || echo "설정 없음"

echo ""
echo "================================================"
log "Media 경로 Nginx 설정 수정 완료!"
echo "================================================"

echo ""
echo "🔧 테스트 명령어:"
echo "curl -I http://localhost/media/img/test.png"
echo "curl -I http://$(hostname -I | awk '{print $1}')/media/img/test.png"
echo ""
echo "🚨 여전히 403 오류가 발생하면:"
echo "1. 파일 존재 확인: ls -la /home/rocky/ceweb/media/img/"
echo "2. Nginx 오류 로그: sudo tail -f /var/log/nginx/ceweb_error.log"
echo "3. SELinux 확인: getenforce"
echo "4. 파일 권한 재설정: sudo chown -R rocky:rocky /home/rocky/ceweb/media && sudo chmod -R 755 /home/rocky/ceweb/media"