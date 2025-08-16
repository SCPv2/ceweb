# Creative Energy 시스템 트러블슈팅 가이드

## 🔍 개요
이 가이드는 Creative Energy 3티어 아키텍처의 모든 구성 요소에 대한 종합적인 점검 및 문제 해결 방법을 제공합니다.

**시스템 구성:**
- **DB-Server**: db.cesvc.net:2866 (PostgreSQL)
- **App-Server**: app.cesvc.net:3000 (Node.js API)
- **Web-Server**: www.cesvc.net:80 (Nginx + 정적 파일)

---

## 1. 🗄️ DB-Server (db.cesvc.net:2866) 점검

### 1.1 PostgreSQL 서비스 상태 확인

```bash
# PostgreSQL 서비스 상태 확인
sudo systemctl status postgresql

# PostgreSQL 프로세스 확인
ps aux | grep postgres

# PostgreSQL 포트 확인
sudo netstat -tulpn | grep 2866

# PostgreSQL 로그 확인
sudo tail -f /var/log/postgresql/postgresql-*.log
```

### 1.2 데이터베이스 접근 권한 점검

```bash
# 로컬에서 PostgreSQL 접근 테스트
sudo -u postgres psql

# 특정 사용자로 접근 테스트
psql -h localhost -p 2866 -U ceadmin -d cedb

# 연결 설정 파일 확인
sudo cat /etc/postgresql/*/main/pg_hba.conf | grep -v "#"

# PostgreSQL 설정 파일 확인
sudo cat /etc/postgresql/*/main/postgresql.conf | grep -E "(listen_addresses|port)"
```

### 1.3 스키마 및 테이블 구조 점검

```sql
-- PostgreSQL에 접속한 후 실행
\c cedb

-- 데이터베이스 목록 확인
\l

-- 현재 데이터베이스의 스키마 확인
\dn

-- 테이블 목록 확인
\dt

-- 주요 테이블 구조 확인
\d products
\d inventory
\d orders
\d audition_files

-- 뷰 확인
\dv
\d product_inventory_view

-- 인덱스 확인
\di

-- 테이블 권한 확인
\dp

-- 사용자 권한 확인
\du

-- 테이블 데이터 개수 확인
SELECT 'products' as table_name, COUNT(*) as row_count FROM products
UNION ALL
SELECT 'inventory', COUNT(*) FROM inventory
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'audition_files', COUNT(*) FROM audition_files;

-- 주요 테이블 샘플 데이터 확인
SELECT * FROM products LIMIT 5;
SELECT * FROM inventory LIMIT 5;
SELECT * FROM product_inventory_view LIMIT 5;
```

### 1.4 네트워크 접근성 점검

```bash
# 외부에서 DB 서버 네트워크 연결 테스트
ping -c 3 db.cesvc.net

# 외부에서 DB 포트 접근 테스트
timeout 10 bash -c "cat < /dev/null > /dev/tcp/db.cesvc.net/2866"
echo $?  # 0이면 성공

# 방화벽 설정 확인
sudo firewall-cmd --list-ports
sudo firewall-cmd --list-services

# PostgreSQL 연결 통계 확인
sudo -u postgres psql -c "SELECT * FROM pg_stat_activity WHERE datname = 'cedb';"
```

---

## 2. 🖥️ App-Server (app.cesvc.net:3000) DB 연결 점검

### 2.1 DB-Server 연결성 테스트

```bash
# DB 서버 네트워크 연결 테스트
ping -c 3 db.cesvc.net

# DB 포트 접근 테스트
timeout 10 bash -c "cat < /dev/null > /dev/tcp/db.cesvc.net/2866"

# PostgreSQL 클라이언트로 직접 연결 테스트
psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c "SELECT 1;"

# DNS 해상도 확인
nslookup db.cesvc.net
dig db.cesvc.net
```

### 2.2 환경 설정 파일 점검

