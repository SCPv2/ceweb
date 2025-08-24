#!/bin/bash
# ==============================================================================
# Copyright (c) 2025 Stan H. All rights reserved.
#
# This software and its source code are the exclusive property of Stan H.
#
# Use is strictly limited to 2025 SCPv2 Advance training and education only.
# Any reproduction, modification, distribution, or other use beyond this scope is
# strictly prohibited without prior written permission from the copyright holder.
#
# Unauthorized use may lead to legal action under applicable law.
#
# Contact: ars4mundus@gmail.com
# ==============================================================================

# Creative Energy App VM Bootstrap Script  
# Samsung Cloud Platform VM 이미지 부팅 시 자동 실행 스크립트
# 용도: VM 인스턴스 생성 후 Node.js 애플리케이션 자동 시작
# 수정: 네트워크 체크 비활성화, 애플리케이션 재시작 최우선

set -e

# 로그 설정 (시스템 로그 + 홈 디렉토리 로그)
LOG_FILE="/var/log/ceweb-bootstrap.log"
HOME_LOG_FILE="/home/rocky/Application_Reloaded_Successfully.log"

# 듀얼 로깅 함수
log_message() {
    local message="$1"
    echo "$message" | tee -a "$LOG_FILE" >> "$HOME_LOG_FILE" 2>/dev/null || echo "$message"
}

# 명령어 실행 및 결과 로깅 함수
execute_and_log() {
    local description="$1"
    local command="$2"
    
    log_message "========== 실행: $description =========="
    log_message "명령어: $command"
    log_message "시간: $(date)"
    
    if eval "$command" 2>&1 | tee -a "$HOME_LOG_FILE"; then
        log_message "✅ 성공: $description"
        log_message ""
        return 0
    else
        log_message "❌ 실패: $description"
        log_message ""
        return 1
    fi
}

log_message "========================================="
log_message "Creative Energy App VM Bootstrap 시작"
log_message "시작 시간: $(date)"
log_message "호스트명: $(hostname)"
log_message "IP 주소: $(hostname -I)"
log_message "========================================="

# 1. 시스템 정보 수집 (네트워크 체크 없이)
log_message "1. 시스템 상태 확인..."
log_message "메모리 사용량: $(free -h | grep Mem)"
log_message "디스크 사용량: $(df -h / | tail -1)"
log_message "부팅 시간: $(uptime)"

# 2. 애플리케이션 디렉토리 및 권한 설정 (최우선)
APP_USER="rocky"
APP_DIR="/home/$APP_USER/ceweb"

log_message "2. 애플리케이션 디렉토리 및 권한 설정..."
if [ -d "$APP_DIR" ]; then
    log_message "✅ 애플리케이션 디렉토리 확인: $APP_DIR"
    
    execute_and_log "디렉토리 권한 복구" "chown -R $APP_USER:$APP_USER $APP_DIR"
    execute_and_log "디렉토리 권한 설정" "chmod -R 755 $APP_DIR"
    
    # 오디션 파일 디렉토리 권한 확인
    AUDITION_DIR="$APP_DIR/files/audition"
    if [ -d "$AUDITION_DIR" ]; then
        execute_and_log "오디션 디렉토리 권한 설정" "chown -R $APP_USER:$APP_USER '$AUDITION_DIR' && chmod -R 755 '$AUDITION_DIR'"
        log_message "✅ 오디션 파일 디렉토리 권한 복구"
    fi
    
    # 홈 디렉토리 로그 파일 권한 설정
    execute_and_log "로그 파일 생성 및 권한 설정" "touch '$HOME_LOG_FILE' && chown $APP_USER:$APP_USER '$HOME_LOG_FILE' && chmod 644 '$HOME_LOG_FILE'"
    
else
    log_message "❌ 애플리케이션 디렉토리 누락: $APP_DIR"
    exit 1
fi

# 3. Node.js 및 PM2 환경 확인
log_message "3. Node.js 및 PM2 환경 확인..."
if command -v node >/dev/null; then
    log_message "✅ Node.js 버전: $(node --version)"
