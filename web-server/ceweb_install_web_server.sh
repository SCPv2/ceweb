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

# Creative Energy CEWEB Server Installation Script
# Rocky Linux 9.4 Static Web Server 설치 스크립트 (Nginx만)
# 사용법: sudo bash ceweb_install_web_server.sh

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

log "Creative Energy CEWEB Server 설치를 시작합니다..."
log "서버 역할: 정적 파일 서빙 전용 (Stand-alone Web Server)"

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
mkdir -p $WEB_DIR/media/img
mkdir -p $WEB_DIR/files/audition
chown -R rocky:rocky $WEB_DIR
chmod -R 755 $WEB_DIR

log "✅ 미디어 디렉토리 생성 완료: $WEB_DIR/media/img"
log "✅ 파일 업로드 디렉토리 생성 완료: $WEB_DIR/files/audition"

# SELinux 설정 (활성화된 경우)
if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" != "Disabled" ]; then
    log "SELinux 활성화 상태 - 웹 디렉토리 접근 권한 설정 중..."
    
    # Nginx가 웹 디렉토리에 접근할 수 있도록 SELinux 컨텍스트 설정
    # httpd_exec_t (웹서버가 읽을 수 있는 콘텐츠) 사용
    semanage fcontext -a -t httpd_exec_t "$WEB_DIR(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t httpd_exec_t "$WEB_DIR/media(/.*)?" 2>/dev/null || true  
    semanage fcontext -a -t httpd_exec_t "$WEB_DIR/files(/.*)?" 2>/dev/null || true
    restorecon -Rv $WEB_DIR 2>/dev/null || true
    
    # Nginx가 홈 디렉토리에 접근할 수 있도록 허용
    setsebool -P httpd_read_user_content 1 2>/dev/null || true
    setsebool -P httpd_enable_homedirs 1 2>/dev/null || true
    
    # NFS 컨텍스트 파일 접근 허용 (파일이 nfs_t 컨텍스트를 가질 경우 대비)
    setsebool -P httpd_use_nfs 1 2>/dev/null || true
    
    log "✅ SELinux 웹 디렉토리 접근 권한 설정 완료"
    log "   - httpd_exec_t 컨텍스트 적용"
    log "   - NFS 컨텍스트 파일 접근 허용"
else
    log "SELinux가 비활성화되어 있거나 설치되지 않았습니다"
fi

# 5. CEWEB Server 도메인 설정 (master_config.json 기반)
log "Web Server 도메인 설정 중..."

# 기본 서버명 (master_config.json에서 참조)
DEFAULT_SERVERS="www.your_private_domain_name.net www.your_public_domain_name.net"
SERVER_NAMES="$DEFAULT_SERVERS"

log "✅ CEWEB Server 도메인이 master_config.json 기반으로 설정되었습니다"
log "Nginx 서버명 목록: $SERVER_NAMES"

# 6. Nginx 설정 파일 생성
log "Nginx 설정 파일 생성 중..."

# Samsung Cloud Platform Load Balancer 환경용 설정 우선 사용
if [ -f "$WEB_DIR/web-server/nginx-site.conf" ]; then
    log "Load Balancer 환경용 nginx-site.conf 파일을 사용합니다"
    
    # server_name 설정 업데이트 및 API 프록시 제거
    sed "s/server_name www\.cesvc\.net;/server_name $SERVER_NAMES;/" "$WEB_DIR/web-server/nginx-site.conf" | \
    sed '/location \/api\//,/^    }/d' | \
    sed '/location \/health/,/^    }/d' > /etc/nginx/conf.d/creative-energy.conf
    
    log "✅ nginx-site.conf를 /etc/nginx/conf.d/creative-energy.conf로 적용 완료 (API 프록시 제거됨)"
    log "서버명이 업데이트되었습니다: $SERVER_NAMES"
else
    log "기본 nginx 설정 파일을 생성합니다"
    cat > /etc/nginx/conf.d/creative-energy.conf << EOF
