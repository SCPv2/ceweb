#!/bin/bash

# Creative Energy API 404 오류 실시간 진단 스크립트
# 사용법: bash diagnose_api_404.sh

echo "================================================"
echo "Creative Energy API 404 오류 진단"
echo "시간: $(date)"
echo "호스트: $(hostname) ($(hostname -I | awk '{print $1}'))"
echo "================================================"
echo

# 1. Nginx 상태 확인
echo "🔍 1. Nginx 서비스 상태"
echo "----------------------------------------"
if systemctl is-active --quiet nginx; then
    echo "✅ Nginx 실행 중"
    systemctl status nginx --no-pager -l | head -5
else
    echo "❌ Nginx 중지됨"
    echo "해결: sudo systemctl start nginx"
fi
echo

# 2. Nginx 설정 파일 확인
echo "🔍 2. Nginx 프록시 설정 확인"
echo "----------------------------------------"
if [ -f "/etc/nginx/conf.d/creative-energy.conf" ]; then
    echo "✅ Creative Energy 설정 파일 존재"
    
    # API 프록시 설정 확인
    if grep -A 3 "location /api/" /etc/nginx/conf.d/creative-energy.conf; then
        echo ""
        echo "현재 proxy_pass 설정:"
        grep "proxy_pass.*3000" /etc/nginx/conf.d/creative-energy.conf || echo "❌ proxy_pass 설정 없음"
    else
        echo "❌ /api/ location 설정 없음"
    fi
else
    echo "❌ Creative Energy nginx 설정 파일 없음"
    echo "위치: /etc/nginx/conf.d/creative-energy.conf"
fi
echo

# 3. Nginx 설정 테스트
echo "🔍 3. Nginx 설정 검증"
echo "----------------------------------------"
if nginx -t 2>&1; then
    echo "✅ Nginx 설정 문법 정상"
else
    echo "❌ Nginx 설정 문법 오류"
fi
echo

# 4. 포트 사용 상태 확인
echo "🔍 4. 포트 사용 상태"
echo "----------------------------------------"
echo "포트 80 (Nginx):"
if netstat -tulpn 2>/dev/null | grep ":80 "; then
    echo "✅ 포트 80 사용 중"
else
    echo "❌ 포트 80 사용 안됨"
fi

echo ""
echo "포트 3000 (App Server):"
if netstat -tulpn 2>/dev/null | grep ":3000 "; then
    echo "✅ 포트 3000 사용 중"
    netstat -tulpn 2>/dev/null | grep ":3000"
else
    echo "❌ 포트 3000 사용 안됨 (App Server 중지)"
fi
echo

# 5. App Server 프로세스 확인
echo "🔍 5. App Server 프로세스 상태"
echo "----------------------------------------"
if pgrep -f "node.*server.js" >/dev/null; then
    echo "✅ Node.js 서버 프로세스 실행 중"
    ps aux | grep -E "(node|server.js)" | grep -v grep
elif pgrep -f "PM2" >/dev/null; then
    echo "✅ PM2 프로세스 실행 중"
    if command -v pm2 &> /dev/null; then
        pm2 list 2>/dev/null || echo "PM2 상태 확인 실패"
    else
        echo "⚠️ pm2 명령어 없음"
    fi
else
    echo "❌ App Server 프로세스 없음"
fi
echo

# 6. 로컬 API 테스트
echo "🔍 6. 로컬 API 연결 테스트"
echo "----------------------------------------"
echo "Health Check 테스트:"
if curl -f -s --connect-timeout 5 http://localhost/health >/dev/null 2>&1; then
    echo "✅ /health 프록시 연결 성공"
    curl -s http://localhost/health | head -3
else
    echo "❌ /health 프록시 연결 실패"
fi
echo ""

echo "Products API 테스트:"
if curl -f -s --connect-timeout 5 http://localhost/api/orders/products >/dev/null 2>&1; then
    echo "✅ /api/orders/products 프록시 연결 성공"
else
    echo "❌ /api/orders/products 프록시 연결 실패"
    
    # 직접 앱서버 연결 테스트
    echo "직접 App Server 연결 테스트:"
    if curl -f -s --connect-timeout 5 http://localhost:3000/api/orders/products >/dev/null 2>&1; then
        echo "✅ 앱서버 직접 연결 성공 → Nginx 프록시 문제"
    else
        echo "❌ 앱서버 직접 연결도 실패 → App Server 문제"
    fi
fi
echo

# 7. 로그 확인
echo "🔍 7. 최근 오류 로그"
echo "----------------------------------------"
echo "Nginx 오류 로그 (최근 5줄):"
if [ -f "/var/log/nginx/creative-energy-error.log" ]; then
    tail -5 /var/log/nginx/creative-energy-error.log 2>/dev/null || echo "로그 없음"
elif [ -f "/var/log/nginx/error.log" ]; then
    tail -5 /var/log/nginx/error.log 2>/dev/null || echo "로그 없음"
else
    echo "Nginx 오류 로그 파일 없음"
fi
echo

# 8. 해결 방안 제시
echo "🔧 8. 권장 해결 방안"
echo "----------------------------------------"

# Nginx 설정 문제 확인
if [ -f "/etc/nginx/conf.d/creative-energy.conf" ]; then
    if grep -q "proxy_pass.*3000/;" /etc/nginx/conf.d/creative-energy.conf; then
        echo "❌ Nginx 프록시 설정 오류 발견!"
        echo "해결방법:"
        echo "sudo sed -i 's|proxy_pass http://app.cesvc.net:3000/;|proxy_pass http://app.cesvc.net:3000;|g' /etc/nginx/conf.d/creative-energy.conf"
        echo "sudo nginx -t && sudo systemctl reload nginx"
        echo ""
    fi
fi

# App Server 문제 확인
if ! pgrep -f "node.*server.js" >/dev/null && ! pgrep -f "PM2" >/dev/null; then
    echo "❌ App Server 중지됨!"
    echo "해결방법:"
    echo "cd /home/rocky/ceweb"
    echo "pm2 start ecosystem.config.js"
    echo ""
fi

# 종합 해결 방안
echo "🚀 종합 해결 명령어:"
echo "# 1. Nginx 프록시 설정 수정"
echo "sudo sed -i 's|proxy_pass http://app.cesvc.net:3000/;|proxy_pass http://app.cesvc.net:3000;|g' /etc/nginx/conf.d/creative-energy.conf"
echo ""
echo "# 2. App Server 시작 (필요한 경우)"
echo "cd /home/rocky/ceweb && pm2 start ecosystem.config.js"
echo ""
echo "# 3. 서비스 재시작"
echo "sudo nginx -t && sudo systemctl reload nginx"
echo ""
echo "# 4. 테스트"
echo "curl http://localhost/api/orders/products"

echo ""
echo "================================================"
echo "진단 완료: $(date)"
echo "================================================"