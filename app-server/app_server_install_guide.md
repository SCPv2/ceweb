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

### 1-1단계: Samsung Cloud Platform VM Bootstrap 설정

```bash
# VM 이미지 생성 후 부팅 시 자동 실행되도록 설정
sudo cp /home/rocky/ceweb/app-server/bootstrap_app_vm.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/bootstrap_app_vm.sh

# cloud-init 설정 (VM 이미지 생성 시 포함)
echo "/usr/local/bin/bootstrap_app_vm.sh" >> /etc/rc.local
chmod +x /etc/rc.local
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

### 4단계: Samsung Cloud Platform Load Balancer 환경 테스트

```bash
# VM 정보 확인 (Bootstrap 스크립트 실행 후)
cat /home/rocky/ceweb/vm-info.json

# 응답 예시:
# {
#   "vm_type": "app",
#   "vm_number": "1",
#   "hostname": "app-server-01",
#   "ip_address": "10.0.2.100",
#   "startup_time": "2024-08-16T10:30:00Z",
#   "app_status": "online",
#   "node_version": "v20.x.x",
#   "load_balancer": "appLB"
# }

# Server Status Icons용 Health API 테스트 (서버 식별 정보 포함)
curl -X GET http://localhost:3000/health

# Bootstrap 스크립트 수동 실행 테스트
sudo /usr/local/bin/bootstrap_app_vm.sh

# 상품 API에서 서버 정보 확인
curl -X GET http://localhost:3000/api/orders/products | jq '.server_info'
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

### Samsung Cloud Platform Load Balancer 환경
- [ ] VM Bootstrap 스크립트 (`bootstrap_app_vm.sh`) 설정 완료
- [ ] VM 정보 파일 (`vm-info.json`) 생성 확인
- [ ] Health API에서 서버 식별 정보 (VM 번호, IP 등) 제공 확인
- [ ] 상품 API 응답에 `server_info` 필드 포함 확인
- [ ] Server Status Icons 동작 확인 (App-1, App-2 아이콘 표시)
- [ ] VM 이미지에서 자동 부팅 스크립트 실행 확인
- [ ] Load Balancer에서 Health Check 응답 확인

---

## 🎯 오디션 파일 업로드 API 시스템

### 개요
Creative Energy App Server는 오디션 지원자들을 위한 완전한 파일 업로드 시스템을 제공합니다. 이 시스템은 한글 파일명 자동 인코딩 지원과 파일 메타데이터 관리 기능을 포함합니다.

### API 엔드포인트

#### 1. 파일 업로드
**POST** `/api/audition/upload`

오디션 파일을 업로드하며 한글 파일명 자동 인코딩을 지원합니다.

**요청:**
- Content-Type: `multipart/form-data`
- Body: `file` 필드에 단일 파일

**지원 파일 형식:**
- PDF 문서 (`.pdf`)
- Word 문서 (`.doc`, `.docx`)
- 오디오 파일 (`.mp3`)
- 비디오 파일 (`.mp4`)
- 이미지 파일 (`.jpg`, `.jpeg`, `.png`)

**파일 크기 제한:** 50MB

**성공 응답:**
```json
{
  "success": true,
  "message": "파일이 성공적으로 업로드되었습니다.",
  "file": {
    "id": 123,
    "originalName": "김예림_여_201005.pdf",
    "filename": "1234567890_123.pdf",
    "size": 1024000,
    "type": "application/pdf",
    "uploadDate": "2025-08-15T12:00:00.000Z",
    "downloadUrl": "/files/audition/1234567890_123.pdf"
  }
}
```

#### 2. 파일 목록 조회
**GET** `/api/audition/files`

업로드된 모든 오디션 파일 목록을 조회합니다.

**성공 응답:**
```json
{
  "success": true,
  "files": [
    {
      "id": 123,
      "name": "김예림_여_201005.pdf",
      "filename": "1234567890_123.pdf",
      "size": 1024000,
      "type": "application/pdf",
      "uploadDate": "2025-08-15T12:00:00.000Z",
      "downloadUrl": "/files/audition/1234567890_123.pdf"
    }
  ],
  "count": 1
}
```

#### 3. 파일 다운로드
**GET** `/api/audition/download/:id`

ID로 특정 파일을 다운로드합니다.

**파라미터:**
- `id`: 데이터베이스의 파일 ID

**응답:** 적절한 헤더와 함께 파일 다운로드

#### 4. 파일 삭제
**DELETE** `/api/audition/delete/:id`

ID로 특정 파일을 삭제합니다.

**파라미터:**
- `id`: 데이터베이스의 파일 ID

**성공 응답:**
```json
{
  "success": true,
  "message": "파일이 삭제되었습니다: 김예림_여_201005.pdf"
}
```

#### 5. 파일 정보 조회
**GET** `/api/audition/info/:id`

