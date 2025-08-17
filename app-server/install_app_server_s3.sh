#!/bin/bash

# Creative Energy App Server Installation Script (S3 Enhanced)
# Rocky Linux 9.4 App Server 설치 스크립트 (Node.js + API + Samsung Cloud Platform S3)
# 사용법: sudo bash install_app_server_s3.sh

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

log "Creative Energy App Server (S3 Enhanced) 설치를 시작합니다..."
log "서버 역할: API 처리 + 비즈니스 로직 + Samsung Cloud Platform S3 (app.cesvc.net)"
log "DB 서버: db.cesvc.net:2866"

# 1. 시스템 업데이트
log "시스템 업데이트 중..."
dnf update -y
dnf upgrade -y
dnf install -y epel-release
dnf install -y wget curl git vim nano htop net-tools telnet postgresql

# 2. 방화벽 설정 생략 (firewalld 불필요)
log "방화벽 설정 생략 - firewalld 사용하지 않음"

# 3. Node.js 설치
log "Node.js 20.x 설치 중..."
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs

NODE_VERSION=$(node --version)
NPM_VERSION=$(npm --version)
log "Node.js 설치 완료: $NODE_VERSION"
log "NPM 버전: $NPM_VERSION"

# 4. PM2 설치
log "PM2 프로세스 매니저 설치 중..."
npm install -g pm2

# 5. PostgreSQL 클라이언트 설치 (서버 제외)
log "PostgreSQL 클라이언트 설치 중..."
PSQL_VERSION=$(psql --version)
log "PostgreSQL 클라이언트 설치 완료: $PSQL_VERSION"

# 6. DB 서버 연결 테스트
log "DB 서버 연결 테스트 중..."
DB_HOST="db.cesvc.net"
DB_PORT="2866"

if ping -c 3 $DB_HOST &>/dev/null; then
    log "✅ DB 서버 네트워크 연결 성공: $DB_HOST"
else
    warn "⚠️  DB 서버 네트워크 연결 확인 필요: $DB_HOST"
fi

if timeout 10 bash -c "cat < /dev/null > /dev/tcp/$DB_HOST/$DB_PORT" 2>/dev/null; then
    log "✅ DB 서버 포트 연결 성공: $DB_HOST:$DB_PORT"
else
    warn "⚠️  DB 서버 포트 연결 확인 필요: $DB_HOST:$DB_PORT"
fi

# 7. rocky 사용자 생성
APP_USER="rocky"
log "애플리케이션 사용자 '$APP_USER' 생성 중..."

if id "$APP_USER" &>/dev/null; then
    warn "사용자 '$APP_USER'가 이미 존재합니다."
else
    useradd -m -s /bin/bash $APP_USER
    usermod -aG wheel $APP_USER
    log "사용자 '$APP_USER' 생성 완료"
fi

# 8. 애플리케이션 디렉토리 생성
APP_DIR="/home/$APP_USER/ceweb/app-server"
FILES_DIR="/home/$APP_USER/ceweb/files"
AUDITION_DIR="/home/$APP_USER/ceweb/files/audition"

log "애플리케이션 디렉토리 생성: $APP_DIR"
sudo -u $APP_USER mkdir -p $APP_DIR
sudo -u $APP_USER mkdir -p $APP_DIR/logs

log "파일 업로드 디렉토리 생성: $FILES_DIR"
sudo -u $APP_USER mkdir -p $AUDITION_DIR
chmod -R 755 $FILES_DIR
chown -R $APP_USER:$APP_USER $FILES_DIR
log "✅ 파일 업로드 디렉토리 생성 완료: $AUDITION_DIR"

# 9. JWT 키 생성
log "JWT Secret Key 생성 중..."
if command -v openssl &> /dev/null; then
    JWT_SECRET=$(openssl rand -hex 32)
    log "✅ JWT Secret Key 생성 완료 (64자)"
else
    warn "⚠️ OpenSSL이 설치되지 않았습니다. 기본 JWT 키를 사용합니다."
    JWT_SECRET="your_jwt_secret_key_minimum_32_characters_long_change_this_in_production"
fi

# 10. Public 도메인 입력 받기
log "CORS 허용 도메인 설정 중..."
echo ""
echo "================================================"
echo "Public 도메인 설정"
echo "================================================"
echo "이 App Server에 접근할 Public 도메인을 입력하세요."
echo "기본 허용 도메인: www.cesvc.net, www.creative-energy.net"
echo "추가로 허용할 도메인이 있다면 입력하세요 (없으면 Enter)."
echo ""
echo "예시: mysite.com 또는 subdomain.mysite.com"
echo -n "Public 도메인 입력: "

