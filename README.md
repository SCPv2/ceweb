# Creative Energy - K-POP 아티스트 관리 플랫폼

## 📋 프로젝트 개요

**목적**: BigBoys와 Cloudy 두 K-POP 아티스트의 공식 웹사이트 및 굿즈 판매 시스템  
**구조**: 3-Tier 아키텍처 (Web-Server, App-Server, DB-Server)  
**기술스택**: HTML/CSS/JS, Node.js/Express, PostgreSQL  
**배포환경**: Rocky Linux 9.4  

---

## 📁 디렉토리 구조 및 파일 설명

```
ceweb/                                  # 프로젝트 루트 디렉토리
├── README.md                           # 📖 프로젝트 전체 가이드 문서
├── index.html                          # 🏠 메인 홈페이지 (Creative Energy 소개)
│
├── 🌐 web-server/                      # 웹서버 관련 파일들 (Nginx 설정 및 정적 파일)
│   ├── api-config.js                   # 🔧 클라이언트 API 설정 (환경별 엔드포인트 관리)
│   ├── WEB_SERVER_SETUP_GUIDE.md       # 📚 웹서버 설치 가이드
│   ├── install_web_server.sh           # 🚀 웹서버 자동 설치 스크립트
│   └── web_server_api_proxy_setup.md   # 🔄 API 프록시 설정 가이드
│
├── 🖥️ app-server/                      # 백엔드 애플리케이션 서버 (Node.js/Express)
│   ├── server.js                       # 🚀 Express 서버 메인 파일
│   ├── package.json                    # 📦 Node.js 의존성 및 스크립트 정의
│   ├── APP_SERVER_SETUP_GUIDE.md       # 📚 앱서버 설치 가이드  
│   ├── install_app_server.sh           # 🚀 앱서버 자동 설치 스크립트
│   ├── config/                         # ⚙️ 서버 설정 파일들
│   │   └── database.js                 # 🗄️ PostgreSQL 연결 설정 (풀링, 타임아웃 등)
│   └── routes/                         # 🛣️ API 라우트 정의
│       └── orders.js                   # 🛒 주문/상품/재고 관련 API 엔드포인트
│
├── 🗄️ db-server/                       # 데이터베이스 서버 관련 파일들
│   ├── complete_database_v2_ultra_compatible.sql  # 🗃️ 전체 DB 스키마 백업
│   ├── dbaas_db/                       # 🔹 DBaaS PostgreSQL 서버 설정
│   │   ├── postgresql_dbaas_init_schema.sql # 🏗️ DBaaS 데이터베이스 스키마
│   │   ├── setup_postgresql_dbaas.sh   # 🚀 DBaaS DB 자동 설치 스크립트
│   │   ├── postgresql_dbaas_setup_guide.md # 📚 DBaaS 설치 가이드
│   │   │
│   │   └── .env.dbaas_db               # ⚙️ DBaaS 환경설정 템플릿
│   ├── test_database_installation.sh   # ✅ DB 설치 검증 스크립트
│
│   └── vm_db/                          # 🔸 VM DB 서버 연동 설정
│       ├── postgresql_vm_init_schema.sql # 🔧 VM DB 스키마 SQL 명령어
│       ├── install_postgresql_vm.sh    # 🌐 VM PostgreSQL 설치 스크립트
│       ├── postgresql_vm_install_guide.md # 📚 VM PostgreSQL 설치 가이드
│       └── uninstall_postgresql_vm.sh  # 🗑️ VM PostgreSQL 제거 스크립트
│
├── 📄 pages/                           # 웹페이지들
│   ├── shop.html                       # 🛍️ 온라인 굿즈 쇼핑몰 (상품 목록 및 카테고리)
│   ├── order.html                      # 💳 주문/결제 페이지 (상품 주문 및 재고 확인)
│   ├── admin.html                      # 👑 관리자 패널 (상품/주문/재고 관리)
│   ├── audition.html                   # 🎤 오디션 신청 페이지 (파일 업로드)
│   ├── notice.html                     # 📢 공지사항 게시판
│   └── shop-db 적용전.html             # 📋 Shop 페이지 백업 (DB 적용 이전 버전)
│
├── 🎨 artist/                          # 아티스트별 페이지
│   ├── cloudy.html                     # ☁️ Cloudy 아티스트 소개 및 앨범 정보
│   └── bbweb/                          # 🎵 BigBoys 관련 파일들
│       └── index.html                  # 🎤 BigBoys 아티스트 페이지
│
├── 📸 media/                           # 미디어 파일들 (이미지, 비디오)
│   ├── logo.png, logo.svg, logo_*.png  # 🏷️ Creative Energy 로고 파일들
│   ├── bb_prod*.png                    # 🎵 BigBoys 상품 이미지들
│   ├── cloudy*.png                     # ☁️ Cloudy 관련 이미지들
│   ├── cloudy_prod*.png                # 🛍️ Cloudy 상품 이미지들
│   ├── bigboys1.png                    # 🎤 BigBoys 프로필 이미지
│   └── cloudy_vid1.mp4                 # 📹 Cloudy 프로모션 비디오
│
├── 📁 files/                           # 사용자 업로드 파일 저장소 (오디션 파일 등)
│
└── 🗂️ deployment/                      # 🚨 레거시 배포 폴더 (백업용 - 사용 중단 예정)
    ├── app/, db/, web/, etc/           # ⚠️ 기존 배포 스크립트들 (새 구조로 이전됨)
    └── README.md → 루트로 이동완료     # ✅ 이 파일을 루트 폴더로 이동
```

---