```bash
# 환경 변수 파일 확인
cat ~/.ceweb/.env

# DB 연결 관련 환경 변수 확인
grep DB_ ~/.ceweb/.env

# 환경 변수 파일 권한 확인
ls -la ~/.ceweb/.env

# Node.js 애플리케이션에서 환경 변수 로드 테스트
cd ~/ceweb
node -e "require('dotenv').config(); console.log(process.env.DB_HOST, process.env.DB_PORT)"
```

### 2.3 애플리케이션 DB 연결 테스트

```bash
# Node.js에서 DB 연결 테스트
cd ~/ceweb
node -e "
const pool = require('./config/database');
pool.query('SELECT 1', (err, result) => {
  if (err) {
    console.error('DB 연결 실패:', err.message);
    process.exit(1);
  } else {
    console.log('✅ DB 연결 성공:', result.rows);
    process.exit(0);
  }
});
"

# 애플리케이션 DB 설정 파일 확인
cat ~/ceweb/config/database.js

# 특정 테이블 데이터 조회 테스트
node -e "
const pool = require('./config/database');
pool.query('SELECT COUNT(*) FROM products', (err, result) => {
  if (err) console.error('쿼리 실패:', err.message);
  else console.log('Products 테이블 행 수:', result.rows[0].count);
  process.exit(0);
});
"
```

---

## 3. 🚀 App-Server 내부 애플리케이션 기능 점검

### 3.1 Node.js 애플리케이션 상태 확인

```bash
# Node.js 버전 확인
node --version
npm --version

# PM2 상태 확인
pm2 status

# PM2 프로세스 상세 정보
pm2 show creative-energy-api

# PM2 로그 확인
pm2 logs creative-energy-api --lines 20

# 애플리케이션 메모리 사용량 확인
pm2 monit

# 포트 사용 상태 확인
netstat -tulpn | grep :3000
ss -tulpn | grep :3000
```

### 3.2 애플리케이션 직접 실행 테스트

```bash
cd ~/ceweb

# PM2 중지 후 직접 실행 (디버깅용)
pm2 stop creative-energy-api
node server.js

# 정상 실행 시 다음 메시지 확인:
# ✅ PostgreSQL 외부 DB 서버 연결 성공
# Creative Energy API Server
# Host: 0.0.0.0
# Port: 3000
# Server URL: http://app.cesvc.net:3000

# Ctrl+C로 중단 후 PM2 재시작
pm2 start ecosystem.config.js
```

### 3.3 API 엔드포인트 기능 테스트

```bash
# 헬스체크 API 테스트
curl -X GET http://localhost:3000/health
curl -X GET http://localhost:3000/

# 상품 재고 조회 API 테스트
curl -X GET http://localhost:3000/api/orders/products/1/inventory

# 오디션 파일 목록 조회 API 테스트
curl -X GET http://localhost:3000/api/audition/files

# API 응답 시간 측정
curl -w "@/dev/stdout" -o /dev/null -s -X GET http://localhost:3000/health

# 오디션 파일 업로드 테스트 (샘플 파일 필요)
# curl -X POST http://localhost:3000/api/audition/upload -F "file=@test.pdf"
```

### 3.4 파일 시스템 및 권한 점검

```bash
# 애플리케이션 파일 구조 확인
ls -la ~/ceweb/
ls -la ~/ceweb/routes/
ls -la ~/ceweb/config/

# 오디션 파일 업로드 디렉토리 확인
ls -la ~/ceweb/files/audition/

# 로그 파일 확인
ls -la ~/ceweb/logs/
tail -f ~/ceweb/logs/combined.log

# 디스크 용량 확인
df -h
du -sh ~/ceweb/

# 파일 권한 확인
ls -la ~/ceweb/server.js
ls -la ~/ceweb/.env
ls -la ~/ceweb/package.json
```

---

## 4. 🌐 Web-Server에서 App-Server API 연결 점검

### 4.1 네트워크 연결성 테스트

