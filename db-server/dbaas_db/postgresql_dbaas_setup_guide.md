# Creative Energy DBaaS 데이터베이스 설정 가이드

## 📋 개요
이 가이드는 **app.cesvc.net** (app-server)에서 **db.cesvc.net:2866** (DBaaS PostgreSQL 서버)에 Creative Energy 데이터베이스 스키마를 설치하고 연결하는 완전한 과정을 다룹니다.

## 🎯 설정 대상
- **Database Server**: db.cesvc.net:2866 (PostgreSQL 16.8)
- **Database Name**: cedb
- **Database User**: ceadmin
- **Database Password**: ceadmin123!
- **App Server**: app.cesvc.net:3000 (Node.js/Express)

---

## 🛠️ 1단계: 사전 준비사항

### 📋 시스템 요구사항
- **OS**: Rocky Linux 9.4 (app-server)
- **PostgreSQL Client**: psql (app-server에 설치 필요)
- **Network**: db.cesvc.net:2866 포트 접근 가능
- **Credentials**: ceadmin / ceadmin123!

### 💿 PostgreSQL 클라이언트 설치 (app-server에서)
```bash
# CentOS/Rocky Linux/RHEL
sudo dnf install -y postgresql

# Ubuntu/Debian (참고용)
sudo apt-get install -y postgresql-client

# 설치 확인
psql --version
```

### 🌐 네트워크 연결 확인
```bash
# 1. 서버 연결 확인
ping -c 3 db.cesvc.net

# 2. 포트 연결 확인
telnet db.cesvc.net 2866
# 또는
timeout 5 bash -c "cat < /dev/null > /dev/tcp/db.cesvc.net/2866"

# 3. 수동 데이터베이스 연결 테스트
psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c "SELECT 'Connection test successful!' as status;"
```

---

## 🚀 2단계: 자동 설치 (권장)

### 📁 파일 준비
설치에 필요한 파일들:
```
db-server/dbaas_db/
├── setup_postgresql_dbaas.sh              # 🔧 통합 설치 스크립트 (NEW!)
├── postgresql_dbaas_init_schema.sql      # 📊 완전한 데이터베이스 스키마
├── .env.dbaas_db                       # ⚙️ 환경 설정 템플릿
└── postgresql_dbaas_setup_guide.md          # 📚 이 가이드
```

### 🎯 통합 설치 스크립트 실행
```bash
# 1. dbaas_db 디렉토리로 이동
cd db-server/dbaas_db/

# 2. 실행 권한 부여
chmod +x setup_postgresql_dbaas.sh

# 3. 통합 설치 실행
./setup_postgresql_dbaas.sh
```

### 🔧 설치 스크립트 수행 내용
통합 스크립트는 다음을 자동으로 수행합니다:

1. **📋 사전 요구사항 확인**
   - PostgreSQL 클라이언트 설치 확인
   - 스키마 파일 존재 확인

2. **🌐 데이터베이스 연결 테스트**
   - db.cesvc.net:2866 연결 확인
   - ceadmin 계정 인증 확인

3. **🔍 기존 스키마 확인**
   - 기존 테이블 존재 여부 확인
   - 업데이트/재설치 확인

4. **📊 데이터베이스 스키마 설치**
   - 테이블 생성 (products, inventory, orders)
   - 함수 생성 (재고 관리 함수들)
   - 뷰 생성 (product_inventory_view)
   - 초기 데이터 삽입 (BigBoys & Cloudy 상품)

5. **✅ 설치 검증**
   - 테이블 생성 확인
   - 초기 데이터 확인
   - 함수 및 뷰 확인

6. **🧪 애플리케이션 레벨 테스트**
   - API 쿼리 테스트
   - 재고 관리 함수 테스트

7. **⚙️ App Server 환경 파일 생성**
   - .env.app_server 파일 자동 생성
   - 모든 필요한 환경 변수 포함

