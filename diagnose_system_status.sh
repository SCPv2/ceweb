#!/bin/bash

# Creative Energy 전체 시스템 상태 진단 스크립트
# Load Balancer 환경의 모든 서버 상태를 종합적으로 확인
# 사용법: bash diagnose_system_status.sh

echo "================================================"
echo "Creative Energy 전체 시스템 상태 진단"
echo "시간: $(date)"
echo "실행 서버: $(hostname) ($(hostname -I | awk '{print $1}'))"
echo "================================================"
echo

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 상태 체크 함수
check_status() {
    local service=$1
    local url=$2
    local expected_status=${3:-200}
    
    echo -n "[$service] "
    
    if curl -f -s --connect-timeout 5 --max-time 10 "$url" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 정상${NC}"
        return 0
    else
        local status_code=$(curl -s -w "%{http_code}" -o /dev/null --connect-timeout 5 --max-time 10 "$url" 2>/dev/null)
        if [[ "$status_code" == "$expected_status" || "$status_code" == "404" ]]; then
            echo -e "${YELLOW}⚠️  응답 코드: $status_code${NC}"
            return 0
        else
            echo -e "${RED}❌ 연결 실패 (코드: $status_code)${NC}"
            return 1
        fi
    fi
}

# 1. 현재 서버 유형 확인
echo "🔍 1. 현재 서버 정보"
echo "----------------------------------------"
HOSTNAME=$(hostname -s)
SERVER_TYPE="unknown"

if [[ $HOSTNAME =~ webvm ]]; then
    SERVER_TYPE="web-server"
elif [[ $HOSTNAME =~ appvm ]]; then
    SERVER_TYPE="app-server"
elif [[ $HOSTNAME =~ dbvm ]]; then
    SERVER_TYPE="db-server"
fi

echo "서버 유형: $SERVER_TYPE"
echo "호스트명: $HOSTNAME"
echo "IP 주소: $(hostname -I | awk '{print $1}')"
echo

# 2. Load Balancer 상태 확인
echo "🌐 2. Load Balancer 상태 확인"
echo "----------------------------------------"
echo "Web Load Balancer:"
check_status "www.cesvc.net" "http://www.cesvc.net/"
check_status "www.creative-energy.net" "http://www.creative-energy.net/"

echo
echo "App Load Balancer:"
check_status "app.cesvc.net:3000" "http://app.cesvc.net:3000/health"
echo

# 3. 개별 서버 상태 확인
echo "🖥️ 3. 개별 서버 상태 확인"
echo "----------------------------------------"
echo "Web Servers:"
check_status "webvm111r" "http://10.1.1.111/health"
check_status "webvm112r" "http://10.1.1.112/health"

echo
echo "App Servers:"
check_status "appvm121r" "http://10.1.2.121:3000/health"
check_status "appvm122r" "http://10.1.2.122:3000/health"

echo
echo "DB Server:"
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/10.1.3.131/2866" 2>/dev/null; then
    echo -e "[dbvm131r:2866] ${GREEN}✅ 포트 연결 성공${NC}"
else
    echo -e "[dbvm131r:2866] ${RED}❌ 포트 연결 실패${NC}"
fi
echo

# 4. 현재 서버의 로컬 서비스 상태
echo "🔧 4. 로컬 서비스 상태"
echo "----------------------------------------"

if [[ "$SERVER_TYPE" == "web-server" ]]; then
    echo "Nginx 서비스:"
    if systemctl is-active --quiet nginx; then
        echo -e "✅ ${GREEN}Nginx 실행 중${NC}"
        check_status "로컬 API 프록시" "http://localhost/api/orders/products"
        check_status "로컬 Health Check" "http://localhost/health"
    else
        echo -e "❌ ${RED}Nginx 중지됨${NC}"
    fi
    