```bash
# App-Server 네트워크 연결 테스트
ping -c 3 app.cesvc.net

# App-Server 포트 접근 테스트
timeout 10 bash -c "cat < /dev/null > /dev/tcp/app.cesvc.net/3000"

# DNS 해상도 확인
nslookup app.cesvc.net
dig app.cesvc.net

# Traceroute로 네트워크 경로 확인
traceroute app.cesvc.net
```

### 4.2 App-Server API 직접 호출 테스트

```bash
# Web-Server에서 App-Server API 직접 호출
curl -X GET http://app.cesvc.net:3000/health

# API 응답 시간 및 상세 정보 확인
curl -v -X GET http://app.cesvc.net:3000/health

# 오디션 API 테스트
curl -X GET http://app.cesvc.net:3000/api/audition/files

# 상품 재고 API 테스트
curl -X GET http://app.cesvc.net:3000/api/orders/products/1/inventory

# 연결 타임아웃 테스트
curl --connect-timeout 5 --max-time 10 http://app.cesvc.net:3000/health
```

### 4.3 Nginx 프록시를 통한 API 테스트

```bash
# Nginx를 통한 API 프록시 테스트
curl -X GET http://localhost/health
curl -X GET http://localhost/api/audition/files

# 외부에서 Web-Server를 통한 API 접근
curl -X GET http://www.cesvc.net/health
curl -X GET http://www.cesvc.net/api/audition/files

# HTTP 헤더 상세 확인
curl -I http://www.cesvc.net/health
curl -v http://www.cesvc.net/api/audition/files
```

---

## 5. 🔧 Web-Server Nginx 설정 및 권한 점검

### 5.1 Nginx 서비스 상태 확인

```bash
# Nginx 서비스 상태
sudo systemctl status nginx

# Nginx 프로세스 확인
ps aux | grep nginx

# Nginx 포트 확인
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep nginx

# Nginx 설정 테스트
sudo nginx -t

# Nginx 설정 다시 로드
sudo nginx -s reload

# Nginx 재시작
sudo systemctl restart nginx
```

### 5.2 Nginx 설정 파일 점검

```bash
# 메인 설정 파일 확인
sudo cat /etc/nginx/nginx.conf

# Creative Energy 사이트 설정 확인
sudo cat /etc/nginx/conf.d/creative-energy.conf

# 설정 파일 문법 확인
sudo nginx -t

# 설정 파일 백업 확인
ls -la /etc/nginx/*.backup

# 사용 중인 설정 파일 목록
sudo nginx -T | head -20
```

### 5.3 웹 디렉토리 권한 및 파일 점검

```bash
# 웹 루트 디렉토리 권한 확인
ls -la /home/rocky/
ls -la /home/rocky/ceweb/

# 주요 파일 권한 확인
ls -la /home/rocky/ceweb/index.html
ls -la /home/rocky/ceweb/pages/

# 파일 업로드 디렉토리 권한 확인
ls -la /home/rocky/ceweb/files/
ls -la /home/rocky/ceweb/files/audition/

# SELinux 컨텍스트 확인 (활성화된 경우)
ls -Z /home/rocky/ceweb/

# Nginx 사용자가 파일에 접근 가능한지 확인
sudo -u nginx ls /home/rocky/ceweb/
```

### 5.4 웹 파일 접근성 테스트

```bash
# 정적 파일 접근 테스트
curl -I http://localhost/index.html
curl -I http://localhost/pages/shop.html

# 업로드된 파일 접근 테스트 (파일이 있는 경우)
curl -I http://localhost/files/audition/test.pdf

# 외부에서 정적 파일 접근
curl -I http://www.cesvc.net/
curl -I http://www.cesvc.net/pages/audition.html

# 403/404 오류 확인
curl -I http://localhost/nonexistent.html
```

### 5.5 Nginx 로그 분석

