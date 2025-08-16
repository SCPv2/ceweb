# Creative Energy Web Server 설치 가이드

## 🌐 Web Server 전용 설치 가이드 (www.cesvc.net, www.creative-energy.net)

**서버 역할**: 정적 파일 서빙 + API 프록시  
**설치 대상**: www.cesvc.net 또는 www.creative-energy.net  
**필요 소프트웨어**: Nginx만  

---

## 📋 사전 요구사항

- Rocky Linux 9.4 설치 완료
- Root 권한 또는 sudo 권한
- 인터넷 연결
- App Server (app.cesvc.net) 주소 확인

---

## 🚀 자동 설치 (권장)

### 1단계: 설치 스크립트 다운로드 및 실행

```bash
# root 사용자로 로그인
sudo su -

# 설치 스크립트 다운로드 (또는 업로드)
# wget https://your-repo/install_web_server.sh
# 또는 파일을 직접 업로드

# 실행 권한 부여
chmod +x install_web_server.sh

# 설치 실행
./install_web_server.sh
```

### 1-1단계: Samsung Cloud Platform VM Bootstrap 설정

```bash
# VM 이미지 생성 후 부팅 시 자동 실행되도록 설정
sudo cp /home/rocky/ceweb/web-server/bootstrap_web_vm.sh /etc/rc.d/init.d/
sudo chmod +x /etc/rc.d/init.d/bootstrap_web_vm.sh

# 또는 systemd 서비스로 등록
sudo cp /home/rocky/ceweb/web-server/bootstrap_web_vm.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/bootstrap_web_vm.sh

# cloud-init 설정 (VM 이미지 생성 시 포함)
echo "/usr/local/bin/bootstrap_web_vm.sh" >> /etc/rc.local
chmod +x /etc/rc.local
```

### 2단계: 설치 완료 확인

```bash
# Nginx 상태 확인
systemctl status nginx

# 방화벽 포트 확인
firewall-cmd --list-ports
# 예상 결과: 80/tcp 443/tcp

# App Server 연결 테스트
/root/test_app_server.sh
```

---

## 🔧 수동 설치

### 1단계: 시스템 업데이트

```bash
# 시스템 패키지 업데이트
sudo dnf update -y
sudo dnf upgrade -y
sudo dnf install -y epel-release
sudo dnf install -y wget curl git vim nano htop net-tools
```

### 2단계: 방화벽 설정

```bash
# 방화벽 시작 및 활성화
sudo systemctl start firewalld
sudo systemctl enable firewalld

# 웹 서버용 포트 개방
sudo firewall-cmd --permanent --add-port=80/tcp    # HTTP
sudo firewall-cmd --permanent --add-port=443/tcp   # HTTPS

# 방화벽 규칙 적용
sudo firewall-cmd --reload

# 설정 확인
sudo firewall-cmd --list-ports
```

### 3단계: Nginx 설치

```bash
# Nginx 설치
sudo dnf install -y nginx

# Nginx 시작 및 자동 시작 설정
sudo systemctl start nginx
sudo systemctl enable nginx

# 상태 확인
sudo systemctl status nginx
```

### 4단계: 웹 디렉토리 설정

```bash
# rocky 사용자가 없으면 생성
sudo useradd -m -s /bin/bash rocky || echo "rocky 사용자가 이미 존재합니다"

# 작업 디렉토리 생성
sudo mkdir -p /home/rocky/ceweb

# 권한 설정
sudo chown -R rocky:rocky /home/rocky/ceweb
sudo chmod -R 755 /home/rocky/ceweb
```

### 5단계: Nginx 설정

#### Samsung Cloud Platform Load Balancer 환경 (권장)

```bash
# 미리 준비된 nginx 설정 파일 사용 (Rocky Linux용)
sudo cp /home/rocky/ceweb/web-server/nginx-site.conf /etc/nginx/conf.d/creative-energy.conf

# 설정 적용 확인
sudo nginx -t
```

#### 수동 설정 파일 생성 (대안)

```bash
# 설정 파일 생성
sudo vim /etc/nginx/conf.d/creative-energy.conf
```

**설정 파일 내용** (`nginx-site.conf` 파일 참조):

```nginx
server {
    listen 80;
    server_name www.cesvc.net;
    
    root /home/rocky/ceweb;
    index index.html index.htm;
    
    # 정적 파일 서빙
    location / {
        try_files $uri $uri/ =404;
    }
    
    # VM 정보 엔드포인트 - bootstrap 스크립트에서 생성한 파일 제공
    location /vm-info.json {
        alias /home/rocky/ceweb/vm-info.json;
        add_header Content-Type application/json;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma no-cache;
        add_header Expires 0;
    }
    
    # API 프록시 (App Server로 전달) - Load Balancer 환경
    location /api/ {
        proxy_pass http://app.cesvc.net:3000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 60s;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
    }
    
    # 미디어 파일 캐시 설정
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # 보안 헤더
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # 로그 설정
    access_log /var/log/nginx/ceweb_access.log;
    error_log /var/log/nginx/ceweb_error.log;
}
```

### 6단계: Nginx 설정 적용

```bash
# 설정 파일 문법 검사
sudo nginx -t

# Nginx 재시작
sudo systemctl restart nginx
```

---

## 📁 정적 파일 업로드

### 1단계: HTML, CSS, JS 파일 업로드

```bash
# 로컬에서 서버로 파일 업로드
scp -r /local/path/to/html-files/* rocky@www.cesvc.net:/home/rocky/ceweb/

# 또는 rocky 사용자로 직접 업로드
# rocky 사용자 권한으로 파일 복사
sudo -u rocky cp -r /tmp/uploaded-files/* /home/rocky/ceweb/

# 권한 설정
sudo chown -R rocky:rocky /home/rocky/ceweb
sudo chmod -R 755 /home/rocky/ceweb
```