8. **🏁 최종 연결 테스트**
   - 모든 주요 API 쿼리 실행 테스트

---

## 🔧 3단계: 수동 설치 (고급 사용자용)

### 📊 스키마만 직접 설치
```bash
# 스키마 파일 직접 실행
PGPASSWORD="ceadmin123!" psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -f postgresql_dbaas_init_schema.sql
```

### 🔍 설치 확인
```bash
# 테이블 확인
PGPASSWORD="ceadmin123!" psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c "\dt"

# 데이터 확인
PGPASSWORD="ceadmin123!" psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c "
SELECT 
    '상품' as 구분, COUNT(*) as 개수 FROM products
UNION ALL 
SELECT 
    '재고' as 구분, COUNT(*) as 개수 FROM inventory;
"
```

---

## ⚙️ 4단계: App Server 설정

### 📁 환경 설정 파일
자동 생성된 `.env.app_server` 파일을 app server로 복사:

```bash
# app-server로 파일 복사
scp .env.app_server user@app.cesvc.net:/path/to/app-server/.env

# 또는 수동으로 생성
cat > /path/to/app-server/.env << 'EOF'
# External Database Configuration
DB_HOST=db.cesvc.net
DB_PORT=2866
DB_NAME=cedb
DB_USER=ceadmin
DB_PASSWORD=ceadmin123!
DB_SSL=false

# Connection Pool Settings
DB_POOL_MIN=2
DB_POOL_MAX=10
DB_POOL_IDLE_TIMEOUT=30000
DB_POOL_CONNECTION_TIMEOUT=5000

# Server Configuration
PORT=3000
NODE_ENV=production
BIND_HOST=0.0.0.0

# CORS Configuration
ALLOWED_ORIGINS=http://www.cesvc.net,https://www.cesvc.net

# Security
JWT_SECRET=your_jwt_secret_here
EOF
```

### 🚀 App Server 시작
```bash
# app-server 디렉토리에서
cd /path/to/app-server

# 의존성 설치
npm install

# 서버 시작
npm start
# 또는 프로덕션 환경에서
pm2 start ecosystem.config.js
```

---

## 🧪 5단계: 설치 검증 및 테스트

### 🔍 데이터베이스 연결 테스트
```bash
# 1. 직접 데이터베이스 연결
psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb

# 2. 상품 데이터 확인
SELECT id, title, category, price FROM products ORDER BY id;

# 3. 재고 정보 확인  
SELECT id, title, stock_quantity, stock_display FROM product_inventory_view ORDER BY id;

# 4. 함수 테스트
SELECT reset_daily_inventory();
```

### 🌐 App Server API 테스트
```bash
# 1. 서버 헬스 체크
curl http://app.cesvc.net:3000/health

# 2. 상품 목록 API
curl http://app.cesvc.net:3000/api/orders/products

# 3. 특정 상품 재고 확인
curl http://app.cesvc.net:3000/api/orders/products/1/inventory
```

### 🖥️ 웹 인터페이스 테스트
```bash
# 브라우저에서 접속 테스트
# 1. 메인 페이지
http://www.cesvc.net/

# 2. 쇼핑몰 페이지
http://www.cesvc.net/pages/shop.html

# 3. 주문 페이지 (상품 클릭 후)
http://www.cesvc.net/pages/order.html
```

---

## 📊 6단계: 데이터베이스 구조 이해

