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

# Creative Energy Samsung Cloud Platform Architecture Installer
# 사용법: sudo bash install_architecture.sh
# 설명: 사용자가 선택한 아키텍처에 따라 적절한 설치 스크립트 조합을 실행

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

# 루트 권한 확인
if [[ $EUID -ne 0 ]]; then
   error "이 스크립트는 root 권한으로 실행되어야 합니다."
   exit 1
fi

# 헤더 출력
echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}     Creative Energy Samsung Cloud Platform Installer${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# 서버 역할 자동 감지 함수
detect_server_role() {
    local hostname_role=""
    local ip_role=""
    local detected_role=""
    
    # 1. 호스트명 기반 역할 감지
    HOSTNAME=$(hostname)
    case $HOSTNAME in
        *web*vm*) hostname_role="web" ;;
        *app*vm*) hostname_role="app" ;;
        *db*vm*) hostname_role="db" ;;
        *bastion*) hostname_role="bastion" ;;
        *) hostname_role="unknown" ;;
    esac
    
    # 3. IP 주소 기반 역할 감지
    SERVER_IP=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}' 2>/dev/null || echo "unknown")
    case $SERVER_IP in
        10.1.1.*) ip_role="web" ;;
        10.1.2.*) ip_role="app" ;;
        10.1.3.*) ip_role="db" ;;
        *) ip_role="unknown" ;;
    esac
    
    # 호스트명과 IP가 일치하는지 확인
    if [[ "$hostname_role" != "unknown" && "$ip_role" != "unknown" && "$hostname_role" == "$ip_role" ]]; then
        detected_role="$hostname_role"
        info "🔍 서버 역할 자동 감지:"
        info "- 호스트명: $HOSTNAME → $hostname_role 서버"
        info "- IP 주소: $SERVER_IP → $ip_role 서버"
        info "- 감지 결과: ✅ $detected_role 서버로 판단됨"
        echo ""
        
        # 확인 질문
        case $detected_role in
            "web")
                echo -n -e "${YELLOW}설치하고자 하는 서비스가 웹서버 서비스가 맞습니까? (y/n): ${NC}"
                ;;
            "app")
                echo -n -e "${YELLOW}설치하고자 하는 서비스가 앱서버 서비스가 맞습니까? (y/n): ${NC}"
                ;;
            "db")
                echo -n -e "${YELLOW}설치하고자 하는 서비스가 데이터베이스 서비스가 맞습니까? (y/n): ${NC}"
                ;;
        esac
        
        read -r ROLE_CONFIRM
        echo ""
        
        if [[ $ROLE_CONFIRM =~ ^[Yy]$ ]]; then
            echo "$detected_role"
            return 0
        else
            warn "자동 감지된 역할이 맞지 않습니다. 수동 선택으로 진행합니다."
            echo ""
        fi
    else
        info "🔍 서버 역할 자동 감지:"
        info "- 호스트명: $HOSTNAME → $hostname_role"
        info "- IP 주소: $SERVER_IP → $ip_role"
        info "- 감지 결과: ❓ 역할을 명확히 판단할 수 없음"
        echo ""
    fi
    
    # 2. 수동 선택 메뉴
    info "서버 역할을 수동으로 선택해주세요:"
    echo "1) Web Server (웹서버 - Nginx)"
    echo "2) App Server (앱서버 - Node.js + PM2)"
    echo "3) DB Server (데이터베이스 - PostgreSQL)"
    echo "4) All-in-One (단일 서버 - 모든 서비스)"
    echo ""
    echo -n -e "${YELLOW}서버 역할을 선택하세요 (1-4): ${NC}"
    read -r ROLE_CHOICE
    echo ""
    
    case $ROLE_CHOICE in
        1) echo "web" ;;
        2) echo "app" ;;
        3) echo "db" ;;
        4) echo "all" ;;
        *) 
            error "잘못된 선택입니다. All-in-One으로 진행합니다."
            echo "all"
            ;;
    esac
}

