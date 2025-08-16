#!/bin/bash

# Creative Energy Web VM Bootstrap Script
# Samsung Cloud Platform VM 이미지 부팅 시 자동 실행 스크립트
# 용도: VM 인스턴스 생성 후 서비스 자동 시작

set -e

# 로그 설정
LOG_FILE="/var/log/ceweb-bootstrap.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "========================================="
echo "Creative Energy Web VM Bootstrap 시작"
echo "시작 시간: $(date)"
echo "호스트명: $(hostname)"
echo "IP 주소: $(hostname -I)"
echo "========================================="

# 시스템 정보 수집
echo "1. 시스템 상태 확인..."
echo "메모리 사용량: $(free -h | grep Mem)"
echo "디스크 사용량: $(df -h / | tail -1)"
echo "부팅 시간: $(uptime)"

# 네트워크 연결 대기 (클라우드 환경에서 네트워크 초기화 시간 필요)
echo "2. 네트워크 연결 대기..."
for i in {1..30}; do
    if ping -c 1 google.com >/dev/null 2>&1; then
        echo "네트워크 연결 확인됨"
        break
    fi
    echo "네트워크 연결 대기 중... ($i/30)"
    sleep 2
done

# Nginx 서비스 상태 확인 및 재시작
echo "3. Nginx 서비스 점검..."
if systemctl is-active --quiet nginx; then
    echo "✅ Nginx 서비스 실행 중"
else
    echo "⚠️ Nginx 서비스 정지됨, 재시작 중..."
    systemctl start nginx
    systemctl enable nginx
fi

# Nginx 설정 파일 점검
echo "4. Nginx 설정 점검..."
if nginx -t >/dev/null 2>&1; then
    echo "✅ Nginx 설정 정상"
else
    echo "❌ Nginx 설정 오류, 기본 설정 복원 시도..."
    if [ -f /etc/nginx/nginx.conf.backup ]; then
        cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf
        systemctl reload nginx
    fi
fi

# 웹 디렉토리 권한 점검 및 복구
echo "5. 웹 디렉토리 권한 점검..."
WEB_DIR="/home/rocky/ceweb"
if [ -d "$WEB_DIR" ]; then
    # 권한 복구
    chown -R rocky:rocky "$WEB_DIR"
    chmod -R 755 "$WEB_DIR"
    chmod 755 /home/rocky
    echo "✅ 웹 디렉토리 권한 복구 완료"
    
    # 주요 파일 존재 확인
    if [ -f "$WEB_DIR/index.html" ]; then
        echo "✅ 웹 파일 정상 확인"
    else
        echo "⚠️ 웹 파일 누락 감지"
    fi
else
    echo "❌ 웹 디렉토리 누락: $WEB_DIR"
fi

# SELinux 컨텍스트 복원 (필요시)
echo "6. SELinux 설정 점검..."
if command -v getenforce >/dev/null && getenforce | grep -q "Enforcing"; then
    echo "SELinux 활성화 상태, 컨텍스트 복원 중..."
    setsebool -P httpd_read_user_content on >/dev/null 2>&1 || true
    setsebool -P httpd_can_network_connect on >/dev/null 2>&1 || true
    restorecon -Rv "$WEB_DIR" >/dev/null 2>&1 || true
    echo "✅ SELinux 설정 완료"
fi

# 방화벽 포트 확인
echo "7. 방화벽 설정 점검..."
if systemctl is-active --quiet firewalld; then
    echo "방화벽 활성화 상태"
    if ! firewall-cmd --query-port=80/tcp --quiet; then
        echo "포트 80 개방 중..."
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --reload
    fi
fi

# App Server 연결 테스트
echo "8. App Server 연결성 테스트..."
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/app.cesvc.net/3000" 2>/dev/null; then
    echo "✅ App Server 연결 정상 (app.cesvc.net:3000)"
else
    echo "⚠️ App Server 연결 불가 - Load Balancer 설정 확인 필요"
fi

# Load Balancer Health Check 엔드포인트 응답 테스트
echo "9. Health Check 엔드포인트 테스트..."
if curl -f -s http://localhost/ >/dev/null; then
    echo "✅ Web Server Health Check 정상"
else
    echo "⚠️ Web Server Health Check 실패"
fi

# 서비스 최종 상태 확인
echo "10. 서비스 최종 상태 확인..."
echo "Nginx 상태: $(systemctl is-active nginx)"
echo "Nginx 포트: $(ss -tlnp | grep :80 || echo 'Port 80 not listening')"

# VM 식별 정보 생성 (Load Balancer용)
echo "11. VM 식별 정보 생성..."
VM_INFO_FILE="/home/rocky/ceweb/vm-info.json"

# Load Balancer 환경: VM 인스턴스 번호 자동 감지 (hostname 기반)
VM_NUMBER="1"
VM_HOSTNAME=$(hostname)
if [[ $VM_HOSTNAME == *"111"* ]] || [[ $VM_HOSTNAME == *"web1"* ]]; then
    VM_NUMBER="1"
elif [[ $VM_HOSTNAME == *"112"* ]] || [[ $VM_HOSTNAME == *"web2"* ]]; then
    VM_NUMBER="2"
fi

# 실제 서버 IP 확인 (Load Balancer 환경)
INTERNAL_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")

cat > "$VM_INFO_FILE" << EOF
{
    "vm_type": "web",
    "vm_number": "$VM_NUMBER",
    "hostname": "$VM_HOSTNAME",
    "internal_ip": "$INTERNAL_IP",
    "ip_address": "$PUBLIC_IP",
    "startup_time": "$(date -Iseconds)",
    "nginx_status": "$(systemctl is-active nginx)",
    "nginx_port": "80",
    "load_balancer": {
        "name": "www.cesvc.net",
        "ip": "10.1.1.100",
        "policy": "Round Robin",
        "pool": ["webvm111r (10.1.1.111)", "webvm112r (10.1.1.112)"]
    },
    "architecture": {
        "tier": "Web Server",
        "role": "Static files + API Proxy",
        "upstream": "app.cesvc.net (10.1.2.100)"
    },
    "region": "$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo 'samsung-cloud')",
    "last_health_check": "$(date -Iseconds)"
}
EOF
chown rocky:rocky "$VM_INFO_FILE"
chmod 644 "$VM_INFO_FILE"
echo "✅ VM 정보 파일 생성: $VM_INFO_FILE (Web-$VM_NUMBER)"

echo "========================================="
echo "Creative Energy Web VM Bootstrap 완료"
echo "완료 시간: $(date)"
echo "웹 서버 상태: $(systemctl is-active nginx)"
echo "========================================="

# 성공 여부에 따른 exit code 설정
if systemctl is-active --quiet nginx; then
    echo "🎉 Web VM 부팅 완료 - 서비스 정상"
    exit 0
else
    echo "❌ Web VM 부팅 실패 - 서비스 점검 필요"
    exit 1
fi