else
    log_message "❌ Node.js 설치되지 않음"
    exit 1
fi

if command -v pm2 >/dev/null; then
    log_message "✅ PM2 버전: $(pm2 --version)"
else
    log_message "❌ PM2 설치되지 않음"
    exit 1
fi

# 4. 환경 설정 파일 확인
log_message "4. 환경 설정 파일 확인..."
ENV_FILE="$APP_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    log_message "✅ 환경 설정 파일 확인: $ENV_FILE"
    execute_and_log "환경 파일 권한 설정" "chown $APP_USER:$APP_USER '$ENV_FILE' && chmod 600 '$ENV_FILE'"
else
    log_message "❌ 환경 설정 파일 누락: $ENV_FILE"
    exit 1
fi

# 5. 필수 애플리케이션 파일 확인
log_message "5. 필수 애플리케이션 파일 확인..."
REQUIRED_FILES=("server.js" "package.json" "ecosystem.config.js")
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$APP_DIR/$file" ]; then
        log_message "✅ 필수 파일 확인: $file"
    else
        log_message "❌ 필수 파일 누락: $file"
        exit 1
    fi
done

# 6. 애플리케이션 강제 재시작 (네트워크 체크 없이)
log_message "6. 애플리케이션 강제 재시작..."

execute_and_log "기존 PM2 프로세스 정리" "sudo -u $APP_USER bash -c 'cd $APP_DIR && pm2 delete creative-energy-api >/dev/null 2>&1 || true'"
execute_and_log "PM2 데몬 완전 종료" "sudo -u $APP_USER bash -c 'cd $APP_DIR && pm2 kill >/dev/null 2>&1 || true'"

log_message "프로세스 완전 종료 대기 중..."
sleep 5

# 포트 3000이 완전히 해제될 때까지 대기
log_message "포트 3000 해제 확인 중..."
for i in {1..15}; do
    if ! ss -tlnp | grep -q ':3000'; then
        log_message "✅ 포트 3000 해제 완료"
        break
    fi
    log_message "포트 3000 해제 대기 중... ($i/15)"
    sleep 2
done

# PM2로 애플리케이션 시작
execute_and_log "PM2 애플리케이션 시작" "sudo -u $APP_USER bash -c 'cd $APP_DIR && pm2 start ecosystem.config.js'"
execute_and_log "PM2 설정 저장" "sudo -u $APP_USER bash -c 'cd $APP_DIR && pm2 save'"

# 7. 애플리케이션 시작 확인
log_message "7. 애플리케이션 시작 확인..."
for i in {1..30}; do
    if ss -tlnp | grep -q ':3000'; then
        log_message "✅ 애플리케이션 포트 3000 바인딩 확인 ($i초 소요)"
        break
    fi
    log_message "포트 3000 바인딩 대기 중... ($i/30)"
    sleep 2
done

# 8. Health Check 확인 (간단히)
log_message "8. Health Check 확인..."
for i in {1..15}; do
    if curl -f -s http://localhost:3000/health >/dev/null 2>&1; then
        log_message "✅ Health Check API 응답 정상 ($i회 시도)"
        break
    fi
    log_message "Health Check API 응답 대기 중... ($i/15)"
    sleep 3
done

# 9. VM 식별 정보 생성
log_message "9. VM 식별 정보 생성..."
VM_INFO_FILE="/home/$APP_USER/ceweb/vm-info.json"
PM2_STATUS=$(sudo -u $APP_USER pm2 jlist | jq -r '.[0].pm2_env.status' 2>/dev/null || echo "unknown")

# Load Balancer 환경: VM 인스턴스 번호 자동 감지
VM_NUMBER="1"
VM_HOSTNAME=$(hostname)
if [[ $VM_HOSTNAME == *"121"* ]] || [[ $VM_HOSTNAME == *"app1"* ]]; then
    VM_NUMBER="1"
elif [[ $VM_HOSTNAME == *"122"* ]] || [[ $VM_HOSTNAME == *"app2"* ]]; then
    VM_NUMBER="2"
fi