특정 파일의 상세 정보를 조회합니다.

**성공 응답:**
```json
{
  "success": true,
  "file": {
    "id": 123,
    "name": "김예림_여_201005.pdf",
    "filename": "1234567890_123.pdf",
    "size": 1024000,
    "type": "application/pdf",
    "uploadDate": "2025-08-15T12:00:00.000Z",
    "downloadUrl": "/files/audition/1234567890_123.pdf"
  }
}
```

### 파일 저장소 구조

#### 저장 위치
- **App-Server 경로:** `/home/rocky/ceweb/files/audition/`
- **Web-Server 접근:** Nginx를 통해 `/files/audition/` URL 경로로 제공
- **데이터베이스:** `audition_files` 테이블에 파일 메타데이터 저장

#### 한글 파일명 지원
시스템에서 한글 파일명 인코딩을 자동으로 처리합니다:
- 입력 파일명이 `latin1`에서 `utf8` 인코딩으로 자동 변환
- 원본 한글 파일명이 데이터베이스에 보존됨
- 물리적 파일은 타임스탬프 기반 이름으로 저장되어 충돌 방지

#### 파일 명명 규칙
- **원본명:** `김예림_여_201005.pdf` (데이터베이스에 저장)
- **물리적 파일명:** `1234567890_123.pdf` (타임스탬프_랜덤숫자.확장자)

### 데이터베이스 스키마

```sql
CREATE TABLE audition_files (
    id SERIAL PRIMARY KEY,
    original_name VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    upload_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audition_files_upload_date 
ON audition_files(upload_date);
```

### 설정 요구사항

#### 환경 변수
`/home/rocky/ceweb/app-server/.env`에 설정:
- 파일 업로드 경로는 `routes/audition.js`에서 하드코딩됨
- 추가 설정 불필요

#### 보안 기능
- MIME 타입 기반 파일 형식 검증
- 파일 크기 제한 (50MB)
- Nginx에서 실행 파일 차단
- 적절한 권한으로 디렉토리 자동 생성

### 오류 처리

#### 일반적인 오류 응답
```json
{
  "success": false,
  "message": "오류 설명"
}
```

**주요 오류 코드:**
- 400: 파일 업로드 없음 또는 지원하지 않는 파일 형식
- 404: 파일을 찾을 수 없음
- 500: 서버 오류 또는 파일 시스템 문제

### 설치 요구사항

오디션 파일 업로드 시스템은 다음 명령어 실행 시 자동으로 설정됩니다:
```bash
sudo bash install_app_server.sh
```

이 스크립트는:
1. `/home/rocky/ceweb/files/audition/` 디렉토리 생성
2. 적절한 권한 설정 (755)
3. 첫 실행 시 데이터베이스 테이블 초기화
4. UTF-8 인코딩을 위한 Express 미들웨어 설정

### 문제 해결

#### 한글 파일명 깨짐 현상
한글 파일명이 깨져서 나타나는 경우:
1. 서버 로그에서 인코딩 오류 확인
2. Express 미들웨어에 `charset: 'utf-8'` 포함 확인
3. 간단한 ASCII 파일명으로 먼저 테스트

#### 파일 업로드 실패
1. 디스크 용량 확인: `df -h`
2. 디렉토리 권한 확인: `ls -la /home/rocky/ceweb/files/`
3. 앱 서버 로그 확인: `pm2 logs creative-energy-api`

#### API 연결 문제
1. 앱 서버 실행 상태 확인: `pm2 status`
2. 직접 연결 테스트: `curl http://app.cesvc.net:3000/health`
3. 웹 서버의 Nginx 프록시 설정 확인

### 테스트 예제

#### 파일 업로드 테스트
```bash
# 로컬에서 파일 업로드 테스트
curl -X POST http://localhost:3000/api/audition/upload \
  -F "file=@김예림_여_201005.pdf"

# 성공 시 응답으로 file 객체와 downloadUrl 확인
```

#### 파일 목록 조회 테스트
```bash
# 업로드된 파일 목록 확인
curl -X GET http://localhost:3000/api/audition/files

# 파일 개수와 한글 파일명이 올바르게 표시되는지 확인
```

---

## 📞 다음 단계

1. **Web Server** 연동 확인 (API 프록시 테스트)
2. **오디션 파일 업로드** 시스템 테스트
3. **프론트엔드** 배포 및 연동
4. **모니터링** 및 **백업** 시스템 구축
5. **HTTPS** 및 보안 강화

**중요사항:**
- Web Server가 이 App Server로 API 요청을 정상적으로 프록시할 수 있어야 합니다
- 오디션 파일 업로드 기능은 한글 파일명을 완전히 지원합니다
- 파일은 App-Server에 저장되지만 Web-Server를 통해 접근됩니다