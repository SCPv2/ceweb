#!/bin/bash
#
# 목적: PostgreSQL 16.8과 Creative Energy 데이터베이스를 완전히 제거하는 스크립트
# 작동방식: PostgreSQL 서비스 중지 → 패키지 제거 → 데이터 디렉토리 삭제 → 사용자/그룹 제거 → 백업 파일 삭제
# 사용대상: 시스템 관리자 (완전한 재설치가 필요할 때 사용)
# 사용법: sudo bash uninstall_postgresql_vm.sh
# 주의사항: 모든 데이터가 영구 삭제되므로 백업을 먼저 생성하세요
#

# PostgreSQL Complete Uninstallation Script
# Rocky Linux 9.4 PostgreSQL 16.8 완전 제거 스크립트
# 사용법: sudo bash uninstall_postgresql_vm.sh

set -e  # 오류 발생 시 스크립트 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
print_status() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
   print_error "이 스크립트는 root 권한으로 실행되어야 합니다."
   exit 1
fi

# 경고 메시지 출력
echo -e "${RED}=======================================${NC}"
echo -e "${RED} PostgreSQL 완전 제거 스크립트${NC}"
echo -e "${RED}=======================================${NC}"
echo ""
print_warning "이 스크립트는 다음 항목들을 완전히 삭제합니다:"
print_warning "- PostgreSQL 16 서비스 및 패키지"
print_warning "- 모든 데이터베이스 및 데이터"
print_warning "- PostgreSQL 설정 파일"
print_warning "- postgres 사용자 및 그룹"
print_warning "- 백업 파일 및 로그"
echo ""
print_error "⚠️  주의: 삭제된 데이터는 복구할 수 없습니다!"
echo ""

# 사용자 확인
read -p "정말로 PostgreSQL을 완전히 제거하시겠습니까? (yes/no): " confirm
if [[ $confirm != "yes" ]]; then
    print_info "설치 제거가 취소되었습니다."
    exit 0
fi

print_status "PostgreSQL 완전 제거를 시작합니다..."

# 1. PostgreSQL 서비스 중지 및 비활성화
print_status "PostgreSQL 서비스 중지 중..."
if systemctl is-active --quiet postgresql-16; then
    systemctl stop postgresql-16
    print_status "PostgreSQL 서비스가 중지되었습니다."
else
    print_warning "PostgreSQL 서비스가 실행 중이 아닙니다."
fi

if systemctl is-enabled --quiet postgresql-16; then
    systemctl disable postgresql-16
    print_status "PostgreSQL 서비스가 비활성화되었습니다."
fi

# 2. PostgreSQL 패키지 제거
print_status "PostgreSQL 패키지 제거 중..."
dnf remove -y postgresql16-server postgresql16-contrib postgresql16 postgresql16-libs 2>/dev/null || print_warning "일부 패키지가 이미 제거되었거나 설치되지 않았습니다."

# 3. PostgreSQL 저장소 제거
print_status "PostgreSQL 저장소 제거 중..."
dnf remove -y pgdg-redhat-repo 2>/dev/null || print_warning "PostgreSQL 저장소가 이미 제거되었습니다."

# 4. PostgreSQL 데이터 디렉토리 제거
print_status "PostgreSQL 데이터 디렉토리 제거 중..."
if [ -d "/var/lib/pgsql" ]; then
    rm -rf /var/lib/pgsql
    print_status "PostgreSQL 데이터 디렉토리가 제거되었습니다."
else
    print_warning "PostgreSQL 데이터 디렉토리가 존재하지 않습니다."
fi

# 5. PostgreSQL 로그 디렉토리 제거
print_status "PostgreSQL 로그 파일 제거 중..."
if [ -d "/var/log/postgresql" ]; then
    rm -rf /var/log/postgresql
    print_status "PostgreSQL 로그 디렉토리가 제거되었습니다."
fi

# 6. systemd 서비스 파일 제거
print_status "PostgreSQL systemd 서비스 파일 제거 중..."
if [ -f "/usr/lib/systemd/system/postgresql-16.service" ]; then
    rm -f /usr/lib/systemd/system/postgresql-16.service
    systemctl daemon-reload
    print_status "PostgreSQL systemd 서비스 파일이 제거되었습니다."
fi