server {
    listen 80 default_server;
    server_name $SERVER_NAMES _;
    
    # 파일 업로드 크기 제한 (오디션 파일용)
    client_max_body_size 100M;
    
    # 정적 파일 서빙 (HTML, CSS, JS, 이미지 등)
    location / {
        root /home/rocky/ceweb;
        index index.html;
        try_files \$uri \$uri/ /index.html;
        
        # 정적 파일 캐싱
        location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf)\$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # Files 폴더 - 업로드된 파일 다운로드용
    location /files/ {
        root /home/rocky/ceweb;
        autoindex off;  # 보안상 디렉터리 리스팅 비활성화
        
        # 파일 다운로드를 위한 헤더 설정
        add_header Content-Disposition "attachment";
        add_header X-Content-Type-Options "nosniff";
        
        # 허용된 파일 확장자만 접근 가능
        location ~* \.(pdf|doc|docx|mp3|mp4|jpg|jpeg|png)\$ {
            expires 30d;
            add_header Cache-Control "public";
        }
        
        # 실행 파일 차단
        location ~* \.(php|php3|php4|php5|phtml|pl|py|jsp|asp|sh|cgi|exe|bat|com)\$ {
            deny all;
            return 403;
        }
    }
    
    # Media 폴더 - 이미지 파일 서빙용
    location /media/ {
        root /home/rocky/ceweb;
        expires 1y;
        add_header Cache-Control "public, immutable";
        
        # 이미지 파일만 허용
        location ~* /media/.*\.(jpg|jpeg|png|gif|ico|svg|webp)\$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
        
        # 실행 파일 및 기타 파일 차단
        location ~* /media/.*\.(php|php3|php4|php5|phtml|pl|py|jsp|asp|sh|cgi|exe|bat|com|txt|md)\$ {
            deny all;
            return 403;
        }
    }
    
    # Web-Server 폴더 - API 설정 파일 전용 (보안 강화)
    location /web-server/ {
        root /home/rocky/ceweb;
        
        # JS 파일만 허용 (api-config.js 등)
        location ~* \.js\$ {
            expires 1d;
            add_header Cache-Control "public";
        }
        
        # 설치 스크립트 및 문서 파일 차단
        location ~* \.(sh|md|txt|conf|yml|yaml)\$ {
            deny all;
            return 403;
        }
        
        # 디렉토리 리스팅 금지
        autoindex off;
    }
    
    # VM 정보 엔드포인트 - Load Balancer 서버 상태용
    location /vm-info.json {
        alias /home/rocky/ceweb/vm-info.json;
        add_header Content-Type application/json;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma no-cache;
        add_header Expires 0;
    }
    
    # 보안 헤더
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # 로그 설정
    access_log /var/log/nginx/creative-energy-access.log;
    error_log /var/log/nginx/creative-energy-error.log;
}
EOF
fi

# 7. Nginx 설정 테스트
log "Nginx 설정 테스트 중..."
nginx -t

# 8. 기본 서버 블록 비활성화 (프록시 충돌 방지)
log "기본 서버 블록 비활성화 중..."
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
sed -i '/^    server {/,/^    }/s/^/#/' /etc/nginx/nginx.conf

# 9. Nginx 재시작
log "Nginx 재시작 중..."
systemctl restart nginx

# 10. SELinux 설정
log "SELinux 설정 중..."
if command -v getenforce &> /dev/null && getenforce | grep -q "Enforcing"; then
    log "SELinux가 활성화되어 있습니다. 웹 서버 접근 권한을 설정합니다..."
    
    # Nginx가 사용자 홈 디렉토리의 컨텐츠를 읽을 수 있도록 허용
    setsebool -P httpd_read_user_content on
    
    # 웹 디렉토리의 SELinux 컨텍스트 복원
    restorecon -Rv $WEB_DIR
    
    log "✅ SELinux 설정 완료"
else
    log "SELinux가 비활성화되어 있거나 설치되지 않았습니다."
fi

# 11. 최종 권한 설정
log "웹 디렉토리 권한 설정 중..."
chmod 755 /home/rocky  # 홈 디렉토리 접근 권한
chmod -R 755 $WEB_DIR
chown -R rocky:rocky $WEB_DIR
log "✅ 권한 설정 완료"

# 12. Samsung Cloud Platform Bootstrap 스크립트 설정
log "VM Bootstrap 스크립트 설정 중..."

BOOTSTRAP_SCRIPT="$WEB_DIR/web-server/bootstrap_web_vm.sh"
if [ -f "$BOOTSTRAP_SCRIPT" ]; then
    log "bootstrap_web_vm.sh 스크립트를 찾았습니다"
    
    # Bootstrap 스크립트를 시스템 위치로 복사
    cp "$BOOTSTRAP_SCRIPT" /usr/local/bin/
    chmod +x /usr/local/bin/bootstrap_web_vm.sh
    
    # rc.local에 Bootstrap 스크립트 추가 (VM 부팅 시 자동 실행)
    if ! grep -q "bootstrap_web_vm.sh" /etc/rc.local 2>/dev/null; then
        echo '#!/bin/bash' > /etc/rc.local
        echo '/usr/local/bin/bootstrap_web_vm.sh' >> /etc/rc.local
        chmod +x /etc/rc.local
        log "✅ VM Bootstrap 스크립트 자동 실행 설정 완료"
    else
        log "Bootstrap 스크립트가 이미 rc.local에 설정되어 있습니다"
    fi
    
    log "✅ Samsung Cloud Platform Load Balancer 환경 설정 완료"
else
    warn "⚠️ bootstrap_web_vm.sh 스크립트를 찾을 수 없습니다: $BOOTSTRAP_SCRIPT"
fi

# 13. VM 정보 파일 생성 (Load Balancer 환경용)
log "VM 정보 파일 생성 중..."