```bash
# 접속 로그 확인
sudo tail -f /var/log/nginx/creative-energy-access.log

# 오류 로그 확인
sudo tail -f /var/log/nginx/creative-energy-error.log

# 일반 Nginx 로그
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# 특정 시간대 로그 필터링
sudo grep "$(date '+%d/%b/%Y:%H')" /var/log/nginx/creative-energy-access.log

# 오류 로그에서 404/500 오류 확인
sudo grep -E "(404|500)" /var/log/nginx/creative-energy-error.log
```

---

## 6. 🔧 기타 시스템 운영 참고 명령어

### 6.1 시스템 리소스 모니터링

```bash
# CPU 및 메모리 사용률 확인
top
htop

# 디스크 사용량 확인
df -h
du -sh /home/rocky/ceweb/

# 메모리 사용량 상세 확인
free -h
cat /proc/meminfo

# 시스템 로드 확인
uptime
w

# 네트워크 인터페이스 상태
ip addr show
ifconfig

# 시스템 프로세스 확인
ps aux | grep -E "(nginx|node|postgres)"
```

### 6.2 네트워크 진단 도구

```bash
# 포트 스캔
nmap -p 80,3000,2866 localhost

# 네트워크 연결 상태 확인
ss -tuln
netstat -tuln

# 특정 프로세스의 네트워크 연결
lsof -i :3000
lsof -i :80
lsof -i :2866

# TCP 연결 통계
ss -s
netstat -s
```

### 6.3 로그 관리 및 분석

```bash
# 시스템 전체 로그
sudo journalctl -f

# 특정 서비스 로그
sudo journalctl -u nginx -f
sudo journalctl -u postgresql -f

# 로그 파일 크기 확인
ls -lh /var/log/nginx/
ls -lh /home/rocky/ceweb/logs/

# 로그 파일 회전 확인
sudo logrotate -d /etc/logrotate.d/nginx

# 디스크 공간 절약을 위한 로그 정리 (주의!)
# sudo truncate -s 0 /var/log/nginx/access.log
```

### 6.4 보안 및 방화벽

```bash
# 방화벽 상태 확인
sudo firewall-cmd --state
sudo firewall-cmd --list-all

# SELinux 상태 확인 (해당하는 경우)
getenforce
sestatus

# 실행 중인 서비스 확인
sudo systemctl list-units --type=service --state=running

# 열린 포트 확인
sudo ss -tulpn | grep LISTEN

# 최근 로그인 기록
last
lastlog
```

### 6.5 백업 및 복구 관련

```bash
# 중요 설정 파일 백업
sudo cp /etc/nginx/conf.d/creative-energy.conf /etc/nginx/conf.d/creative-energy.conf.backup
cp ~/ceweb/.env ~/ceweb/.env.backup

# 데이터베이스 백업 (DB 서버에서)
pg_dump -h localhost -p 2866 -U ceadmin cedb > cedb_backup_$(date +%Y%m%d).sql

# 웹 파일 백업
tar -czf ceweb_backup_$(date +%Y%m%d).tar.gz -C /home/rocky/ ceweb/

# PM2 프로세스 목록 저장
pm2 save
```

### 6.6 성능 튜닝 및 모니터링

```bash
# Nginx 성능 통계
curl http://localhost/nginx_status

# PM2 모니터링
pm2 monit

# PostgreSQL 성능 확인 (DB 서버에서)
sudo -u postgres psql -c "SELECT * FROM pg_stat_activity;"

# 시스템 I/O 확인
iostat 1 5
iotop

# 네트워크 트래픽 모니터링
iftop
nethogs
```

---

## 🚨 주요 문제 해결 방법

### API 연결 타임아웃 문제 (AbortError)
**증상:** 브라우저에서 `AbortError: signal is aborted without reason` 및 `요청 시간이 초과되었습니다` 오류

**원인:** `api-config.js`에서 production 환경이 App-Server에 직접 접속하도록 설정되어 있음

