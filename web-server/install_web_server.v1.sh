#!/bin/bash

# Creative Energy Web Server Installation Script
# Rocky Linux 9.4 Web Server 설치 스크립트 (Nginx만)
# 사용법: sudo bash install_web_server.sh

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

log "Creative Energy Web Server 설치를 시작합니다..."
log "서버 역할: 정적 파일 서빙 + API 프록시 (www.cesvc.net, www.creative-energy.net)"

# 1. 시스템 업데이트
log "시스템 업데이트 중..."
dnf update -y
dnf upgrade -y
dnf install -y epel-release
dnf install -y wget curl git vim nano htop net-tools

# 2. 방화벽 설정 생략 (firewalld 불필요)
log "방화벽 설정 생략 - firewalld 사용하지 않음"

# 3. Nginx 설치
log "Nginx 웹서버 설치 중..."
dnf install -y nginx
systemctl start nginx
systemctl enable nginx

# 4. rocky 사용자 및 Web 디렉토리 설정
WEB_DIR="/home/rocky/ceweb"
log "rocky 사용자 설정 및 웹 디렉토리 생성: $WEB_DIR"

# rocky 사용자가 없으면 생성
useradd -m -s /bin/bash rocky || echo "rocky 사용자가 이미 존재합니다"
usermod -aG wheel rocky

mkdir -p $WEB_DIR
chown -R rocky:rocky $WEB_DIR
chmod -R 755 $WEB_DIR

# 5. Nginx 설정 파일 생성
log "Nginx 설정 파일 생성 중..."

cat > /etc/nginx/conf.d/creative-energy.conf << 'EOF'
server {
    listen 80 default_server;
    server_name www.cesvc.net www.creative-energy.net _;
    
    # 정적 파일 서빙 (HTML, CSS, JS, 이미지 등)
    location / {
        root /home/rocky/ceweb;
        index index.html;
        try_files $uri $uri/ /index.html;
        
        # 정적 파일 캐싱
        location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # API 요청을 App Server로 프록시
    location /api/ {
        proxy_pass http://app.cesvc.net:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # App Server 연결 타임아웃 설정
        proxy_connect_timeout 10s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
        
        # 네트워크 지연 대응
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries 2;
    }
    
    # 헬스체크 엔드포인트
    location /health {
        proxy_pass http://app.cesvc.net:3000/health;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_connect_timeout 5s;
        proxy_send_timeout 5s;
        proxy_read_timeout 5s;
    }
    
    # 보안 헤더
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # 로그 설정
    access_log /var/log/nginx/creative-energy-access.log;
    error_log /var/log/nginx/creative-energy-error.log;
}
EOF

# 6. Nginx 설정 테스트
log "Nginx 설정 테스트 중..."
nginx -t

# 7. 기본 서버 블록 비활성화 (프록시 충돌 방지)
log "기본 서버 블록 비활성화 중..."
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
sed -i '/^    server {/,/^    }/s/^/#/' /etc/nginx/nginx.conf

# 8. Nginx 재시작
log "Nginx 재시작 중..."
systemctl restart nginx

# 9. SELinux 설정
log "SELinux 설정 중..."
if command -v getenforce &> /dev/null && getenforce | grep -q "Enforcing"; then
    log "SELinux가 활성화되어 있습니다. 웹 서버 접근 권한을 설정합니다..."
    
    # Nginx가 사용자 홈 디렉토리의 컨텐츠를 읽을 수 있도록 허용
    setsebool -P httpd_read_user_content on
    
    # Nginx가 앱서버로 네트워크 연결을 할 수 있도록 허용
    setsebool -P httpd_can_network_connect on
    
    # 웹 디렉토리의 SELinux 컨텍스트 복원
    restorecon -Rv $WEB_DIR
    
    log "✅ SELinux 설정 완료"
else
    log "SELinux가 비활성화되어 있거나 설치되지 않았습니다."
fi

# 10. 최종 권한 설정
log "웹 디렉토리 권한 설정 중..."
chmod 755 /home/rocky  # 홈 디렉토리 접근 권한
chmod -R 755 $WEB_DIR
chown -R rocky:rocky $WEB_DIR
log "✅ 권한 설정 완료"

# 11. App Server 연결 테스트 스크립트 생성
log "App Server 연결 테스트 스크립트 생성 중..."

cat > /root/test_app_server.sh << 'EOF'
#!/bin/bash

echo "=== App Server 연결 테스트 ==="
echo "App 서버: app.cesvc.net:3000"
echo "시간: $(date)"
echo ""

# 1. 네트워크 연결 테스트
echo "1. 네트워크 연결 테스트:"
if ping -c 3 app.cesvc.net &>/dev/null; then
    echo "✅ 네트워크 연결 성공"
else
    echo "❌ 네트워크 연결 실패"
    exit 1
fi

# 2. 포트 연결 테스트
echo ""
echo "2. 포트 연결 테스트:"
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/app.cesvc.net/3000" 2>/dev/null; then
    echo "✅ 포트 3000 연결 성공"
else
    echo "❌ 포트 3000 연결 실패"
    echo "   App Server가 실행 중인지 확인해주세요."
    exit 1
fi

# 3. API 응답 테스트
echo ""
echo "3. API 응답 테스트:"
if curl -f -s http://app.cesvc.net:3000/health >/dev/null; then
    echo "✅ API 헬스체크 성공"
    curl -s http://app.cesvc.net:3000/health | head -3
else
    echo "❌ API 응답 실패"
fi

echo ""
echo "=== 연결 테스트 완료 ==="
EOF

chmod +x /root/test_app_server.sh

# 12. 설치 완료 메시지
log "================================================================"
log "Creative Energy Web Server 설치가 완료되었습니다!"
log "================================================================"
log ""
log "🏗️ 설치된 구성:"
log "- Web Server: Rocky Linux 9.4 + Nginx"
log "- 도메인: www.cesvc.net, www.creative-energy.net"
log "- 정적 파일 디렉토리: $WEB_DIR"
log ""
log "📋 다음 단계를 진행해주세요:"
log ""
log "1. 정적 파일 업로드:"
log "   HTML, CSS, JS, 이미지 파일을 $WEB_DIR 에 업로드하세요"
log "   예: scp -r /local/html-files/* user@server:$WEB_DIR/"
log ""
log "2. App Server 연결 테스트:"
log "   /root/test_app_server.sh"
log ""
log "3. DNS 설정 확인:"
log "   www.cesvc.net → 이 서버 IP"
log "   www.creative-energy.net → 이 서버 IP"
log "   app.cesvc.net → App Server IP"
log ""
log "🔧 유틸리티 명령어:"
log "- Nginx 상태: systemctl status nginx"
log "- Nginx 설정 테스트: nginx -t"
log "- Nginx 재시작: systemctl restart nginx"
log "- 로그 확인: tail -f /var/log/nginx/creative-energy-*.log"
log "- SELinux 상태 확인: getenforce"
log ""
log "🔌 열린 포트: 80, 443"
log "📁 웹 디렉토리: $WEB_DIR"
log "📝 Nginx 설정: /etc/nginx/conf.d/creative-energy.conf"
log ""
log "⚠️  중요 사항:"
log "- 이 서버는 정적 파일 서빙과 API 프록시 역할만 수행합니다"
log "- 실제 API 처리는 app.cesvc.net:3000에서 수행됩니다"
log "- App Server가 실행 중이어야 API 요청이 정상 동작합니다"
log "- SELinux 설정이 자동으로 구성되어 권한 문제 없이 동작합니다"
log ""
log "================================================================"