# 사용자 입력 받기 (30초 타임아웃)
read -t 30 CUSTOM_DOMAIN || CUSTOM_DOMAIN=""

# 기본 허용 도메인 목록
DEFAULT_ORIGINS="http://www.cesvc.net,https://www.cesvc.net,http://www.creative-energy.net,https://www.creative-energy.net"

# 사용자가 입력한 도메인 추가
if [[ -n "$CUSTOM_DOMAIN" ]]; then
    # 공백 제거 및 소문자 변환
    CUSTOM_DOMAIN=$(echo "$CUSTOM_DOMAIN" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    
    # http:// 또는 https:// 제거 (있다면)
    CUSTOM_DOMAIN=${CUSTOM_DOMAIN#http://}
    CUSTOM_DOMAIN=${CUSTOM_DOMAIN#https://}
    
    # 허용 도메인 목록에 추가
    ALLOWED_ORIGINS="$DEFAULT_ORIGINS,http://$CUSTOM_DOMAIN,https://$CUSTOM_DOMAIN"
    
    log "✅ 추가 Public 도메인 설정: $CUSTOM_DOMAIN"
else
    ALLOWED_ORIGINS="$DEFAULT_ORIGINS"
    log "기본 도메인만 사용합니다"
fi

log "CORS 허용 도메인 목록: $ALLOWED_ORIGINS"

# 11. 환경 설정 파일 생성
log "App Server용 환경 설정 파일 생성 중..."

cat > $APP_DIR/.env << EOF
# External Database Configuration
DB_HOST=db.cesvc.net
DB_PORT=2866
DB_NAME=cedb
DB_USER=ceadmin
DB_PASSWORD=ceadmin123!
DB_SSL=false

# Connection Pool Settings
DB_POOL_MIN=2
DB_POOL_MAX=10
DB_POOL_IDLE_TIMEOUT=30000
DB_POOL_CONNECTION_TIMEOUT=5000

# Server Configuration (App Server 전용)
PORT=3000
NODE_ENV=production
BIND_HOST=0.0.0.0

# CORS Configuration (허용 도메인 목록)
ALLOWED_ORIGINS=$ALLOWED_ORIGINS

# Security
JWT_SECRET=$JWT_SECRET

# Logging
LOG_LEVEL=info
EOF

chown $APP_USER:$APP_USER $APP_DIR/.env
chmod 600 $APP_DIR/.env

# 12. Samsung Cloud Platform Object Storage 인증 파일 템플릿 생성
log "Samsung Cloud Platform Object Storage 인증 파일 템플릿 생성 중..."

cat > $APP_DIR/credentials.json << 'EOF'
{
  "accessKeyId": "your-access-key-here",
  "secretAccessKey": "your-secret-key-here",
  "region": "kr-west1",
  "bucketName": "ceweb",
  "privateEndpoint": "https://object-store.private.kr-west1.e.samsungsdscloud.com",
  "publicEndpoint": "https://object-store.kr-west1.e.samsungsdscloud.com",
  "folders": {
    "media": "media/img",
    "audition": "files/audition"
  }
}
EOF

chown $APP_USER:$APP_USER $APP_DIR/credentials.json
chmod 600 $APP_DIR/credentials.json
log "✅ Samsung Cloud Platform 인증 파일 템플릿 생성: $APP_DIR/credentials.json"
warn "⚠️  실제 Samsung Cloud Platform 인증키를 입력해야 S3 기능이 작동합니다"

# 13. PM2 Ecosystem 설정 파일 생성
log "PM2 Ecosystem 설정 파일 생성 중..."

cat > $APP_DIR/ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'creative-energy-api',
    script: 'server.js',
    instances: 'max',
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: 3000,
      BIND_HOST: '0.0.0.0'
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    time: true,
    max_memory_restart: '1G',
    node_args: '--max_old_space_size=1024',
    
    restart_delay: 4000,
    max_restarts: 10,
    min_uptime: '10s'
  }]
};
EOF

chown $APP_USER:$APP_USER $APP_DIR/ecosystem.config.js

# 14. DB 연결 테스트 스크립트 생성
log "DB 연결 테스트 스크립트 생성 중..."

cat > /home/$APP_USER/test_db_connection.sh << 'EOF'
#!/bin/bash

echo "=== DB 서버 연결 테스트 ==="
echo "DB 서버: db.cesvc.net:2866"
echo "시간: $(date)"
echo ""