# 현재 VM 정보 수집
VM_HOSTNAME=$(hostname -s)
VM_IP=$(hostname -I | awk '{print $1}')
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# VM 번호 추출 (hostname에서 숫자 추출: webvm111r -> 1, webvm112r -> 2)
VM_NUMBER=""
if [[ $VM_HOSTNAME =~ webvm([0-9]+) ]]; then
    FULL_NUMBER=${BASH_REMATCH[1]}
    # 마지막 자리 숫자를 VM 번호로 사용
    VM_NUMBER="${FULL_NUMBER: -1}"
else
    VM_NUMBER="1"  # 기본값
fi

log "VM 정보: 호스트명=$VM_HOSTNAME, IP=$VM_IP, VM번호=$VM_NUMBER"

# vm-info.json 파일 생성
VM_INFO_FILE="$WEB_DIR/vm-info.json"
cat > "$VM_INFO_FILE" << EOF
{
  "hostname": "$VM_HOSTNAME",
  "ip_address": "$VM_IP",
  "vm_number": "$VM_NUMBER",
  "server_type": "ceweb-server",
  "load_balancer": {
    "name": "www.your_private_domain_name.net",
    "ip": "10.1.1.100",
    "policy": "Round Robin"
  },
  "cluster": {
    "servers": [
      {
        "hostname": "webvm111r",
        "ip": "10.1.1.111",
        "vm_number": "1"
      },
      {
        "hostname": "webvm112r", 
        "ip": "10.1.1.112",
        "vm_number": "2"
      }
    ]
  },
  "timestamp": "$CURRENT_TIME",
  "version": "1.0"
}
EOF

chmod 644 "$VM_INFO_FILE"
chown rocky:rocky "$VM_INFO_FILE"

log "✅ VM 정보 파일 생성 완료: $VM_INFO_FILE"

# 14. index_lb.html을 index.html로 복사
log "index_lb.html을 index.html로 복사 중..."
INDEX_LB_FILE="$WEB_DIR/index_lb.html"
INDEX_FILE="$WEB_DIR/index.html"

if [ -f "$INDEX_LB_FILE" ]; then
    cp "$INDEX_LB_FILE" "$INDEX_FILE"
    chown rocky:rocky "$INDEX_FILE"
    chmod 644 "$INDEX_FILE"
    log "✅ index_lb.html을 index.html로 복사 완료"
else
    warn "⚠️ index_lb.html 파일을 찾을 수 없습니다: $INDEX_LB_FILE"
    warn "   웹 파일 배포 후 수동으로 다음 명령어를 실행하세요:"
    warn "   cp $INDEX_LB_FILE $INDEX_FILE"
fi

# 15. 설치 완료 메시지
log "================================================================"
log "Creative Energy CEWEB Server 설치가 완료되었습니다!"
log "================================================================"
log ""
log "🏗️ 설치된 구성:"
log "- Web Server: Rocky Linux 9.4 + Nginx (Static Files Only)"
log "- 도메인: www.your_private_domain_name.net, www.your_public_domain_name.net"
log "- 정적 파일 디렉토리: $WEB_DIR"
log ""
log "📋 다음 단계를 진행해주세요:"
log ""
log "1. 정적 파일 업로드:"
log "   HTML, CSS, JS 파일을 $WEB_DIR 에 업로드하세요"
log "   예: scp -r /local/html-files/* user@server:$WEB_DIR/"
log ""
log "2. 미디어 파일 업로드:"
log "   이미지 파일을 $WEB_DIR/media/img/ 에 업로드하세요"
log "   예: scp /local/images/*.png user@server:$WEB_DIR/media/img/"
log "   접근 URL: http://도메인/media/img/파일명.png"
log ""
log "3. DNS 설정 확인:"
if [[ -n "$CUSTOM_DOMAIN" ]]; then
    log "   $CUSTOM_DOMAIN → 이 서버 IP"
fi
log "   www.your_private_domain_name.net → 이 서버 IP"
log "   www.your_public_domain_name.net → 이 서버 IP"
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
log "- 이 서버는 정적 파일 서빙만 수행합니다 (Stand-alone Web Server)"
log "- API 기능은 제거되어 순수 정적 웹사이트로만 작동합니다"
log "- SELinux 설정이 자동으로 구성되어 /media/ 및 /files/ 디렉토리 접근 가능"
log "- index_lb.html이 index.html로 자동 복사되었습니다"
log ""
log "🧪 서버 상태 테스트 명령어:"
log "curl -I http://localhost/"
log "curl -X GET http://localhost/vm-info.json  # VM 정보 확인"
log "curl -I http://localhost/media/img/  # 미디어 디렉토리 접근 테스트"
log ""
log "🌐 Samsung Cloud Platform Load Balancer 환경:"
log "- VM Bootstrap 자동 실행: VM 부팅 시 자동으로 서비스 시작"
log "- Server Status Icons: Web-1, Web-2 실시간 상태 표시"
log "- 현재 서빙 서버는 녹색, 나머지 서버는 회색으로 표시"
log "- /vm-info.json 엔드포인트에서 실시간 VM 정보 제공"
log ""
log "🔄 VM Bootstrap 수동 실행 (테스트용):"
log "/usr/local/bin/bootstrap_web_vm.sh"
log ""
log "================================================================"