**해결 방법:**
```bash
# api-config.js 파일의 production baseURL 수정
# 수정 전: baseURL: 'http://app.cesvc.net:3000/api'
# 수정 후: baseURL: '/api'

# 1. ceweb/scripts/api-config.js 파일 수정
sed -i "s|baseURL: 'http://app.cesvc.net:3000/api'|baseURL: '/api'|g" /home/rocky/ceweb/scripts/api-config.js

# 2. 웹 서버에서 Nginx 프록시 설정 확인
sudo nginx -t
curl -X GET http://localhost/api/orders/products

# 3. 브라우저 캐시 클리어 후 재접속
# Ctrl+F5 또는 Shift+F5로 강제 새로고침
```

### CORS 정책 오류
**증상:** `CORS 정책에 의해 접근이 거부되었습니다` 오류

**해결 방법:**
```bash
# App-Server에서 ALLOWED_ORIGINS 환경 변수 확인
grep ALLOWED_ORIGINS ~/ceweb/.env

# 필요시 도메인 추가
echo "ALLOWED_ORIGINS=http://www.cesvc.net,https://www.cesvc.net,http://www.creative-energy.net,https://www.creative-energy.net" >> ~/ceweb/.env

# App-Server 재시작
pm2 restart creative-energy-api
```

### API 응답 지연 또는 실패
**증상:** API 요청이 느리거나 500 오류 발생

**진단 단계:**
```bash
# 1. App-Server 상태 확인
pm2 status
pm2 logs creative-energy-api --lines 20

# 2. DB 연결 확인
psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c "SELECT 1;"

# 3. 네트워크 지연 확인
ping -c 5 app.cesvc.net
curl -w "시간: %{time_total}s\n" -X GET http://app.cesvc.net:3000/health

# 4. Web-Server에서 프록시 테스트
curl -X GET http://localhost/api/orders/products
```

## 🆘 긴급 복구 절차

### 전체 서비스 재시작
```bash
# DB 서버 (db.cesvc.net)
sudo systemctl restart postgresql

# App 서버 (app.cesvc.net)
pm2 restart all
# 또는
sudo systemctl restart pm2-rocky

# Web 서버 (www.cesvc.net)
sudo systemctl restart nginx
```

### 설정 파일 복구
```bash
# Nginx 설정 복구
sudo cp /etc/nginx/conf.d/creative-energy.conf.backup /etc/nginx/conf.d/creative-energy.conf
sudo nginx -t && sudo systemctl reload nginx

# 환경 변수 복구
cp ~/ceweb/.env.backup ~/ceweb/.env
pm2 restart creative-energy-api
```

### 로그 기반 문제 진단
```bash
# 최근 오류 로그 통합 확인
sudo tail -f /var/log/nginx/creative-energy-error.log /home/rocky/ceweb/logs/err.log /var/log/postgresql/postgresql-*.log
```

---

## 📋 정상 동작 체크리스트

### ✅ DB-Server 체크리스트
- [ ] PostgreSQL 서비스 실행 중
- [ ] 포트 2866 바인딩 확인
- [ ] ceadmin 사용자 접근 가능
- [ ] 주요 테이블 존재 및 데이터 확인
- [ ] 외부 접근 허용 설정 확인

### ✅ App-Server 체크리스트
- [ ] Node.js 애플리케이션 PM2로 실행 중
- [ ] DB 서버 연결 성공
- [ ] 포트 3000 정상 바인딩
- [ ] API 엔드포인트 정상 응답
- [ ] 오디션 파일 업로드 기능 동작

### ✅ Web-Server 체크리스트
- [ ] Nginx 서비스 실행 중
- [ ] 정적 파일 정상 서빙
- [ ] API 프록시 정상 동작
- [ ] 파일 다운로드 기능 동작
- [ ] 외부 접근 가능

### ✅ 전체 시스템 체크리스트
- [ ] 3티어 간 네트워크 연결 정상
- [ ] 엔드투엔드 API 테스트 통과
- [ ] 파일 업로드/다운로드 정상
- [ ] 한글 파일명 처리 정상
- [ ] 로그에 오류 메시지 없음