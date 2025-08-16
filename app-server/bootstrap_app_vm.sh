#!/bin/bash

# Creative Energy App VM Bootstrap Script  
# Samsung Cloud Platform VM 이미지 부팅 시 자동 실행 스크립트
# 용도: VM 인스턴스 생성 후 Node.js 애플리케이션 자동 시작

set -e

# 로그 설정
LOG_FILE="/var/log/ceweb-bootstrap.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "========================================="
echo "Creative Energy App VM Bootstrap 시작"
echo "시작 시간: $(date)"
echo "호스트명: $(hostname)"
echo "IP 주소: $(hostname -I)"
echo "========================================="

# 시스템 정보 수집
echo "1. 시스템 상태 확인..."
echo "메모리 사용량: $(free -h | grep Mem)"
echo "디스크 사용량: $(df -h / | tail -1)"
echo "부팅 시간: $(uptime)"

# 네트워크 연결 대기
echo "2. 네트워크 연결 대기..."
for i in {1..30}; do
    if ping -c 1 google.com >/dev/null 2>&1; then
        echo "네트워크 연결 확인됨"
        break
    fi
    echo "네트워크 연결 대기 중... ($i/30)"
    sleep 2
done

# DB 서버 연결 대기
echo "3. DB 서버 연결 대기..."
for i in {1..60}; do
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/db.cesvc.net/2866" 2>/dev/null; then
        echo "✅ DB 서버 연결 확인됨 (db.cesvc.net:2866)"
        break
    fi
    echo "DB 서버 연결 대기 중... ($i/60)"
    sleep 3
done

# rocky 사용자로 전환하여 작업 수행
APP_USER="rocky"
APP_DIR="/home/$APP_USER/ceweb"

echo "4. 애플리케이션 디렉토리 점검..."
if [ -d "$APP_DIR" ]; then
    echo "✅ 애플리케이션 디렉토리 확인: $APP_DIR"
    
    # 디렉토리 권한 복구
    chown -R $APP_USER:$APP_USER $APP_DIR
    chmod -R 755 $APP_DIR
    
    # 오디션 파일 디렉토리 권한 확인
    AUDITION_DIR="$APP_DIR/files/audition"
    if [ -d "$AUDITION_DIR" ]; then
        chown -R $APP_USER:$APP_USER "$AUDITION_DIR"
        chmod -R 755 "$AUDITION_DIR"
        echo "✅ 오디션 파일 디렉토리 권한 복구"
    fi
else
    echo "❌ 애플리케이션 디렉토리 누락: $APP_DIR"
    exit 1
fi

# Node.js 및 PM2 상태 확인
echo "5. Node.js 환경 점검..."
if command -v node >/dev/null; then
    echo "✅ Node.js 버전: $(node --version)"
else
    echo "❌ Node.js 설치되지 않음"
    exit 1
fi

if command -v pm2 >/dev/null; then
    echo "✅ PM2 버전: $(pm2 --version)"
else
    echo "❌ PM2 설치되지 않음"
    exit 1
fi

# 환경 변수 파일 점검
echo "6. 환경 설정 파일 점검..."
ENV_FILE="$APP_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    echo "✅ 환경 설정 파일 확인: $ENV_FILE"
    # 파일 권한 보안 설정
    chown $APP_USER:$APP_USER "$ENV_FILE"
    chmod 600 "$ENV_FILE"
else
    echo "❌ 환경 설정 파일 누락: $ENV_FILE"
    exit 1
fi

# 애플리케이션 파일 점검
echo "7. 애플리케이션 파일 점검..."
REQUIRED_FILES=("server.js" "package.json" "ecosystem.config.js")
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$APP_DIR/$file" ]; then
        echo "✅ 필수 파일 확인: $file"
    else
        echo "❌ 필수 파일 누락: $file"
        exit 1
    fi
done

