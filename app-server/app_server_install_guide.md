# Creative Energy App Server 설치 가이드

## 🖥️ App Server 전용 설치 가이드 (app.cesvc.net)

**서버 역할**: API 처리 + 비즈니스 로직  
**설치 대상**: app.cesvc.net  
**필요 소프트웨어**: Node.js, PM2, PostgreSQL Client  
**DB 연결**: db.cesvc.net:2866  

---

## 📋 사전 요구사항

- Rocky Linux 9.4 설치 완료
- Root 권한 또는 sudo 권한
- 인터넷 연결
- DB Server (db.cesvc.net:2866) 접근 가능
- DB 관리자 계정 정보 (ceadmin)

---

## 🚀 자동 설치 (권장)

### 1단계: 설치 스크립트 다운로드 및 실행

```bash
# root 사용자로 로그인
sudo su -

# 설치 스크립트 다운로드 (또는 업로드)
# wget https://your-repo/install_app_server.sh
# 또는 파일을 직접 업로드

# 실행 권한 부여
chmod +x install_app_server.sh

# 설치 실행
./install_app_server.sh
```

### 2단계: 설치 완료 확인

```bash
# Node.js 버전 확인
node --version  # v20.x.x

# PM2 상태 확인
sudo -u creative-energy pm2 --version

# DB 연결 테스트
sudo -u creative-energy /home/creative-energy/test_db_connection.sh
```

---

## 🔧 수동 설치

### 1단계: 시스템 업데이트

```bash
# 시스템 패키지 업데이트
sudo dnf update -y
sudo dnf upgrade -y
sudo dnf install -y epel-release
sudo dnf install -y wget curl git vim nano htop net-tools telnet postgresql
```

### 2단계: 방화벽 설정 (App Server용)

```bash
# 방화벽 시작 및 활성화
sudo systemctl start firewalld
sudo systemctl enable firewalld

# App Server용 포트만 개방 (3000포트)
sudo firewall-cmd --permanent --add-port=3000/tcp

# 방화벽 규칙 적용
sudo firewall-cmd --reload

# 설정 확인 (3000포트만 열려있어야 함)
sudo firewall-cmd --list-ports
```

### 3단계: Node.js 20.x 설치

```bash
# NodeSource 저장소 추가
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -

# Node.js 설치
sudo dnf install -y nodejs

# 버전 확인
node --version
npm --version
```

### 4단계: PM2 프로세스 매니저 설치

```bash
# PM2 전역 설치
sudo npm install -g pm2

# 버전 확인
pm2 --version
```

### 5단계: rocky 사용자 설정

```bash
# rocky 사용자가 없으면 생성
sudo useradd -m -s /bin/bash rocky || echo "rocky 사용자가 이미 존재합니다"
sudo usermod -aG wheel rocky

# 사용자 전환
sudo su - rocky
```

### 6단계: 애플리케이션 디렉토리 설정

```bash
# 애플리케이션 디렉토리 생성 (rocky 사용자의 홈 디렉토리에)
mkdir -p ~/ceweb
mkdir -p ~/ceweb/logs

# 디렉토리 구조 확인
ls -la ~/ceweb/
```

---

## 🗄️ 데이터베이스 연결 설정

### 1단계: DB Server 네트워크 연결 테스트

```bash
# DB 서버 네트워크 연결 확인
ping -c 3 db.cesvc.net

# DB 포트 연결 확인
timeout 10 bash -c "cat < /dev/null > /dev/tcp/db.cesvc.net/2866"
echo $?  # 0이면 성공
```

### 2단계: PostgreSQL 직접 연결 테스트

```bash
# psql로 DB 서버 연결 (비밀번호 입력 필요)
psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb

# 연결 성공 시 테스트 쿼리
SELECT 1;
SELECT current_database();
SELECT current_user;

# 테이블 존재 확인
\dt

# 연결 종료
\q
```

### 3단계: 환경 변수 설정

```bash
# 환경 변수 파일 생성
vim ~/ceweb/.env
```

**환경 변수 파일 내용**:

```env
# External Database Configuration
DB_HOST=db.cesvc.net
DB_PORT=2866
DB_NAME=cedb
DB_USER=ceadmin
DB_PASSWORD=실제_DB_비밀번호_입력

# Connection Pool Settings
DB_POOL_MIN=2
DB_POOL_MAX=10
DB_POOL_IDLE_TIMEOUT=30000
DB_POOL_CONNECTION_TIMEOUT=5000

# Server Configuration (App Server 전용)
PORT=3000
NODE_ENV=production
BIND_HOST=0.0.0.0

# CORS Configuration (Web Server 도메인 허용)
ALLOWED_ORIGINS=http://www.cesvc.net,https://www.cesvc.net,http://www.creative-energy.net,https://www.creative-energy.net

# Security
JWT_SECRET=복잡한_JWT_시크릿_키_입력

# Logging
LOG_LEVEL=info
```