# 서버 역할 감지 실행
SERVER_ROLE=$(detect_server_role)

# 통합 메뉴 선택
echo -e "${CYAN}=== Creative Energy Samsung Cloud Platform 통합 메뉴 ===${NC}"
echo ""
echo -e "${BLUE}🏗️ 아키텍처 설치:${NC}"
echo "1) 정적 웹사이트 (Standalone)"
echo "   - 파일 규칙: _nodb"
echo "   - 기능: static_local_path_job (상대경로, SIMULATION 모드)"
echo "   - 구성: Web Server만 설치"
echo ""

echo "2) 로드 밸런싱 (Standalone)" 
echo "   - 파일 규칙: _lb"
echo "   - 기능: static_url_path_job (절대URL, SIMULATION 모드)"
echo "   - 구성: Web Server만 설치"
echo ""

echo "3) 3Tier 동적 (3tier-ha)"
echo "   - 파일 규칙: \"\" (기본)"
echo "   - 기능: dynamic_file_job (실제 DB 연결, 로컬 파일 저장)"
echo "   - 구성: Web Server + App Server + DB Server"
echo ""

echo "4) 3Tier Object Storage (3tier-ha-as)"
echo "   - 파일 규칙: _obj"
echo "   - 기능: dynamic_object_job (실제 DB 연결, Object Storage)"
echo "   - 구성: Web Server + App Server(S3) + DB Server(DBaaS)"
echo ""

echo -e "${BLUE}🔧 개별 구성요소 관리:${NC}"
echo "5) Web Server 설치 (install_web_server.sh)"
echo "6) App Server 설치 (install_app_server.sh)"
echo "7) App Server S3 설치 (install_app_server_s3.sh)"
echo "8) PostgreSQL VM 설치 (install_postgresql_vm.sh)"
echo "9) PostgreSQL DBaaS 설정 (setup_postgresql_dbaas.sh)"
echo ""

echo -e "${BLUE}🧹 제거/정리 도구:${NC}"
echo "10) Web Server 제거 (uninstall_web_server.sh)"
echo "11) App Server 제거 (uninstall_app_server.sh)"
echo "12) PostgreSQL VM 제거 (uninstall_postgresql_vm.sh)"
echo ""

echo -e "${BLUE}🚀 VM 이미지 부트스트랩:${NC}"
echo "13) Web VM Bootstrap 실행 (bootstrap_web_vm.sh)"
echo "14) App VM Bootstrap 실행 (bootstrap_app_vm.sh)"
echo ""

echo -e "${BLUE}🔍 테스트 및 진단:${NC}"
echo "15) 데이터베이스 설치 테스트 (test_database_installation.sh)"
echo "16) 대체 웹서버 설치 - CEWeb (ceweb_install_web_server.sh)"
echo "17) 대체 웹서버 설치 - BBWeb (bbweb_install_web_server.sh)"
echo ""

# 사용자 선택 입력
echo -n -e "${YELLOW}실행할 작업을 선택하세요 (1-17): ${NC}"
read -r MENU_CHOICE