### 🗃️ 테이블 구조
```sql
-- 상품 테이블
CREATE TABLE products (
    id integer PRIMARY KEY,
    title varchar(255) NOT NULL,           -- 상품명
    subtitle varchar(255),                 -- 부제목
    price varchar(20) NOT NULL,            -- 가격 표시 (한국어)
    price_numeric integer NOT NULL,        -- 가격 숫자
    image varchar(255),                    -- 이미지 경로
    category varchar(50),                  -- 카테고리 (bigboys/cloudy)
    type varchar(50),                      -- 타입 (album/goods/limited)
    badge varchar(20),                     -- 배지 (NEW/LIMITED/SET)
    created_at timestamp DEFAULT NOW(),
    updated_at timestamp DEFAULT NOW()
);

-- 재고 테이블
CREATE TABLE inventory (
    id integer PRIMARY KEY,
    product_id integer REFERENCES products(id),
    stock_quantity integer DEFAULT 100,    -- 재고 수량
    reserved_quantity integer DEFAULT 0,   -- 예약 수량
    updated_at timestamp DEFAULT NOW()
);

-- 주문 테이블
CREATE TABLE orders (
    id integer PRIMARY KEY,
    customer_name varchar(100) NOT NULL,   -- 주문자명
    product_id integer REFERENCES products(id),
    quantity integer NOT NULL,             -- 주문 수량
    unit_price integer NOT NULL,           -- 단가
    total_price integer NOT NULL,          -- 총액
    order_date timestamp DEFAULT NOW(),
    status varchar(20) DEFAULT 'completed'
);
```

### 🔧 주요 함수들
```sql
-- 주문 처리 및 재고 차감
SELECT process_order_inventory(product_id, quantity);

-- 일일 재고 리셋 (매일 자정 실행)
SELECT reset_daily_inventory();

-- 상품-재고 통합 뷰
SELECT * FROM product_inventory_view;
```

### 📦 초기 데이터
- **BigBoys 상품**: 앨범 2개, 굿즈 2개
- **Cloudy 상품**: 앨범 2개, 굿즈 2개
- **초기 재고**: 모든 상품 100개씩

---

## 🔧 7단계: 유지보수 및 모니터링

### 📊 일일 관리 명령어
```bash
# 1. 재고 현황 확인
PGPASSWORD="ceadmin123!" psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c "
SELECT 
    category as 카테고리,
    COUNT(*) as 상품수,
    SUM(stock_quantity) as 총재고
FROM product_inventory_view 
GROUP BY category;
"

# 2. 금일 주문 현황
PGPASSWORD="ceadmin123!" psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c "
SELECT 
    COUNT(*) as 주문수,
    SUM(total_price) as 총매출
FROM orders 
WHERE DATE(order_date) = CURRENT_DATE;
"

# 3. 재고 부족 상품 확인
PGPASSWORD="ceadmin123!" psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c "
SELECT title, stock_quantity 
FROM product_inventory_view 
WHERE stock_quantity < 10 
ORDER BY stock_quantity;
"
```

### 🔄 정기 작업
```bash
# 1. 매일 자정 재고 리셋 (app-server에서 cron 실행)
0 0 * * * PGPASSWORD="ceadmin123!" psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c "SELECT reset_daily_inventory();"

# 2. 주간 데이터베이스 백업
pg_dump -h db.cesvc.net -p 2866 -U celadmin cedb > cedb_backup_$(date +%Y%m%d).sql

# 3. 로그 정리 (app-server에서)
find /path/to/app-server/logs -name "*.log" -mtime +7 -delete
```

---

## 🚨 8단계: 문제 해결

### 🔍 일반적인 문제들

#### 1. **연결 거부 오류**
```bash
# 문제: psql: could not connect to server
# 해결책:
sudo systemctl status postgresql-16    # DB 서버 상태 확인
sudo firewall-cmd --list-ports         # 방화벽 확인
telnet db.cesvc.net 2866               # 포트 연결 확인
```

#### 2. **인증 실패**
```bash
# 문제: psql: FATAL: password authentication failed
# 해결책:
# 1. 비밀번호 확인: ceadmin123!
# 2. 사용자명 확인: ceadmin
# 3. pg_hba.conf 설정 확인 (DB 서버에서)
```

#### 3. **스키마 설치 실패**
```bash
# 문제: CREATE TABLE 권한 오류
# 해결책:
PGPASSWORD="ceadmin123!" psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c "\du"  # 사용자 권한 확인
```