```bash
# 파일 권한 설정 (보안)
chmod 600 ~/ceweb/.env
```

---

## 📦 애플리케이션 코드 배포

### 1단계: 애플리케이션 파일 업로드

```bash
# 로컬에서 서버로 애플리케이션 코드 업로드
# scp -r /local/path/to/app-server/* rocky@app.cesvc.net:~/ceweb/

# 또는 Git을 통한 배포
# git clone https://your-repo.git ~/ceweb/
```

### 2단계: 필수 파일 확인

```bash
cd ~/ceweb/

# 필수 파일들이 존재하는지 확인
ls -la server.js package.json
ls -la config/database.js
ls -la routes/orders.js
ls -la .env
```

**필요한 파일 구조**:
```
~/ceweb/
├── server.js                 # 메인 애플리케이션 파일
├── package.json              # 의존성 정의
├── .env                      # 환경 변수
├── config/
│   └── database.js          # DB 연결 설정
├── routes/
│   └── orders.js           # API 라우트
└── logs/                   # 로그 디렉토리
```

### 3단계: 의존성 설치

```bash
cd ~/ceweb/

# package.json이 있는지 확인
cat package.json

# NPM 의존성 설치
npm install

# 또는 운영 환경용으로만 설치
npm install --production
```

---

## 🚀 애플리케이션 실행

### 1단계: 직접 실행 테스트 (디버깅)

```bash
cd ~/ceweb/

# 환경 변수 로드 후 직접 실행
node server.js

# 정상 실행 시 다음과 같은 메시지 확인:
# ✅ PostgreSQL 외부 DB 서버 연결 성공
# Creative Energy API Server
# Host: 0.0.0.0
# Port: 3000
# Server URL: http://app.cesvc.net:3000

# Ctrl+C로 중단
```

### 2단계: PM2 Ecosystem 설정

```bash
# PM2 설정 파일 생성
vim ~/ceweb/ecosystem.config.js
```

**PM2 설정 파일 내용**:

```javascript
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
```

### 3단계: PM2로 애플리케이션 시작

```bash
cd ~/ceweb/

# PM2로 애플리케이션 시작
pm2 start ecosystem.config.js

# 상태 확인
pm2 status

# 로그 확인
pm2 logs creative-energy-api

# 애플리케이션 정보 확인
pm2 show creative-energy-api
```

### 4단계: PM2 자동 시작 설정

```bash
# PM2 자동 시작 설정 (root 권한으로 실행)
sudo su -

# PM2 startup 설정
pm2 startup systemd -u rocky --hp /home/rocky

# 위 명령어 실행 후 나오는 명령어를 복사해서 실행
# 예: sudo env PATH=$PATH:/usr/bin...

# rocky 사용자로 돌아가서 설정 저장
sudo su - rocky
pm2 save
```

---

## 🧪 API 테스트 및 검증

### 1단계: 기본 API 응답 테스트

```bash
# 헬스체크 엔드포인트 테스트
curl -X GET http://localhost:3000/health

# 예상 응답:
# {
#   "success": true,
#   "message": "Server is healthy",
#   "database": "Connected"
# }
```

### 2단계: 데이터베이스 연동 API 테스트

```bash
# 상품 재고 조회 API 테스트
curl -X GET http://localhost:3000/api/orders/products/1/inventory

# 정상 응답 예시:
# {
#   "success": true,
#   "product": {
#     "id": 1,
#     "title": "상품명",
#     "stock_quantity": 100,
#     "stock_display": "100"
#   }
# }

# 에러 응답 시:
# {
#   "success": false,
#   "message": "서버 오류가 발생했습니다."
# }
```

### 3단계: 외부 접근 테스트

```bash
# 다른 서버에서 접근 테스트
curl -X GET http://app.cesvc.net:3000/health

# Web Server에서 접근 테스트 (Web Server가 설정된 경우)
curl -X GET http://www.cesvc.net/health
```

---

## 🗄️ 데이터베이스 스키마 및 초기 데이터 설정

### 1단계: 스키마 파일 적용

```bash
# 스키마 파일이 있는 경우 적용
psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -f /path/to/complete_database_v2_ultra_compatible.sql

# 또는 pgAdmin4를 통해 스키마 적용
```

### 2단계: 테이블 및 데이터 확인

