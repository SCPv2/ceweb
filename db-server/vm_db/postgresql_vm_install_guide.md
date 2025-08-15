# PostgreSQL 16.8 설치 가이드 - Rocky Linux 9.4

## 개요
이 가이드는 Rocky Linux 9.4에서 PostgreSQL 16.8을 설치하고 Creative Energy 데이터베이스를 구성하는 전체 과정을 다룹니다.

## 전제조건
- Rocky Linux 9.4가 설치된 서버 (db.cesvc.net)
- root 권한 또는 sudo 권한
- 인터넷 연결

## 1단계: 시스템 업데이트

```bash
# 시스템 패키지 업데이트
sudo dnf update -y

# 필요한 기본 도구 설치
sudo dnf install -y wget curl vim git
```

## 2단계: PostgreSQL 16 공식 저장소 추가

```bash
# PostgreSQL 공식 RPM 저장소 설치
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# 저장소 목록 확인
sudo dnf repolist | grep pgdg
```

## 3단계: PostgreSQL 16.8 설치

```bash
# PostgreSQL 16 서버 및 클라이언트 설치
sudo dnf install -y postgresql16-server postgresql16 postgresql16-contrib

# 설치 확인
/usr/pgsql-16/bin/postgres --version
```

## 4단계: PostgreSQL 데이터베이스 초기화

```bash
# 데이터베이스 클러스터 초기화
sudo /usr/pgsql-16/bin/postgresql-16-setup initdb

# PostgreSQL 서비스 시작 및 부팅 시 자동 시작 설정
sudo systemctl start postgresql-16
sudo systemctl enable postgresql-16

# 서비스 상태 확인
sudo systemctl status postgresql-16
```

## 5단계: PostgreSQL 설정

### 5.1 PostgreSQL 사용자 설정
```bash
# postgres 사용자로 전환
sudo -u postgres psql

# postgres 사용자 비밀번호 설정 (psql 내에서 실행)
ALTER USER postgres PASSWORD 'your_secure_password';

# 새 데이터베이스 사용자 생성
CREATE USER ceapp WITH PASSWORD 'ceapp_secure_password';
ALTER USER ceapp CREATEDB;

# 종료
\q
```

### 5.2 PostgreSQL 설정 파일 수정
```bash
# postgresql.conf 설정
sudo vim /var/lib/pgsql/16/data/postgresql.conf

# 다음 설정을 찾아 수정:
listen_addresses = '*'          # 모든 IP에서 접근 허용
port = 5432                     # 기본 포트 사용
max_connections = 100           # 최대 연결 수
shared_buffers = 128MB          # 공유 버퍼 크기
```

### 5.3 클라이언트 인증 설정
```bash
# pg_hba.conf 설정
sudo vim /var/lib/pgsql/16/data/pg_hba.conf

# 다음 라인들을 추가 (기존 설정 아래에):
# TYPE  DATABASE        USER            ADDRESS                 METHOD
host    all             all             0.0.0.0/0               md5
host    all             all             ::/0                    md5
```

### 5.4 방화벽 설정
```bash
# PostgreSQL 포트 방화벽 허용
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --reload

# 방화벽 규칙 확인
sudo firewall-cmd --list-ports
```

### 5.5 PostgreSQL 재시작
```bash
sudo systemctl restart postgresql-16
sudo systemctl status postgresql-16
```

## 6단계: Creative Energy 데이터베이스 생성

```bash
# postgres 사용자로 데이터베이스 생성
sudo -u postgres createdb -O ceapp creative_energy

# 데이터베이스 생성 확인
sudo -u postgres psql -l
```

## 7단계: 데이터베이스 스키마 설치

```bash
# 스키마 파일을 서버에 업로드 (scp 또는 다른 방법 사용)
# 예시: scp db-server/vm_db/postgresql_vm_init_schema.sql root@db.cesvc.net:/tmp/

# 스키마 설치
sudo -u postgres psql -d creative_energy -f /tmp/postgresql_vm_init_schema.sql
```

## 8단계: 연결 테스트

```bash
# 로컬에서 연결 테스트
sudo -u postgres psql -d creative_energy -c "SELECT COUNT(*) FROM products;"

# 원격에서 연결 테스트 (다른 서버에서 실행)
psql -h db.cesvc.net -U ceapp -d creative_energy -c "SELECT COUNT(*) FROM products;"
```

## 보안 권장사항

1. **강력한 비밀번호 사용**: 모든 데이터베이스 사용자에게 강력한 비밀번호 설정
2. **SSL 연결 활성화**: 프로덕션 환경에서는 SSL 연결 사용 권장
3. **IP 화이트리스트**: pg_hba.conf에서 특정 IP만 접근 허용
4. **정기적인 백업**: pg_dump를 사용한 정기 백업 설정

## 백업 설정

```bash
# 백업 스크립트 생성
sudo vim /usr/local/bin/backup_creative_energy.sh

#!/bin/bash
BACKUP_DIR="/var/backups/postgresql"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

# 데이터베이스 백업
sudo -u postgres pg_dump creative_energy > $BACKUP_DIR/creative_energy_$DATE.sql

# 7일 이상된 백업 파일 삭제
find $BACKUP_DIR -name "creative_energy_*.sql" -mtime +7 -delete

# 실행 권한 부여
sudo chmod +x /usr/local/bin/backup_creative_energy.sh

# crontab에 매일 백업 설정
sudo -u postgres crontab -e
# 다음 라인 추가: 0 2 * * * /usr/local/bin/backup_creative_energy.sh
```

## 문제 해결

### PostgreSQL이 시작되지 않는 경우
```bash
# 로그 확인
sudo journalctl -u postgresql-16 -f

# 데이터 디렉토리 권한 확인
sudo ls -la /var/lib/pgsql/16/data/
```

### 연결이 거부되는 경우
```bash
# 포트가 열려있는지 확인
sudo netstat -tlnp | grep 5432

# PostgreSQL 프로세스 확인
sudo ps aux | grep postgres
```

### 권한 오류가 발생하는 경우
```bash
# 사용자 권한 확인
sudo -u postgres psql -c "\du"
```

## 완료 확인

설치가 완료되면 다음 명령으로 확인할 수 있습니다:

```bash
# 서비스 상태 확인
sudo systemctl status postgresql-16

# 데이터베이스 연결 및 테이블 확인
sudo -u postgres psql -d creative_energy -c "\dt"

# 샘플 데이터 확인
sudo -u postgres psql -d creative_energy -c "SELECT title, category FROM products LIMIT 3;"
```

설치가 성공적으로 완료되었습니다!