case $MENU_CHOICE in
    1)
        ARCHITECTURE="standalone-static"
        FILE_RULE="_nodb"
        FUNCTION="static_local_path_job"
        ARCH_TYPE="standalone"
        ;;
    2)
        ARCHITECTURE="standalone-lb" 
        FILE_RULE="_lb"
        FUNCTION="static_url_path_job"
        ARCH_TYPE="standalone"
        ;;
    3)
        ARCHITECTURE="3tier-dynamic"
        FILE_RULE=""
        FUNCTION="dynamic_file_job"
        ARCH_TYPE="3tier-ha"
        ;;
    4)
        ARCHITECTURE="3tier-object"
        FILE_RULE="_obj"
        FUNCTION="dynamic_object_job" 
        ARCH_TYPE="3tier-ha-as"
        ;;
    5)
        log "Web Server 설치를 실행합니다..."
        bash web-server/install_web_server.sh
        exit 0
        ;;
    6)
        log "App Server 설치를 실행합니다..."
        bash app-server/install_app_server.sh
        exit 0
        ;;
    7)
        log "App Server S3 설치를 실행합니다..."
        bash app-server/install_app_server_s3.sh
        exit 0
        ;;
    8)
        log "PostgreSQL VM 설치를 실행합니다..."
        bash db-server/vm_db/install_postgresql_vm.sh
        exit 0
        ;;
    9)
        log "PostgreSQL DBaaS 설정을 실행합니다..."
        bash db-server/dbaas_db/setup_postgresql_dbaas.sh
        exit 0
        ;;
    10)
        log "Web Server 제거를 실행합니다..."
        bash web-server/uninstall_web_server.sh
        exit 0
        ;;
    11)
        log "App Server 제거를 실행합니다..."
        bash app-server/uninstall_app_server.sh
        exit 0
        ;;
    12)
        log "PostgreSQL VM 제거를 실행합니다..."
        bash db-server/vm_db/uninstall_postgresql_vm.sh
        exit 0
        ;;
    13)
        log "Web VM Bootstrap을 실행합니다..."
        bash web-server/bootstrap_web_vm.sh
        exit 0
        ;;
    14)
        log "App VM Bootstrap을 실행합니다..."
        bash app-server/bootstrap_app_vm.sh
        exit 0
        ;;
    15)
        log "데이터베이스 설치 테스트를 실행합니다..."
        bash db-server/test_database_installation.sh
        exit 0
        ;;
    16)
        log "CEWeb 웹서버 설치를 실행합니다..."
        bash web-server/ceweb_install_web_server.sh
        exit 0
        ;;
    17)
        log "BBWeb 웹서버 설치를 실행합니다..."
        bash web-server/bbweb_install_web_server.sh
        exit 0
        ;;
    *)
        error "잘못된 선택입니다. 1-17 중에서 선택해주세요."
        exit 1
        ;;
esac

# 아키텍처 설치인 경우만 확인 절차 진행
if [[ $MENU_CHOICE -ge 1 && $MENU_CHOICE -le 4 ]]; then
    log "선택된 아키텍처: $ARCHITECTURE"
    log "파일 규칙: $FILE_RULE"
    log "기능: $FUNCTION"
    log "서버 구성: $ARCH_TYPE"
    echo ""

    # 확인 메시지
    echo -n -e "${YELLOW}계속 진행하시겠습니까? (y/N): ${NC}"
    read -r CONFIRM

    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        log "설치가 취소되었습니다."
        exit 0
    fi

    log "Samsung Cloud Platform $ARCHITECTURE 아키텍처 설치를 시작합니다..."
    echo ""
fi

# 현재 디렉토리 확인
CURRENT_DIR=$(pwd)
if [[ ! -f "install_architecture.sh" ]]; then
    error "ceweb 디렉토리에서 실행해주세요"
    exit 1
fi

# 아키텍처 설치인 경우만 설치 로직 실행
if [[ $MENU_CHOICE -ge 1 && $MENU_CHOICE -le 4 ]]; then
    # 아키텍처별 설치 스크립트 실행