```bash
# DB 연결 후 테이블 확인
psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb

# 테이블 목록 확인
\dt

# 주요 테이블 데이터 확인
SELECT COUNT(*) FROM products;
SELECT COUNT(*) FROM inventory;
SELECT * FROM product_inventory_view LIMIT 3;

# 연결 종료
\q
```

---

## 📊 모니터링 및 관리

### 일상 관리 명령어

```bash
# PM2 상태 확인
pm2 status

# 애플리케이션 재시작
pm2 restart creative-energy-api

# 로그 실시간 확인
pm2 logs creative-energy-api

# 메모리 사용량 확인
pm2 monit

# 프로세스 중지
pm2 stop creative-energy-api

# 프로세스 삭제
pm2 delete creative-energy-api
```

### DB 연결 모니터링

```bash
# DB 연결 테스트 스크립트 (설치 시 자동 생성됨)
~/test_db_connection.sh

# 애플리케이션 모니터링 스크립트
~/monitor_app.sh

# 포트 사용 상태 확인
netstat -tulpn | grep :3000

# DB 연결 상태 확인
netstat -an | grep :2866
```

### 로그 파일 위치

- **PM2 통합 로그**: `~/ceweb/logs/combined.log`
- **에러 로그**: `~/ceweb/logs/err.log`
- **출력 로그**: `~/ceweb/logs/out.log`

---

## 🚨 트러블슈팅

### 1. 애플리케이션이 시작되지 않는 경우

```bash
# PM2 로그 확인
pm2 logs creative-energy-api

# 직접 실행으로 에러 메시지 확인
cd ~/ceweb/
node server.js

# 환경 변수 확인
cat .env

# 파일 권한 확인
ls -la server.js package.json .env
```

### 2. 데이터베이스 연결 오류

```bash
# DB 네트워크 연결 확인
ping -c 3 db.cesvc.net

# DB 포트 연결 확인
timeout 5 bash -c "cat < /dev/null > /dev/tcp/db.cesvc.net/2866"

# psql로 직접 연결 테스트
psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb

# 환경 변수 확인 (DB_PASSWORD 등)
grep DB_ .env
```

### 3. API 요청이 실패하는 경우

```bash
# 로컬 API 테스트
curl -v http://localhost:3000/health

# 포트 확인
netstat -tulpn | grep :3000

# 방화벽 확인
sudo firewall-cmd --list-ports

# CORS 설정 확인
grep ALLOWED_ORIGINS .env
```

### 4. 일반적인 에러 해결

**"서버 오류가 발생했습니다" 메시지**:
- DB 연결 실패: 비밀번호, 네트워크 확인
- 환경 변수 누락: .env 파일 확인
- 테이블 없음: 스키마 적용 확인

**포트 접근 불가**:
- 방화벽 설정 확인
- BIND_HOST 설정 확인 (0.0.0.0)
- PM2 실행 상태 확인

---

## ✅ 설치 완료 체크리스트

### 시스템 설정
- [ ] Rocky Linux 9.4 업데이트 완료
- [ ] 방화벽 포트 3000 개방 완료
- [ ] Node.js 20.x 설치 완료
- [ ] PM2 설치 완료
- [ ] PostgreSQL 클라이언트 설치 완료

### 사용자 및 디렉토리
- [ ] rocky 사용자 생성 완료
- [ ] 애플리케이션 디렉토리 `/home/rocky/ceweb` 생성 완료
- [ ] 로그 디렉토리 생성 완료

### 데이터베이스 연결
- [ ] DB 서버 네트워크 연결 테스트 성공
- [ ] psql로 직접 DB 연결 테스트 성공
- [ ] 환경 변수 (.env) 설정 완료
- [ ] DB 스키마 적용 완료

### 애플리케이션
- [ ] 애플리케이션 코드 업로드 완료
- [ ] NPM 의존성 설치 완료
- [ ] 직접 실행 테스트 성공
- [ ] PM2 설정 및 실행 완료
- [ ] PM2 자동 시작 설정 완료

### API 테스트
- [ ] 헬스체크 API (/health) 테스트 성공
- [ ] 데이터베이스 연동 API 테스트 성공
- [ ] 외부에서 API 접근 테스트 성공

---

## 📞 다음 단계

1. **Web Server** 연동 확인 (API 프록시 테스트)
2. **프론트엔드** 배포 및 연동
3. **모니터링** 및 **백업** 시스템 구축
4. **HTTPS** 및 보안 강화

**중요**: Web Server가 이 App Server로 API 요청을 정상적으로 프록시할 수 있어야 합니다!