#### 4. **App Server 연결 실패**
```bash
# 문제: 애플리케이션에서 DB 연결 안됨
# 해결책:
# 1. .env 파일 확인
cat /path/to/app-server/.env

# 2. Node.js 애플리케이션 로그 확인
pm2 logs creative-energy-api

# 3. 수동 연결 테스트
node -e "
const { Pool } = require('pg');
const pool = new Pool({
  host: 'db.cesvc.net',
  port: 2866,
  database: 'cedb',
  user: 'ceadmin',
  password: 'ceadmin123!',
});
pool.query('SELECT 1').then(console.log).catch(console.error).finally(() => pool.end());
"
```

#### 5. **재고 확인 불가**
```bash
# 문제: order.html에서 "재고 확인 불가"
# 해결책:
# 1. API 엔드포인트 확인
curl http://app.cesvc.net:3000/api/orders/products/1/inventory

# 2. 데이터베이스 직접 확인
PGPASSWORD="ceadmin123!" psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c "
SELECT * FROM product_inventory_view WHERE id = 1;
"
```

### 🔧 디버깅 명령어
```bash
# 1. 전체 시스템 상태 확인
echo "=== Database Status ==="
PGPASSWORD="ceadmin123!" psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c "SELECT 'DB Connected' as status, current_timestamp;"

echo "=== App Server Status ==="
curl -s http://app.cesvc.net:3000/health || echo "App server not responding"

echo "=== Network Status ==="
ping -c 1 db.cesvc.net && echo "DB server reachable" || echo "DB server unreachable"

# 2. 상세 연결 정보 확인
PGPASSWORD="ceadmin123!" psql -h db.cesvc.net -p 2866 -U ceadmin -d cedb -c "
SELECT 
    current_database() as database,
    current_user as user,
    inet_server_addr() as server_ip,
    inet_server_port() as server_port,
    version() as postgresql_version;
"
```

---

## 🎯 완료 확인 체크리스트

설치 완료 후 다음 항목들을 확인하세요:

### ✅ 데이터베이스 레벨
- [ ] PostgreSQL 연결 성공
- [ ] 3개 테이블 생성 (products, inventory, orders)
- [ ] 초기 데이터 8개 상품 삽입
- [ ] 재고 데이터 8개 레코드 생성
- [ ] 4개 함수 생성 (재고 관리 함수들)
- [ ] 1개 뷰 생성 (product_inventory_view)

### ✅ 애플리케이션 레벨
- [ ] App server 정상 시작 (포트 3000)
- [ ] API 엔드포인트 응답 확인
- [ ] 상품 목록 API 정상 동작
- [ ] 재고 조회 API 정상 동작
- [ ] 주문 생성 API 정상 동작

### ✅ 웹 인터페이스 레벨
- [ ] shop.html 상품 목록 표시
- [ ] 카테고리별 필터링 동작
- [ ] order.html 재고 정보 표시
- [ ] 주문 프로세스 정상 동작

---

## 📚 관련 문서

- **App Server 설정**: `../app-server/APP_SERVER_SETUP_GUIDE.md`
- **Web Server 설정**: `../web-server/WEB_SERVER_SETUP_GUIDE.md`
- **전체 시스템 아키텍처**: `../../README.md`
- **포트 및 네트워크**: `../../deployment/etc/PORTS_AND_ARCHITECTURE.md`

---

## 🎉 설치 완료!

모든 단계가 성공적으로 완료되었다면, Creative Energy DBaaS 데이터베이스 설정이 완료되었습니다!

**🔧 최종 테스트**:
```bash
curl http://app.cesvc.net:3000/api/orders/products | jq '.[0:3]'
```

**🌐 웹 접속**:
- 메인 사이트: http://www.cesvc.net/
- 쇼핑몰: http://www.cesvc.net/pages/shop.html

---

*Creative Energy Team - External Database Setup Guide*  
*🎵 BigBoys & ☁️ Cloudy Official Database*