case $ARCH_TYPE in
    "standalone")
        log "=== Standalone 아키텍처 설치 시작 ==="
        log "필요 구성요소: Web Server만"
        echo ""
        
        # Web Server 설치
        log "1/1: Web Server 설치 중..."
        if [ -f "web-server/install_web_server.sh" ]; then
            bash web-server/install_web_server.sh
            log "✅ Web Server 설치 완료"
        else
            error "web-server/install_web_server.sh 파일을 찾을 수 없습니다"
            exit 1
        fi
        
        # 아키텍처에 맞는 index.html 설정
        log "아키텍처별 index.html 설정 중..."
        if [ "$FILE_RULE" != "" ]; then
            WEBAPP_DIR="/home/rocky/ceweb"
            if [ -f "${WEBAPP_DIR}/index${FILE_RULE}.html" ]; then
                cp "${WEBAPP_DIR}/index${FILE_RULE}.html" "${WEBAPP_DIR}/index.html"
                log "✅ index${FILE_RULE}.html → index.html 교체 완료"
            else
                warn "index${FILE_RULE}.html 파일을 찾을 수 없습니다"
            fi
        fi
        ;;
        
    "3tier-ha")
        log "=== 3Tier-HA 아키텍처 설치 시작 ==="
        log "감지된 서버 역할: $SERVER_ROLE"
        echo ""
        
        case $SERVER_ROLE in
            "web")
                log "🌐 웹서버 전용 설치 시작"
                log "구성요소: Nginx Web Server"
                echo ""
                
                log "1/1: Web Server 설치 중..."
                if [ -f "web-server/install_web_server.sh" ]; then
                    bash web-server/install_web_server.sh
                    log "✅ Web Server 설치 완료"
                else
                    error "web-server/install_web_server.sh 파일을 찾을 수 없습니다"
                    exit 1
                fi
                ;;
                
            "app")
                log "⚙️ 앱서버 전용 설치 시작"
                log "구성요소: Node.js + PM2 App Server"
                echo ""
                
                log "1/1: App Server 설치 중..."
                if [ -f "app-server/install_app_server.sh" ]; then
                    bash app-server/install_app_server.sh
                    log "✅ App Server 설치 완료"
                else
                    error "app-server/install_app_server.sh 파일을 찾을 수 없습니다"
                    exit 1
                fi
                ;;
                
            "db")
                log "🗄️ 데이터베이스 서버 전용 설치 시작"
                log "구성요소: PostgreSQL DB Server"
                echo ""
                
                log "1/1: DB Server 설치 중..."
                if [ -f "db-server/vm_db/install_postgresql_vm.sh" ]; then
                    bash db-server/vm_db/install_postgresql_vm.sh
                    log "✅ DB Server 설치 완료"
                else
                    error "db-server/vm_db/install_postgresql_vm.sh 파일을 찾을 수 없습니다"
                    exit 1
                fi
                ;;
                
            "all")
                log "🏗️ All-in-One 서버 설치 시작"
                log "구성요소: Web Server + App Server + DB Server"
                echo ""
                
                # Web Server 설치
                log "1/3: Web Server 설치 중..."
                if [ -f "web-server/install_web_server.sh" ]; then
                    bash web-server/install_web_server.sh
                    log "✅ Web Server 설치 완료"
                else
                    error "web-server/install_web_server.sh 파일을 찾을 수 없습니다"
                    exit 1
                fi
                
                # App Server 설치  
                log "2/3: App Server 설치 중..."
                if [ -f "app-server/install_app_server.sh" ]; then
                    bash app-server/install_app_server.sh
                    log "✅ App Server 설치 완료"
                else
                    error "app-server/install_app_server.sh 파일을 찾을 수 없습니다"
                    exit 1
                fi
                
                # DB Server 설치
                log "3/3: DB Server (PostgreSQL VM) 설치 중..."
                if [ -f "db-server/vm_db/install_postgresql_vm.sh" ]; then
                    bash db-server/vm_db/install_postgresql_vm.sh
                    log "✅ DB Server 설치 완료"
                else
                    error "db-server/vm_db/install_postgresql_vm.sh 파일을 찾을 수 없습니다"
                    exit 1
                fi
                ;;
                
            *)
                error "알 수 없는 서버 역할: $SERVER_ROLE"
                exit 1
                ;;
        esac
        ;;
        
    "3tier-ha-as")
        log "=== 3Tier-HA-AS (Object Storage) 아키텍처 설치 시작 ==="
        log "감지된 서버 역할: $SERVER_ROLE"
        echo ""
        
        # Object Storage 설정 확인 (앱서버에만 해당)
        if [[ "$SERVER_ROLE" == "app" || "$SERVER_ROLE" == "all" ]]; then
            BUCKET_CONFIG="/home/rocky/ceweb/bucket_id.json"
            if [ -f "$BUCKET_CONFIG" ]; then
                BUCKET_STRING=$(jq -r '.object_storage.bucket_string' "$BUCKET_CONFIG" 2>/dev/null || echo "thisneedstobereplaced1234")
                if [ "$BUCKET_STRING" = "thisneedstobereplaced1234" ]; then
                    warn "bucket_id.json의 bucket_string을 실제 값으로 수정해주세요"
                    warn "파일 위치: $BUCKET_CONFIG"
                    warn "현재 값: $BUCKET_STRING"
                    echo ""
                fi
            fi
        fi
        
        case $SERVER_ROLE in
            "web")
                log "🌐 웹서버 전용 설치 시작 (Object Storage 지원)"
                log "구성요소: Nginx Web Server"
                echo ""
                
                log "1/1: Web Server 설치 중..."
                if [ -f "web-server/install_web_server.sh" ]; then
                    bash web-server/install_web_server.sh
                    log "✅ Web Server 설치 완료"
                else
                    error "web-server/install_web_server.sh 파일을 찾을 수 없습니다"
                    exit 1
                fi
                ;;
                
            "app")
                log "⚙️ 앱서버 전용 설치 시작 (Object Storage)"
                log "구성요소: Node.js + PM2 + S3 App Server"
                echo ""
                
                log "1/1: App Server (Object Storage) 설치 중..."
                if [ -f "app-server/install_app_server_s3.sh" ]; then
                    bash app-server/install_app_server_s3.sh
                    log "✅ App Server (S3) 설치 완료"
                else
                    error "app-server/install_app_server_s3.sh 파일을 찾을 수 없습니다"
                    exit 1
                fi
                ;;
                
            "db")
                log "🗄️ 데이터베이스 서버 전용 설치 시작 (DBaaS)"
                log "구성요소: PostgreSQL DBaaS 설정"
                echo ""
                
                log "1/1: DB Server (DBaaS) 설정 중..."
                if [ -f "db-server/dbaas_db/setup_postgresql_dbaas.sh" ]; then
                    bash db-server/dbaas_db/setup_postgresql_dbaas.sh
                    log "✅ DB Server (DBaaS) 설정 완료"
                else
                    error "db-server/dbaas_db/setup_postgresql_dbaas.sh 파일을 찾을 수 없습니다"
                    exit 1
                fi
                ;;
                
            "all")
                log "🏗️ All-in-One 서버 설치 시작 (Object Storage)"
                log "구성요소: Web Server + App Server(S3) + DB Server(DBaaS)"
                echo ""
                
                # Web Server 설치
                log "1/3: Web Server 설치 중..."
                if [ -f "web-server/install_web_server.sh" ]; then
                    bash web-server/install_web_server.sh
                    log "✅ Web Server 설치 완료"
                else
                    error "web-server/install_web_server.sh 파일을 찾을 수 없습니다"
                    exit 1
                fi
                
                # App Server (S3) 설치
                log "2/3: App Server (Object Storage) 설치 중..."
                if [ -f "app-server/install_app_server_s3.sh" ]; then
                    bash app-server/install_app_server_s3.sh
                    log "✅ App Server (S3) 설치 완료"
                else
                    error "app-server/install_app_server_s3.sh 파일을 찾을 수 없습니다"
                    exit 1
                fi
                
                # DB Server (DBaaS) 설정
                log "3/3: DB Server (DBaaS) 설정 중..."
                if [ -f "db-server/dbaas_db/setup_postgresql_dbaas.sh" ]; then
                    bash db-server/dbaas_db/setup_postgresql_dbaas.sh
                    log "✅ DB Server (DBaaS) 설정 완료"
                else
                    error "db-server/dbaas_db/setup_postgresql_dbaas.sh 파일을 찾을 수 없습니다"
                    exit 1
                fi
                ;;
                
            *)
                error "알 수 없는 서버 역할: $SERVER_ROLE"
                exit 1
                ;;
        esac
        
        # 아키텍처에 맞는 index.html 설정 (웹서버 또는 All-in-One에만 적용)
        if [[ "$SERVER_ROLE" == "web" || "$SERVER_ROLE" == "all" ]]; then
            log "Object Storage 아키텍처용 index.html 설정 중..."
            WEBAPP_DIR="/home/rocky/ceweb"
            if [ -f "${WEBAPP_DIR}/index_obj.html" ]; then
                cp "${WEBAPP_DIR}/index_obj.html" "${WEBAPP_DIR}/index.html"
                log "✅ index_obj.html → index.html 교체 완료"
            else
                warn "index_obj.html 파일을 찾을 수 없습니다"
            fi
        fi
        ;;