# 2. 포트 연결 테스트
echo ""
echo "2. 포트 연결 테스트:"
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/db.cesvc.net/2866" 2>/dev/null; then
    echo "✅ 포트 2866 연결 성공"
else
    echo "❌ 포트 2866 연결 실패"
    exit 1
fi

# 3. PostgreSQL 연결 테스트
echo ""
echo "3. PostgreSQL 연결 테스트 (계정 정보 필요):"
echo "   psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c \"SELECT 1;\""

echo ""
echo "=== 연결 테스트 완료 ==="
EOF

chown $APP_USER:$APP_USER /home/$APP_USER/test_db_connection.sh
chmod +x /home/$APP_USER/test_db_connection.sh

# 15. 앱 모니터링 스크립트 생성
cat > /home/$APP_USER/monitor_app.sh << 'EOF'
#!/bin/bash

echo "=== App Server 모니터링 ==="
echo "시간: $(date)"
echo ""

echo "1. 애플리케이션 상태:"
if pgrep -f "creative-energy-api" >/dev/null; then
    echo "✅ 애플리케이션 실행 중"
    pm2 status 2>/dev/null || echo "PM2 상태 확인 실패"
else
    echo "❌ 애플리케이션 중지됨"
fi

echo ""
echo "2. 포트 사용 상태:"
netstat -tulpn | grep :3000 || echo "포트 3000이 사용되지 않음"

echo ""
echo "3. 최근 로그:"
pm2 logs creative-energy-api --lines 5 2>/dev/null || echo "로그 확인 실패"

echo ""
echo "========================="
EOF

chown $APP_USER:$APP_USER /home/$APP_USER/monitor_app.sh
chmod +x /home/$APP_USER/monitor_app.sh

# 16. DB 연결 테스트 실행
log "DB 연결 테스트 실행 중..."
sudo -u $APP_USER /home/$APP_USER/test_db_connection.sh