elif [[ "$SERVER_TYPE" == "app-server" ]]; then
    echo "Node.js 애플리케이션:"
    if pgrep -f "node.*server.js" >/dev/null || pgrep -f "PM2" >/dev/null; then
        echo -e "✅ ${GREEN}App Server 실행 중${NC}"
        check_status "로컬 API" "http://localhost:3000/health"
        check_status "로컬 Products API" "http://localhost:3000/api/orders/products"
        
        # PM2 상태
        if command -v pm2 &> /dev/null; then
            echo
            echo "PM2 프로세스 상태:"
            pm2 list 2>/dev/null | grep -E "(creative-energy|App name)" || echo "PM2 상태 확인 실패"
        fi
        
        # CORS 설정 확인
        echo
        echo "CORS 설정 상태:"
        if [ -f "/home/rocky/ceweb/.env" ]; then
            if grep -q "^ALLOWED_ORIGINS=" "/home/rocky/ceweb/.env"; then
                echo -e "⚠️ ${YELLOW}ALLOWED_ORIGINS 환경변수 설정됨 (제한적 허용)${NC}"
                grep "^ALLOWED_ORIGINS=" "/home/rocky/ceweb/.env" | cut -d'=' -f2
            elif grep -q "^#ALLOWED_ORIGINS=" "/home/rocky/ceweb/.env"; then
                echo -e "✅ ${GREEN}ALLOWED_ORIGINS 주석 처리됨 (Public IP 허용)${NC}"
            else
                echo -e "❓ ${YELLOW}ALLOWED_ORIGINS 설정 없음${NC}"
            fi
        fi
    else
        echo -e "❌ ${RED}App Server 중지됨${NC}"
    fi
fi

echo

# 5. 포트 사용 상태
echo "🔌 5. 포트 사용 상태"
echo "----------------------------------------"
if [[ "$SERVER_TYPE" == "web-server" ]]; then
    echo "포트 80 (HTTP):"
    if netstat -tulpn 2>/dev/null | grep ":80 " >/dev/null; then
        echo -e "✅ ${GREEN}포트 80 사용 중${NC}"
    else
        echo -e "❌ ${RED}포트 80 사용 안됨${NC}"
    fi
elif [[ "$SERVER_TYPE" == "app-server" ]]; then
    echo "포트 3000 (Node.js):"
    if netstat -tulpn 2>/dev/null | grep ":3000 " >/dev/null; then
        echo -e "✅ ${GREEN}포트 3000 사용 중${NC}"
    else
        echo -e "❌ ${RED}포트 3000 사용 안됨${NC}"
    fi
fi
echo