# 서버 IP 확인 (외부 연결 없이)
INTERNAL_IP=$(hostname -I | awk '{print $1}')

execute_and_log "VM 정보 파일 생성" "sudo -u $APP_USER bash -c \"cat > '$VM_INFO_FILE' << 'EOF'
{
    \\\"vm_type\\\": \\\"app\\\",
    \\\"vm_number\\\": \\\"$VM_NUMBER\\\",
    \\\"hostname\\\": \\\"$VM_HOSTNAME\\\",
    \\\"internal_ip\\\": \\\"$INTERNAL_IP\\\",
    \\\"startup_time\\\": \\\"$(date -Iseconds)\\\",
    \\\"app_status\\\": \\\"$PM2_STATUS\\\",
    \\\"app_port\\\": \\\"3000\\\",
    \\\"node_version\\\": \\\"$(node --version)\\\",
    \\\"pm2_version\\\": \\\"$(pm2 --version)\\\",
    \\\"load_balancer\\\": {
        \\\"name\\\": \\\"app.${private_domain_name}\\\",
        \\\"ip\\\": \\\"10.1.2.100\\\",
        \\\"policy\\\": \\\"Round Robin\\\",
        \\\"pool\\\": [\\\"appvm121r (10.1.2.121)\\\", \\\"appvm122r (10.1.2.122)\\\"]
    },
    \\\"architecture\\\": {
        \\\"tier\\\": \\\"App Server\\\",
        \\\"role\\\": \\\"API Processing + Business Logic\\\",
        \\\"database\\\": \\\"db.${private_domain_name}:2866\\\"
    },
    \\\"region\\\": \\\"samsung-cloud\\\",
    \\\"last_health_check\\\": \\\"$(date -Iseconds)\\\",
    \\\"bootstrap_completed\\\": true
}
EOF\""

log_message "✅ VM 정보 파일 생성: $VM_INFO_FILE (App-$VM_NUMBER)"

# 10. 최종 상태 확인
log_message "10. 서비스 최종 상태 확인..."
APP_STATUS=$(sudo -u $APP_USER pm2 list | grep -c "online" 2>/dev/null || echo "0")
PORT_STATUS=$(ss -tlnp | grep :3000 | wc -l)

log_message "PM2 온라인 프로세스: $APP_STATUS개"
log_message "포트 3000 바인딩: $PORT_STATUS개"

# PM2 상태 상세 출력
execute_and_log "PM2 상태 확인" "sudo -u $APP_USER pm2 status"

log_message "========================================="
log_message "Creative Energy App VM Bootstrap 완료"
log_message "완료 시간: $(date)"
log_message "최종 애플리케이션 상태: $(sudo -u $APP_USER pm2 list --no-color | grep creative-energy-api | awk '{print $4}' || echo 'Not found')"
log_message "========================================="

# 성공 로그 메시지
if [ "$APP_STATUS" -gt 0 ] && [ "$PORT_STATUS" -gt 0 ]; then
    log_message "🎉 App VM 부팅 완료 - 애플리케이션 정상 구동"
    log_message "✅ Application Reloaded Successfully!"
    log_message "   - PM2 프로세스: $APP_STATUS개 온라인"
    log_message "   - 포트 3000: 바인딩 완료"
    log_message "   - 로그 위치: $HOME_LOG_FILE"
    
    # 성공 표시 파일 생성
    echo "SUCCESS - $(date)" > "/home/$APP_USER/APPLICATION_STATUS"
    chown $APP_USER:$APP_USER "/home/$APP_USER/APPLICATION_STATUS"
    
    exit 0
else
    log_message "❌ App VM 부팅 실패 - 애플리케이션 점검 필요"
    log_message "   - PM2 프로세스: $APP_STATUS개"
    log_message "   - 포트 바인딩: $PORT_STATUS개"
    
    # 실패 표시 파일 생성
    echo "FAILED - $(date)" > "/home/$APP_USER/APPLICATION_STATUS"
    chown $APP_USER:$APP_USER "/home/$APP_USER/APPLICATION_STATUS"
    
    exit 1
fi