esac

    # 설치 완료 메시지
    echo ""
    log "================================================================"
    log "🎉 Creative Energy $ARCHITECTURE 아키텍처 설치 완료!"
    log "================================================================"
    echo ""

    case $ARCH_TYPE in
    "standalone")
        info "🌐 Standalone 아키텍처 정보:"
        info "- 서비스 유형: $FUNCTION"
        info "- 파일 규칙: $FILE_RULE"
        info "- 웹 서버: Nginx (포트 80)"
        info "- 정적 파일 위치: /home/rocky/ceweb"
        info "- 동적 기능: SIMULATION 모드"
        echo ""
        info "🔧 관리 명령어:"
        info "systemctl status nginx"
        info "systemctl restart nginx"
        ;;
        
    "3tier-ha")
        info "🏗️ 3Tier-HA 아키텍처 정보:"
        info "- 서비스 유형: $FUNCTION"  
        info "- 웹 서버: Nginx (포트 80)"
        info "- 앱 서버: Node.js + PM2 (포트 3000)"
        info "- DB 서버: PostgreSQL (포트 2866)"
        info "- 실시간 데이터베이스 연결"
        info "- 파일 저장: 로컬/NFS 디렉토리"
        echo ""
        info "🔧 관리 명령어:"
        info "systemctl status nginx postgresql pm2-rocky"
        info "sudo -u rocky pm2 status"
        ;;
        
    "3tier-ha-as")
        info "☁️ 3Tier-HA-AS (Object Storage) 아키텍처 정보:"
        info "- 서비스 유형: $FUNCTION"
        info "- 웹 서버: Nginx (포트 80)" 
        info "- 앱 서버: Node.js + PM2 + S3 (포트 3000)"
        info "- DB 서버: PostgreSQL DBaaS"
        info "- Object Storage: Samsung Cloud Platform S3 호환"
        info "- 미디어 파일: Object Storage 제공"
        echo ""
        info "🔧 관리 명령어:"
        info "systemctl status nginx pm2-rocky"
        info "sudo -u rocky pm2 status"
        info "curl http://localhost:3000/api/s3/status"
        echo ""
        info "⚠️ 추가 설정 필요:"
        info "1. bucket_id.json에서 실제 bucket_string 설정"
        info "2. credentials.json에서 Samsung Cloud Platform 인증키 설정"
    esac

    echo ""
    info "📁 웹 애플리케이션 위치: /home/rocky/ceweb"
    info "📋 로그 파일들: /var/log/"
    info "👤 애플리케이션 사용자: rocky"
    echo ""

    log "설치 완료! 웹 브라우저에서 http://your-server-ip 로 접속하세요."
    log "================================================================"
    
else
    # 개별 도구 실행 완료 메시지
    echo ""
    log "================================================================"
    log "🎉 선택된 도구 실행이 완료되었습니다!"
    log "================================================================"
    echo ""
    info "ℹ️  추가 작업이 필요한 경우 다시 sudo bash install_architecture.sh를 실행하세요."
    echo ""
fi