# 17. 애플리케이션 코드 복사
log "애플리케이션 코드 복사 중..."
if [ -d "/home/$APP_USER/ceweb/app-server" ]; then
    log "✅ 소스 디렉토리 발견: /home/$APP_USER/ceweb/app-server"
    
    # app-server 디렉토리의 내용을 목적지로 복사
    sudo -u $APP_USER cp -r /home/$APP_USER/ceweb/app-server/* $APP_DIR/ 2>/dev/null || {
        warn "일부 파일 복사 실패. 수동으로 확인 필요."
    }
    
    # server.js 파일이 존재하는지 확인
    if [ -f "$APP_DIR/server.js" ]; then
        log "✅ server.js 파일 확인됨"
    else
        warn "⚠️ server.js 파일이 없습니다. 수동으로 업로드가 필요합니다."
    fi
else
    warn "⚠️ 애플리케이션 소스 디렉토리를 찾을 수 없습니다."
    warn "   다음 명령으로 수동 업로드하세요:"
    warn "   scp -r /local/app-server/* $APP_USER@$(hostname):$APP_DIR/"
fi

# 18. Node.js 의존성 설치
log "Node.js 의존성 설치 중..."
if [ -f "$APP_DIR/package.json" ]; then
    cd $APP_DIR
    sudo -u $APP_USER npm install
    
    if [ $? -eq 0 ]; then
        log "✅ npm install 완료"
        
        # Samsung Cloud Platform Object Storage용 AWS SDK 설치 (전체 패키지)
        log "Samsung Cloud Platform Object Storage용 AWS SDK 설치 중..."
        sudo -u $APP_USER npm install @aws-sdk/client-s3@^3.600.0
        sudo -u $APP_USER npm install @aws-sdk/s3-request-presigner@^3.600.0
        
        if [ $? -eq 0 ]; then
            log "✅ AWS SDK for S3 설치 완료 (Samsung Cloud Platform 호환)"
            log "   - @aws-sdk/client-s3@^3.600.0"
            log "   - @aws-sdk/s3-request-presigner@^3.600.0"
        else
            warn "⚠️ AWS SDK 설치 실패"
        fi
    else
        warn "⚠️ npm install 실패"
    fi
else
    warn "⚠️ package.json 파일이 없습니다."
fi

# 19. PM2로 애플리케이션 시작
log "PM2로 애플리케이션 시작 중..."
if [ -f "$APP_DIR/server.js" ] && [ -f "$APP_DIR/ecosystem.config.js" ]; then
    cd $APP_DIR
    sudo -u $APP_USER pm2 start ecosystem.config.js
    
    if [ $? -eq 0 ]; then
        log "✅ PM2 애플리케이션 시작 성공"
        
        # PM2 상태 확인
        sudo -u $APP_USER pm2 list
    else
        warn "⚠️ PM2 애플리케이션 시작 실패"
    fi
else
    warn "⚠️ server.js 또는 ecosystem.config.js 파일이 없습니다."
fi

# 20. VM 정보 파일 생성 (Load Balancer 환경용)
log "VM 정보 파일 생성 중..."

# 현재 VM 정보 수집
VM_HOSTNAME=$(hostname -s)
VM_IP=$(hostname -I | awk '{print $1}')
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# VM 번호 추출 (hostname에서 숫자 추출: appvm121r -> 1, appvm122r -> 2)
VM_NUMBER=""
if [[ $VM_HOSTNAME =~ appvm([0-9]+) ]]; then
    FULL_NUMBER=${BASH_REMATCH[1]}
    # 마지막 자리 숫자를 VM 번호로 사용
    VM_NUMBER="${FULL_NUMBER: -1}"
else
    VM_NUMBER="1"  # 기본값
fi

log "VM 정보: 호스트명=$VM_HOSTNAME, IP=$VM_IP, VM번호=$VM_NUMBER"

# vm-info.json 파일 생성 (App 서버용)
VM_INFO_FILE="$APP_DIR/vm-info.json"
cat > "$VM_INFO_FILE" << EOF
{
  "hostname": "$VM_HOSTNAME",
  "ip_address": "$VM_IP",
  "vm_number": "$VM_NUMBER",
  "server_type": "app-server",
  "load_balancer": {
    "name": "app.cesvc.net",
    "ip": "10.1.2.100",
    "policy": "Round Robin"
  },
  "cluster": {
    "servers": [
      {
        "hostname": "appvm121r",
        "ip": "10.1.2.121",
        "vm_number": "1"
      },
      {
        "hostname": "appvm122r", 
        "ip": "10.1.2.122",
        "vm_number": "2"
      }
    ]
  },
  "timestamp": "$CURRENT_TIME",
  "version": "1.0"
}
EOF

chmod 644 "$VM_INFO_FILE"
chown $APP_USER:$APP_USER "$VM_INFO_FILE"

log "✅ VM 정보 파일 생성 완료: $VM_INFO_FILE"

# 21. Samsung Cloud Platform Bootstrap 스크립트 설정
log "VM Bootstrap 스크립트 설정 중..."

BOOTSTRAP_SCRIPT="/home/$APP_USER/ceweb/app-server/bootstrap_app_vm.sh"
if [ -f "$BOOTSTRAP_SCRIPT" ]; then
    log "bootstrap_app_vm.sh 스크립트를 찾았습니다"
    
    # Bootstrap 스크립트를 시스템 위치로 복사
    cp "$BOOTSTRAP_SCRIPT" /usr/local/bin/
    chmod +x /usr/local/bin/bootstrap_app_vm.sh
    chown root:root /usr/local/bin/bootstrap_app_vm.sh
    
    # rc.local에 Bootstrap 스크립트 추가 (VM 부팅 시 자동 실행)
    if ! grep -q "bootstrap_app_vm.sh" /etc/rc.local 2>/dev/null; then
        echo '#!/bin/bash' > /etc/rc.local
        echo '/usr/local/bin/bootstrap_app_vm.sh' >> /etc/rc.local
        chmod +x /etc/rc.local
        log "✅ VM Bootstrap 스크립트 자동 실행 설정 완료"
    else
        log "Bootstrap 스크립트가 이미 rc.local에 설정되어 있습니다"
    fi
    
    log "✅ Samsung Cloud Platform Load Balancer 환경 설정 완료"
else
    warn "⚠️ bootstrap_app_vm.sh 스크립트를 찾을 수 없습니다: $BOOTSTRAP_SCRIPT"
fi

# 22. PM2 자동 시작 설정
log "PM2 자동 시작 설정 중..."
sudo -u $APP_USER pm2 startup systemd --user $APP_USER 2>/dev/null || {
    log "PM2 startup 설정을 위해 다음 명령을 실행하세요:"
    log "sudo su - $APP_USER"
    log "pm2 startup systemd"
    log "pm2 save"
}

if sudo -u $APP_USER pm2 save >/dev/null 2>&1; then
    log "✅ PM2 자동 시작 설정 완료"
else
    warn "⚠️ PM2 save 실패. 수동으로 'pm2 save' 실행 필요"
fi

# 23. 설치 완료 메시지
log "================================================================"
log "Creative Energy App Server (S3 Enhanced) 설치가 완료되었습니다!"
log "================================================================"
log ""
log "🏗️ 설치된 구성:"
log "- App Server: Rocky Linux 9.4 + Node.js $NODE_VERSION"
log "- DB 서버: db.cesvc.net:2866 (외부)"
log "- S3 저장소: Samsung Cloud Platform Object Storage"
log "- 서버 주소: app.cesvc.net:3000"
log ""
log "✅ 설치 및 설정 완료 상태:"
log ""
log "🔧 자동으로 완료된 작업:"
log "- ✅ DB 연결 테스트 성공"
log "- ✅ 애플리케이션 코드 복사"
log "- ✅ Node.js 의존성 설치 (npm install)"
log "- ✅ Samsung Cloud Platform Object Storage SDK 설치"
log "- ✅ S3 인증 파일 템플릿 생성"
log "- ✅ 파일 업로드 디렉토리 생성"
log "- ✅ PM2 애플리케이션 시작"
log "- ✅ PM2 자동 시작 설정"
log ""
log "🔐 생성된 JWT Secret Key:"
log "   $JWT_SECRET"
log "   (이 키는 $APP_DIR/.env 파일에 자동으로 설정되었습니다)"
log ""
log "🔑 Samsung Cloud Platform Object Storage 설정:"
log "   인증 파일: $APP_DIR/credentials.json"
log "   ⚠️  실제 Samsung Cloud Platform 인증키를 입력해야 S3 기능이 작동합니다!"
log ""
log "📊 현재 애플리케이션 상태:"
if sudo -u $APP_USER pm2 list | grep -q "creative-energy-api"; then
    log "- ✅ PM2 프로세스: 실행 중"
else
    log "- ❌ PM2 프로세스: 실행되지 않음"
fi

# API 엔드포인트 테스트
if curl -s http://localhost:3000/health >/dev/null 2>&1; then
    log "- ✅ API 서버: 응답 정상 (http://localhost:3000)"
elif curl -s http://localhost:3000/ >/dev/null 2>&1; then
    log "- ✅ API 서버: 기본 응답 정상 (http://localhost:3000)"
else
    log "- ⚠️ API 서버: 응답 확인 필요"
fi

log ""
log "🔧 유틸리티 스크립트:"
log "- DB 연결 테스트: sudo -u $APP_USER ~/test_db_connection.sh"
log "- 앱 모니터링: sudo -u $APP_USER ~/monitor_app.sh"
log ""
log "🔌 열린 포트: 3000"
log "👤 애플리케이션 사용자: $APP_USER"
log "📁 애플리케이션 경로: $APP_DIR"
log ""
log "🧪 API 엔드포인트 테스트 명령어:"
log "curl -X GET http://localhost:3000/health"
log "curl -X GET http://localhost:3000/api/s3/status"
log "curl -X GET http://localhost:3000/api/orders/products"
log ""
log "🌐 Samsung Cloud Platform Load Balancer 환경:"
log "- VM Bootstrap 자동 실행: VM 부팅 시 자동으로 Node.js 애플리케이션 시작"
log "- Server Status Icons: /health 엔드포인트에서 실시간 VM 정보 제공"
log "- VM 정보 파일: vm-info.json에서 VM 번호와 상태 정보 자동 생성"
log "- Load Balancer에서 Health Check를 통한 서버 상태 모니터링"
log ""
log "🔄 VM Bootstrap 수동 실행 (테스트용):"
log "/usr/local/bin/bootstrap_app_vm.sh"
log ""
log "📦 Samsung Cloud Platform Object Storage 기능:"
log "- S3 호환 스토리지 업로드/다운로드"
log "- Presigned URL 생성 (보안 접근)"
log "- 상품 이미지 및 오디션 파일 관리"
log "- CORS 자동 설정"
log ""
log "⚠️  중요 사항:"
log "- credentials.json 파일에 실제 Samsung Cloud Platform 인증키 입력 필수"
log "- S3 기능을 사용하려면 인증키 설정 후 PM2 재시작 필요"
log "- 이 서버는 API 처리만 담당합니다 (정적 파일 서빙 없음)"
log "- Web Server(www.cesvc.net)에서 이 서버로 API 요청을 프록시합니다"
log "- DB는 별도 서버(db.cesvc.net:2866)에 위치합니다"
log "- /health 엔드포인트에서 서버 식별 정보(VM 번호, IP 등) 제공"
log ""
log "================================================================"