### 2단계: 디렉토리 구조 확인

```bash
# 최종 구조 확인
ls -la /home/rocky/ceweb/
```

**예상 구조**:
```
/home/rocky/ceweb/
├── index.html
├── pages/
│   ├── shop.html
│   ├── order.html
│   └── notice.html
├── media/
│   ├── images...
│   └── ...
└── js/
    └── api-config.js
```

---

## 🧪 테스트 및 검증

### 1단계: 기본 웹 서비스 테스트

```bash
# 로컬에서 웹 서버 응답 확인
curl -I http://localhost

# 정적 파일 접근 테스트
curl http://localhost/index.html
```

### 2단계: App Server 연결 테스트

```bash
# App Server 연결 테스트 스크립트 실행
/root/test_app_server.sh

# 수동 테스트
ping -c 3 app.cesvc.net
timeout 5 bash -c "cat < /dev/null > /dev/tcp/app.cesvc.net/3000"
```

### 3단계: API 프록시 및 서버 상태 테스트

```bash
# API 프록시가 정상 동작하는지 확인 (App Server가 실행 중일 때)
curl http://localhost/health
curl http://localhost/api/orders/products

# VM 정보 엔드포인트 테스트 (Server Status Icons용)
curl http://localhost/vm-info.json

# 응답 예시:
# {
#   "vm_type": "web",
#   "vm_number": "1",
#   "hostname": "web-server-01",
#   "ip_address": "10.0.1.100",
#   "startup_time": "2024-08-16T10:30:00Z",
#   "nginx_status": "active",
#   "load_balancer": "webLB"
# }
```

### 4단계: Load Balancer 환경 테스트

```bash
# Server Status Icons가 정상 동작하는지 브라우저에서 확인
# - shop.html에서 Web-1, Web-2, App-1, App-2 아이콘 표시 확인
# - 현재 서빙 중인 서버는 녹색, 나머지는 회색 표시 확인

# Bootstrap 스크립트 수동 실행 테스트
sudo /usr/local/bin/bootstrap_web_vm.sh

# VM 정보 파일 생성 확인
cat /home/rocky/ceweb/vm-info.json
```

---

## 📊 모니터링 및 관리

### 일상 관리 명령어

```bash
# Nginx 상태 확인
sudo systemctl status nginx

# Nginx 재시작
sudo systemctl restart nginx

# 설정 파일 문법 검사
sudo nginx -t

# 접근 로그 실시간 확인
sudo tail -f /var/log/nginx/creative-energy-access.log

# 에러 로그 실시간 확인
sudo tail -f /var/log/nginx/creative-energy-error.log

# App Server 연결 상태 확인
/root/test_app_server.sh
```

### 로그 파일 위치

- **접근 로그**: `/var/log/nginx/creative-energy-access.log`
- **에러 로그**: `/var/log/nginx/creative-energy-error.log`
- **Nginx 기본 로그**: `/var/log/nginx/access.log`, `/var/log/nginx/error.log`

---

## 🚨 트러블슈팅

### 1. Nginx가 시작되지 않는 경우

```bash
# 에러 로그 확인
sudo journalctl -u nginx

# 설정 파일 문법 검사
sudo nginx -t

# 포트 충돌 확인
sudo netstat -tulpn | grep :80
```

### 2. 정적 파일이 로드되지 않는 경우

```bash
# 파일 권한 확인
ls -la /home/rocky/ceweb/

# SELinux 확인 (필요시)
sudo setsebool -P httpd_can_network_connect 1

# 파일 존재 여부 확인
sudo find /home/rocky/ceweb -name "*.html"
```

### 3. API 프록시가 동작하지 않는 경우

```bash
# App Server 연결 확인
ping app.cesvc.net
telnet app.cesvc.net 3000

# Nginx 에러 로그 확인
sudo tail -20 /var/log/nginx/creative-energy-error.log
```

---

## ✅ 설치 완료 체크리스트

### 기본 설치
- [ ] Rocky Linux 9.4 업데이트 완료
- [ ] 방화벽 포트 80, 443 개방 완료
- [ ] Nginx 설치 및 실행 완료
- [ ] 정적 파일 디렉토리 `/home/rocky/ceweb` 생성 완료
- [ ] Nginx 설정 파일 생성 완료 (`nginx-site.conf` 적용)
- [ ] HTML, CSS, JS 파일 업로드 완료
- [ ] 로컬 웹 서비스 접근 테스트 완료
- [ ] App Server (app.cesvc.net:3000) 연결 테스트 완료
- [ ] API 프록시 동작 확인 (App Server 실행 시)

### Samsung Cloud Platform Load Balancer 환경
- [ ] VM Bootstrap 스크립트 (`bootstrap_web_vm.sh`) 설정 완료
- [ ] `/vm-info.json` 엔드포인트 동작 확인
- [ ] Server Status Icons 표시 확인 (Web-1, Web-2, App-1, App-2)
- [ ] 현재 서빙 서버 녹색 표시, 나머지 회색 표시 확인
- [ ] VM 이미지에서 자동 부팅 스크립트 실행 확인
- [ ] Load Balancer에서 Health Check 응답 확인

---

## 📞 다음 단계

1. **App Server** 설치 및 설정 (별도 가이드 참조)
2. **DB Server** 연결 및 데이터 설정
3. **DNS 설정**: 도메인을 이 서버 IP로 연결
4. **SSL 인증서** 설치 (HTTPS 적용)

**중요**: App Server가 실행되어야 API 요청이 정상적으로 동작합니다!