# DB 연결 테스트
echo "8. 데이터베이스 연결 테스트..."
DB_TEST_RESULT=$(sudo -u $APP_USER bash -c "
    cd $APP_DIR
    node -e \"
        require('dotenv').config();
        const pool = require('./config/database');
        pool.query('SELECT 1', (err, result) => {
            if (err) {
                console.log('DB_CONNECTION_FAILED');
                process.exit(1);
            } else {
                console.log('DB_CONNECTION_SUCCESS');
                process.exit(0);
            }
        });
    \"
" 2>/dev/null)

if [[ "$DB_TEST_RESULT" == *"DB_CONNECTION_SUCCESS"* ]]; then
    echo "✅ 데이터베이스 연결 테스트 성공"
else
    echo "⚠️ 데이터베이스 연결 테스트 실패 - 계속 진행"
fi

# PM2 프로세스 정리 및 재시작
echo "9. PM2 프로세스 관리..."
sudo -u $APP_USER bash -c "
    cd $APP_DIR
    
    # 기존 PM2 프로세스 정리
    pm2 kill >/dev/null 2>&1 || true
    
    # 잠시 대기
    sleep 2
    
    # PM2로 애플리케이션 시작
    pm2 start ecosystem.config.js
    
    # PM2 프로세스 상태 확인
    pm2 status
    
    # PM2 자동 시작 설정 (이미 설정되어 있어도 재실행)
    pm2 save
"

# 애플리케이션 포트 점검
echo "10. 애플리케이션 포트 점검..."
for i in {1..30}; do
    if ss -tlnp | grep -q ':3000'; then
        echo "✅ 애플리케이션 포트 3000 바인딩 확인"
        break
    fi
    echo "포트 3000 바인딩 대기 중... ($i/30)"
    sleep 2
done

# Health Check API 테스트
echo "11. Health Check API 테스트..."
for i in {1..20}; do
    if curl -f -s http://localhost:3000/health >/dev/null; then
        echo "✅ Health Check API 응답 정상"
        break
    fi
    echo "Health Check API 응답 대기 중... ($i/20)"
    sleep 3
done

# 방화벽 포트 확인 (필요시)
echo "12. 방화벽 설정 점검..."
if systemctl is-active --quiet firewalld; then
    echo "방화벽 활성화 상태"
    if ! firewall-cmd --query-port=3000/tcp --quiet; then
        echo "포트 3000 개방 중..."
        firewall-cmd --permanent --add-port=3000/tcp
        firewall-cmd --reload
    fi
fi

# VM 식별 정보 생성 (Load Balancer용)
echo "13. VM 식별 정보 생성..."
VM_INFO_FILE="/home/$APP_USER/ceweb/vm-info.json"
PM2_STATUS=$(sudo -u $APP_USER pm2 jlist | jq -r '.[0].pm2_env.status' 2>/dev/null || echo "unknown")

# VM 인스턴스 번호 자동 감지 (hostname 기반)
VM_NUMBER="1"
if [[ $(hostname) == *"2"* ]] || [[ $(hostname) == *"app2"* ]]; then
    VM_NUMBER="2"
fi

sudo -u $APP_USER bash -c "cat > '$VM_INFO_FILE' << EOF
{
    \"vm_type\": \"app\",
    \"vm_number\": \"$VM_NUMBER\",
    \"hostname\": \"$(hostname)\",
    \"ip_address\": \"$(hostname -I | awk '{print $1}')\",
    \"startup_time\": \"$(date -Iseconds)\",
    \"app_status\": \"$PM2_STATUS\",
    \"app_port\": \"3000\",
    \"node_version\": \"$(node --version)\",
    \"pm2_version\": \"$(pm2 --version)\",
    \"load_balancer\": \"appLB\",
    \"region\": \"$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo 'samsung-cloud')\",
    \"last_health_check\": \"$(date -Iseconds)\"
}
EOF"
echo "✅ VM 정보 파일 생성: $VM_INFO_FILE (App-$VM_NUMBER)"

# API 엔드포인트로 VM 정보 등록 (선택적)
echo "14. VM 정보 등록..."
if curl -f -s -X POST http://localhost:3000/health -H "Content-Type: application/json" >/dev/null; then
    echo "✅ VM 정보 등록 성공"
else
    echo "⚠️ VM 정보 등록 실패 (선택사항)"
fi

# 최종 상태 확인
echo "15. 서비스 최종 상태 확인..."
APP_STATUS=$(sudo -u $APP_USER pm2 list | grep -c "online" || echo "0")
echo "PM2 온라인 프로세스: $APP_STATUS"
echo "포트 3000 상태: $(ss -tlnp | grep :3000 | wc -l)개"

echo "========================================="
echo "Creative Energy App VM Bootstrap 완료"
echo "완료 시간: $(date)"
echo "애플리케이션 상태: $(sudo -u $APP_USER pm2 list --no-color | grep creative-energy-api || echo 'Not found')"
echo "========================================="

# 성공 여부에 따른 exit code 설정
if [ "$APP_STATUS" -gt 0 ] && ss -tlnp | grep -q ':3000'; then
    echo "🎉 App VM 부팅 완료 - 애플리케이션 정상"
    exit 0
else
    echo "❌ App VM 부팅 실패 - 애플리케이션 점검 필요"
    exit 1
fi