# 7. PostgreSQL 실행 파일 및 라이브러리 제거
print_status "PostgreSQL 실행 파일 제거 중..."
if [ -d "/usr/pgsql-16" ]; then
    rm -rf /usr/pgsql-16
    print_status "PostgreSQL 실행 파일 디렉토리가 제거되었습니다."
fi

# 8. postgres 사용자 및 그룹 제거
print_status "postgres 사용자 및 그룹 제거 중..."
if id "postgres" &>/dev/null; then
    userdel -r postgres 2>/dev/null || userdel postgres 2>/dev/null
    print_status "postgres 사용자가 제거되었습니다."
else
    print_warning "postgres 사용자가 존재하지 않습니다."
fi

if getent group postgres &>/dev/null; then
    groupdel postgres 2>/dev/null || print_warning "postgres 그룹 제거 실패"
    print_status "postgres 그룹이 제거되었습니다."
fi

# 9. 백업 디렉토리 제거
print_status "PostgreSQL 백업 파일 제거 중..."
if [ -d "/var/backups/postgresql" ]; then
    rm -rf /var/backups/postgresql
    print_status "PostgreSQL 백업 디렉토리가 제거되었습니다."
fi

# 10. 백업 스크립트 제거
if [ -f "/usr/local/bin/backup_creative_energy.sh" ]; then
    rm -f /usr/local/bin/backup_creative_energy.sh
    print_status "백업 스크립트가 제거되었습니다."
fi

# 11. cron 작업 제거 (백업 관련)
print_status "PostgreSQL 관련 cron 작업 제거 중..."
crontab -l 2>/dev/null | grep -v "backup_creative_energy" | crontab - 2>/dev/null || print_warning "cron 작업 제거 실패 또는 없음"

# 12. 환경 변수 정리
print_status "PostgreSQL 관련 환경 변수 정리 중..."
if [ -f "/etc/profile.d/pgsql.sh" ]; then
    rm -f /etc/profile.d/pgsql.sh
    print_status "PostgreSQL 환경 변수 파일이 제거되었습니다."
fi

# 13. 남은 설정 파일 정리
print_status "남은 설정 파일 정리 중..."
find /etc -name "*postgresql*" -type f -delete 2>/dev/null || true
find /etc -name "*pgsql*" -type f -delete 2>/dev/null || true

# 14. 패키지 캐시 정리
print_status "패키지 캐시 정리 중..."
dnf clean all

# 15. 최종 확인
print_status "제거 작업 완료, 남은 파일 확인 중..."

# PostgreSQL 관련 프로세스 확인
if pgrep -f postgres >/dev/null; then
    print_warning "PostgreSQL 관련 프로세스가 아직 실행 중입니다:"
    pgrep -f postgres
else
    print_status "PostgreSQL 프로세스가 모두 종료되었습니다."
fi

# 포트 2866 사용 확인
if netstat -tlnp 2>/dev/null | grep ":2866" >/dev/null; then
    print_warning "포트 2866이 아직 사용 중입니다:"
    netstat -tlnp | grep ":2866"
else
    print_status "포트 2866이 해제되었습니다."
fi

# 남은 디렉토리 확인
remaining_dirs=""
for dir in "/var/lib/pgsql" "/usr/pgsql-16" "/var/log/postgresql" "/var/backups/postgresql"; do
    if [ -d "$dir" ]; then
        remaining_dirs="$remaining_dirs $dir"
    fi
done

if [ -n "$remaining_dirs" ]; then
    print_warning "다음 디렉토리가 아직 남아있습니다:$remaining_dirs"
    print_warning "수동으로 확인 후 제거하세요."
else
    print_status "모든 PostgreSQL 디렉토리가 제거되었습니다."
fi

print_status "================================================="
print_status "PostgreSQL 완전 제거가 완료되었습니다!"
print_status "================================================="
print_info ""
print_info "제거된 항목:"
print_info "- PostgreSQL 16 서비스 및 패키지"
print_info "- 모든 데이터베이스 및 사용자 데이터"
print_info "- PostgreSQL 설정 파일"
print_info "- postgres 사용자 및 그룹"
print_info "- 백업 파일 및 스크립트"
print_info "- 로그 파일"
print_info ""
print_info "시스템 재부팅을 권장합니다:"
print_info "sudo reboot"
print_info ""
print_status "완전한 재설치가 필요한 경우 다음 명령으로 설치하세요:"
print_status "sudo bash install_postgresql_vm.sh"