## 🏗️ 시스템 아키텍처

### 📊 3-Tier 아키텍처
```
[사용자] → [Web Server:80] → [App Server:3000] → [DB Server:2866]
           (Nginx)           (Node.js/Express)    (PostgreSQL)
```

### 🌐 도메인 구조
- **www.cesvc.net**: 메인 웹사이트 (Nginx)
- **app.cesvc.net**: API 서버 (Node.js)  
- **db.cesvc.net**: 데이터베이스 서버 (PostgreSQL)

### 🔌 주요 포트
- **80**: HTTP 웹서버
- **443**: HTTPS 웹서버  
- **3000**: Node.js API 서버
- **2866**: PostgreSQL 데이터베이스

---

## 🚀 배포 시나리오

### 1️⃣ 3-Tier 분산 환경 구축 (권장 - 운영환경)
```bash
# 🗄️ 1단계: DB 서버 설치
cd db-server/vm_db/
sudo bash install_postgresql_vm.sh

# 🖥️ 2단계: App 서버 설치  
cd app-server/
sudo bash install_app_server.sh

# 🌐 3단계: Web 서버 설치
cd web-server/
sudo bash install_web_server.sh
```

### 2️⃣ 외부 DB 서버 사용
```bash
# 🌐 DB 서버에 스키마 설치
cd db-server/dbaas_db/
bash setup_postgresql_dbaas.sh

# 🖥️ App 서버 설치 (외부 DB 연결)
cd app-server/
sudo bash install_app_server.sh
```

### 3️⃣ 개발 환경 로컬 설정
```bash
# 📦 Node.js 의존성 설치
cd app-server/
npm install

# 🚀 개발 서버 실행
npm run dev

# 🌐 웹 페이지 접속
# http://localhost:3000 (개발환경)
```

---

## 📋 주요 기능

### 🛍️ 쇼핑몰 기능
- **상품 목록**: BigBoys & Cloudy 굿즈 카테고리별 조회
- **실시간 재고**: 데이터베이스 연동 재고 확인 시스템
- **주문 처리**: 고객 정보 입력 및 주문 생성
- **관리자 패널**: 상품/재고/주문 관리 대시보드

### 🎤 아티스트 관리
- **아티스트 페이지**: BigBoys, Cloudy 개별 소개 페이지
- **앨범 정보**: 디스코그래피 및 상품 연동
- **오디션 시스템**: 파일 업로드 및 지원자 관리

### 🔧 시스템 관리
- **API 관리**: RESTful API 엔드포인트
- **파일 관리**: 미디어 및 업로드 파일 관리  
- **보안**: CORS 설정, 헬스체크, 에러 처리

---

## 🔧 개발 환경 설정

### 📋 사전 요구사항
- **OS**: Rocky Linux 9.4 (또는 CentOS/RHEL 호환)
- **Node.js**: v16+ 
- **PostgreSQL**: v16+
- **권한**: sudo/root 권한 필요

### 🛠️ 로컬 개발 설정
```bash
# 1. 저장소 클론
git clone <repository-url>
cd ceweb

# 2. API 설정 파일 확인
# web-server/api-config.js에서 개발환경 설정 확인

# 3. 데이터베이스 설정
# db-server/vm_db/postgresql_vm_init_schema.sql로 스키마 생성

# 4. 백엔드 서버 실행
cd app-server
npm install
npm start

# 5. 웹페이지 접속
# 브라우저에서 index.html 또는 pages/ 폴더의 페이지들 접속
```

---

## 🔍 트러블슈팅 가이드

### 📚 문서 참조
- **웹서버**: `web-server/WEB_SERVER_SETUP_GUIDE.md`
- **앱서버**: `app-server/APP_SERVER_SETUP_GUIDE.md`
- **VM DB**: `db-server/vm_db/postgresql_vm_install_guide.md`
- **DBaaS**: `db-server/dbaas_db/postgresql_dbaas_setup_guide.md`

### 🚨 주요 이슈 해결
1. **API 연결 오류**: `web-server/api-config.js`에서 엔드포인트 확인
2. **데이터베이스 연결 실패**: `app-server/config/database.js` 설정 점검
3. **재고 확인 불가**: DB 스키마 및 API 엔드포인트 확인
4. **파일 업로드 오류**: `files/` 디렉토리 권한 및 용량 확인

---

## 👥 기여 가이드

### 🔄 개발 워크플로우
1. 기능 개발 시 관련 디렉토리에서 작업
2. API 변경 시 `web-server/api-config.js` 업데이트
3. DB 스키마 변경 시 `db-server/` 폴더의 SQL 파일들 업데이트
4. 문서화: 각 변경사항을 해당 가이드 문서에 반영

### 📁 파일 배치 규칙
- **정적 파일**: `media/`, `pages/` 디렉토리
- **설정 파일**: 각 서버 폴더 내 config/ 또는 루트
- **문서화**: README.md 및 각 폴더별 가이드 문서
- **스크립트**: 설치/배포 스크립트는 해당 서버 폴더에 배치

---

*Creative Energy Team - K-POP Artist Management Platform*  
*🎵 BigBoys & ☁️ Cloudy Official Website*


[//]: # (
==============================================================================
Copyright (c) 2025 Stan Hong. All rights reserved.

This software and its source code are the exclusive property of Stan Hong.

Permission is granted only for 2025 SCPv2 Advance training and education.
Any reproduction, modification, distribution, or other use is strictly
prohibited without prior written permission from the copyright holder.

Unauthorized use will be subject to legal action under applicable law.

Contact: ars4mundus@gmail.com
==============================================================================
)