# 6. VM 정보 파일 확인
echo "📋 6. VM 정보 파일 상태"
echo "----------------------------------------"
VM_INFO_FILE="/home/rocky/ceweb/vm-info.json"
if [ -f "$VM_INFO_FILE" ]; then
    echo -e "✅ ${GREEN}vm-info.json 파일 존재${NC}"
    echo "VM 정보:"
    cat "$VM_INFO_FILE" | jq -r '. | "  호스트: \(.hostname), IP: \(.ip_address), VM번호: \(.vm_number), 타입: \(.server_type)"' 2>/dev/null || {
        echo "  $(grep -o '"hostname":"[^"]*"' "$VM_INFO_FILE" | cut -d'"' -f4)"
        echo "  $(grep -o '"ip_address":"[^"]*"' "$VM_INFO_FILE" | cut -d'"' -f4)"
    }
else
    echo -e "❌ ${RED}vm-info.json 파일 없음${NC}"
    echo "  위치: $VM_INFO_FILE"
fi
echo

# 7. 최근 로그 확인
echo "📝 7. 최근 오류 로그 (최근 5줄)"
echo "----------------------------------------"
if [[ "$SERVER_TYPE" == "web-server" ]]; then
    echo "Nginx 오류 로그:"
    if [ -f "/var/log/nginx/creative-energy-error.log" ]; then
        tail -5 /var/log/nginx/creative-energy-error.log 2>/dev/null || echo "로그 없음"
    else
        echo "로그 파일 없음"
    fi
elif [[ "$SERVER_TYPE" == "app-server" ]]; then
    echo "App Server 로그:"
    if command -v pm2 &> /dev/null; then
        pm2 logs creative-energy-api --lines 5 2>/dev/null || echo "PM2 로그 확인 실패"
    else
        echo "PM2 명령어 없음"
    fi
fi
echo

# 8. 디스크 및 메모리 상태
echo "💾 8. 시스템 리소스 상태"
echo "----------------------------------------"
echo "디스크 사용량:"
df -h / | tail -1 | awk '{print "  루트: " $3 "/" $2 " 사용 (" $5 " 사용률)"}'

echo "메모리 사용량:"
free -h | grep "Mem:" | awk '{print "  메모리: " $3 "/" $2 " 사용"}'

echo "시스템 로드:"
uptime | awk '{print "  " $0}'
echo

# 9. 네트워크 연결성 테스트
echo "🌐 9. 네트워크 연결성 테스트"
echo "----------------------------------------"
echo "외부 서버 연결:"

# DB 서버 연결
echo -n "DB 서버 (db.cesvc.net:2866): "
if timeout 3 bash -c "cat < /dev/null > /dev/tcp/db.cesvc.net/2866" 2>/dev/null; then
    echo -e "${GREEN}✅ 연결됨${NC}"
else
    echo -e "${RED}❌ 연결 실패${NC}"
fi

# Load Balancer 연결
if [[ "$SERVER_TYPE" != "web-server" ]]; then
    echo -n "Web Load Balancer (www.cesvc.net): "
    if timeout 3 bash -c "cat < /dev/null > /dev/tcp/www.cesvc.net/80" 2>/dev/null; then
        echo -e "${GREEN}✅ 연결됨${NC}"
    else
        echo -e "${RED}❌ 연결 실패${NC}"
    fi
fi

if [[ "$SERVER_TYPE" != "app-server" ]]; then
    echo -n "App Load Balancer (app.cesvc.net:3000): "
    if timeout 3 bash -c "cat < /dev/null > /dev/tcp/app.cesvc.net/3000" 2>/dev/null; then
        echo -e "${GREEN}✅ 연결됨${NC}"
    else
        echo -e "${RED}❌ 연결 실패${NC}"
    fi
fi
echo

# 10. 종합 결과
echo "📊 10. 종합 상태 결과"
echo "----------------------------------------"
echo -e "서버 유형: ${BLUE}$SERVER_TYPE${NC}"
echo -e "호스트명: ${BLUE}$HOSTNAME${NC}"

# 서비스 상태 요약
if [[ "$SERVER_TYPE" == "web-server" ]]; then
    if systemctl is-active --quiet nginx && netstat -tulpn 2>/dev/null | grep ":80 " >/dev/null; then
        echo -e "서비스 상태: ${GREEN}✅ 정상 (Nginx 실행 중)${NC}"
    else
        echo -e "서비스 상태: ${RED}❌ 비정상 (Nginx 문제)${NC}"
    fi
elif [[ "$SERVER_TYPE" == "app-server" ]]; then
    if (pgrep -f "node.*server.js" >/dev/null || pgrep -f "PM2" >/dev/null) && netstat -tulpn 2>/dev/null | grep ":3000 " >/dev/null; then
        echo -e "서비스 상태: ${GREEN}✅ 정상 (Node.js 실행 중)${NC}"
    else
        echo -e "서비스 상태: ${RED}❌ 비정상 (Node.js 문제)${NC}"
    fi
else
    echo -e "서비스 상태: ${YELLOW}❓ 확인 불가 (알 수 없는 서버 유형)${NC}"
fi

echo
echo "🔧 권장 조치사항:"
if [[ "$SERVER_TYPE" == "app-server" ]]; then
    echo "- CORS 403 오류 발생 시: sudo bash fix_cors_public_ip.sh"
    echo "- API 404 오류 발생 시: sudo bash fix_api_404.sh"
elif [[ "$SERVER_TYPE" == "web-server" ]]; then
    echo "- API 프록시 문제 시: sudo nginx -t && sudo systemctl reload nginx"
    echo "- 정적 파일 문제 시: ls -la /home/rocky/ceweb/"
fi
echo "- 전체 진단: bash diagnose_api_404.sh"
echo "- 서비스 재시작: pm2 restart all (App) / sudo systemctl restart nginx (Web)"

echo
echo "================================================"
echo "시스템 상태 진단 완료: $(date)"
echo "================================================"