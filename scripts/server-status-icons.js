/**
 * Creative Energy Server Status Icons Component
 * Load Balancer 환경에서 Web/App 서버 상태를 아이콘으로 표시
 */

class ServerStatusIcons {
    constructor(containerId) {
        this.container = document.getElementById(containerId);
        this.servers = {
            web: [
                { id: 'web1', name: 'Web-1', status: 'unknown', ip: 'unknown' },
                { id: 'web2', name: 'Web-2', status: 'unknown', ip: 'unknown' }
            ],
            app: [
                { id: 'app1', name: 'App-1', status: 'unknown', ip: 'unknown' },
                { id: 'app2', name: 'App-2', status: 'unknown', ip: 'unknown' }
            ]
        };
        this.updateInterval = null;
        
        this.init();
    }

    init() {
        this.createServerIconsHTML();
        this.loadServerStatus();
        this.startAutoUpdate();
    }

    createServerIconsHTML() {
        if (!this.container) return;

        this.container.innerHTML = `
            <div class="server-status-container">
                <!-- Web Servers -->
                <div class="server-group">
                    <div class="server-group-label">WEB</div>
                    <div class="server-icons-row">
                        ${this.servers.web.map(server => this.createServerIcon(server, 'web')).join('')}
                    </div>
                </div>
                
                <!-- App Servers -->
                <div class="server-group">
                    <div class="server-group-label">APP</div>
                    <div class="server-icons-row">
                        ${this.servers.app.map(server => this.createServerIcon(server, 'app')).join('')}
                    </div>
                </div>
                
                <!-- 상세 정보 툴팁 -->
                <div class="server-tooltip" id="serverTooltip">
                    <div class="tooltip-header">
                        <span class="tooltip-title" id="tooltipTitle">Server Info</span>
                    </div>
                    <div class="tooltip-content">
                        <div class="tooltip-row">
                            <span class="tooltip-label">상태:</span>
                            <span class="tooltip-value" id="tooltipStatus">Unknown</span>
                        </div>
                        <div class="tooltip-row">
                            <span class="tooltip-label">IP:</span>
                            <span class="tooltip-value" id="tooltipIp">Unknown</span>
                        </div>
                        <div class="tooltip-row">
                            <span class="tooltip-label">응답시간:</span>
                            <span class="tooltip-value" id="tooltipResponseTime">-</span>
                        </div>
                    </div>
                </div>
            </div>
        `;

        this.addServerIconsCSS();
        this.setupEventListeners();
    }

    createServerIcon(server, type) {
        const iconSymbol = type === 'web' ? '🌐' : '⚙️';
        return `
            <div class="server-icon ${server.status}" 
                 id="${server.id}" 
                 data-server-id="${server.id}"
                 data-server-name="${server.name}"
                 data-server-type="${type}">
                <div class="server-icon-symbol">${iconSymbol}</div>
                <div class="server-icon-name">${server.name}</div>
                <div class="server-status-dot"></div>
            </div>
        `;
    }

    addServerIconsCSS() {
        if (document.getElementById('server-icons-css')) return;

        const style = document.createElement('style');
        style.id = 'server-icons-css';
        style.textContent = `
            .server-status-container {
                display: flex;
                align-items: center;
                gap: 15px;
                position: relative;
            }

            .server-group {
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 4px;
            }

            .server-group-label {
                font-size: 0.7rem;
                color: rgba(255, 255, 255, 0.8);
                font-weight: bold;
                text-align: center;
                margin-bottom: 2px;
            }

            .server-icons-row {
                display: flex;
                gap: 6px;
            }

            .server-icon {
                position: relative;
                display: flex;
                flex-direction: column;
                align-items: center;
                padding: 8px;
                background: rgba(255, 255, 255, 0.1);
                border: 1px solid rgba(255, 255, 255, 0.2);
                border-radius: 8px;
                cursor: pointer;
                transition: all 0.3s ease;
                min-width: 50px;
                backdrop-filter: blur(5px);
            }

            .server-icon:hover {
                background: rgba(255, 255, 255, 0.2);
                transform: translateY(-2px);
                box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
            }

            .server-icon-symbol {
                font-size: 1.2rem;
                margin-bottom: 2px;
                filter: grayscale(100%);
                transition: filter 0.3s ease;
            }

            .server-icon.online .server-icon-symbol {
                filter: grayscale(0%);
            }

            .server-icon-name {
                font-size: 0.6rem;
                color: rgba(255, 255, 255, 0.9);
                font-weight: 500;
                text-align: center;
                line-height: 1;
            }

            .server-status-dot {
                position: absolute;
                top: 4px;
                right: 4px;
                width: 8px;
                height: 8px;
                border-radius: 50%;
                background: #6c757d;
                transition: all 0.3s ease;
                border: 1px solid rgba(255, 255, 255, 0.3);
            }

            .server-icon.online .server-status-dot {
                background: #28a745;
                box-shadow: 0 0 6px rgba(40, 167, 69, 0.6);
                animation: pulse-green 2s infinite;
            }

            .server-icon.offline .server-status-dot {
                background: #dc3545;
                box-shadow: 0 0 6px rgba(220, 53, 69, 0.6);
            }

            .server-icon.warning .server-status-dot {
                background: #ffc107;
                box-shadow: 0 0 6px rgba(255, 193, 7, 0.6);
            }

            .server-icon.unknown .server-status-dot {
                background: #6c757d;
            }

            @keyframes pulse-green {
                0%, 100% { opacity: 1; }
                50% { opacity: 0.6; }
            }

            /* 툴팁 스타일 */
            .server-tooltip {
                position: absolute;
                top: 100%;
                left: 50%;
                transform: translateX(-50%);
                background: white;
                border: 1px solid #ddd;
                border-radius: 8px;
                box-shadow: 0 4px 12px rgba(0,0,0,0.2);
                padding: 0;
                z-index: 1000;
                display: none;
                min-width: 200px;
                margin-top: 8px;
            }

            .server-tooltip.show {
                display: block;
                animation: tooltipFadeIn 0.2s ease;
            }

            @keyframes tooltipFadeIn {
                from {
                    opacity: 0;
                    transform: translateX(-50%) translateY(-5px);
                }
                to {
                    opacity: 1;
                    transform: translateX(-50%) translateY(0);
                }
            }

            .tooltip-header {
                background: #f8f9fa;
                padding: 10px 12px;
                border-bottom: 1px solid #e9ecef;
                border-radius: 8px 8px 0 0;
            }

            .tooltip-title {
                font-weight: bold;
                color: #495057;
                font-size: 0.9rem;
            }

            .tooltip-content {
                padding: 10px 12px;
            }

            .tooltip-row {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 6px;
                font-size: 0.8rem;
            }

            .tooltip-row:last-child {
                margin-bottom: 0;
            }

            .tooltip-label {
                color: #6c757d;
                font-weight: 500;
            }

            .tooltip-value {
                color: #495057;
                font-weight: bold;
            }

            .tooltip-value.online {
                color: #28a745;
            }

            .tooltip-value.offline {
                color: #dc3545;
            }

            .tooltip-value.warning {
                color: #ffc107;
            }

            /* 모바일 반응형 */
            @media (max-width: 768px) {
                .server-status-container {
                    gap: 10px;
                }
                
                .server-group-label {
                    font-size: 0.65rem;
                }
                
                .server-icon {
                    min-width: 40px;
                    padding: 6px;
                }
                
                .server-icon-symbol {
                    font-size: 1rem;
                }
                
                .server-icon-name {
                    font-size: 0.55rem;
                }
                
                .server-status-dot {
                    width: 6px;
                    height: 6px;
                    top: 2px;
                    right: 2px;
                }

                .server-tooltip {
                    left: 0;
                    transform: none;
                    margin-top: 5px;
                }
            }

            /* 작은 화면에서 툴팁 위치 조정 */
            @media (max-width: 480px) {
                .server-icons-row {
                    gap: 4px;
                }
                
                .server-icon {
                    min-width: 35px;
                    padding: 4px;
                }
            }
        `;
        document.head.appendChild(style);
    }

    setupEventListeners() {
        const tooltip = document.getElementById('serverTooltip');
        let tooltipTimeout;

        // 서버 아이콘 이벤트
        this.container.addEventListener('mouseenter', (e) => {
            const serverIcon = e.target.closest('.server-icon');
            if (serverIcon) {
                clearTimeout(tooltipTimeout);
                this.showTooltip(serverIcon);
            }
        }, true);

        this.container.addEventListener('mouseleave', (e) => {
            if (!this.container.contains(e.relatedTarget)) {
                tooltipTimeout = setTimeout(() => {
                    this.hideTooltip();
                }, 200);
            }
        }, true);

        // 툴팁 호버 유지
        if (tooltip) {
            tooltip.addEventListener('mouseenter', () => {
                clearTimeout(tooltipTimeout);
            });

            tooltip.addEventListener('mouseleave', () => {
                this.hideTooltip();
            });
        }

        // 외부 클릭시 툴팁 닫기
        document.addEventListener('click', (e) => {
            if (!this.container.contains(e.target)) {
                this.hideTooltip();
            }
        });
    }

    showTooltip(serverIcon) {
        const tooltip = document.getElementById('serverTooltip');
        if (!tooltip || !serverIcon) return;

        const serverId = serverIcon.dataset.serverId;
        const serverName = serverIcon.dataset.serverName;
        const serverType = serverIcon.dataset.serverType;
        
        // 서버 정보 찾기
        const serverInfo = this.findServerInfo(serverId, serverType);
        
        // 툴팁 내용 업데이트
        document.getElementById('tooltipTitle').textContent = serverName;
        
        const statusElement = document.getElementById('tooltipStatus');
        statusElement.textContent = serverInfo.status.toUpperCase();
        statusElement.className = `tooltip-value ${serverInfo.status}`;
        
        document.getElementById('tooltipIp').textContent = serverInfo.ip || 'Unknown';
        document.getElementById('tooltipResponseTime').textContent = serverInfo.responseTime || '-';

        tooltip.classList.add('show');
    }

    hideTooltip() {
        const tooltip = document.getElementById('serverTooltip');
        if (tooltip) {
            tooltip.classList.remove('show');
        }
    }

    findServerInfo(serverId, serverType) {
        const serverList = this.servers[serverType] || [];
        return serverList.find(s => s.id === serverId) || {
            status: 'unknown',
            ip: 'unknown',
            responseTime: '-'
        };
    }

    async loadServerStatus() {
        try {
            // 실제 서버 상태 확인 (Load Balancer Health Check 시뮬레이션)
            const webStatus = await this.checkServerStatus('web');
            const appStatus = await this.checkServerStatus('app');
            
            // Web 서버 상태 업데이트 (현재는 시뮬레이션)
            this.servers.web[0].status = webStatus.primary ? 'online' : 'offline';
            this.servers.web[0].ip = webStatus.primaryIp || 'unknown';
            this.servers.web[0].responseTime = webStatus.primaryResponseTime || '-';
            
            this.servers.web[1].status = webStatus.secondary ? 'online' : 'offline';
            this.servers.web[1].ip = webStatus.secondaryIp || 'unknown';
            this.servers.web[1].responseTime = webStatus.secondaryResponseTime || '-';
            
            // App 서버 상태 업데이트
            this.servers.app[0].status = appStatus.primary ? 'online' : 'offline';
            this.servers.app[0].ip = appStatus.primaryIp || 'unknown';
            this.servers.app[0].responseTime = appStatus.primaryResponseTime || '-';
            
            this.servers.app[1].status = appStatus.secondary ? 'online' : 'offline';
            this.servers.app[1].ip = appStatus.secondaryIp || 'unknown';
            this.servers.app[1].responseTime = appStatus.secondaryResponseTime || '-';
            
            this.updateDisplay();
            
        } catch (error) {
            console.error('서버 상태 로드 실패:', error);
        }
    }

    async checkServerStatus(serverType) {
        try {
            if (serverType === 'web') {
                // Web 서버 상태 체크 (현재 접속 중인 서버는 항상 online)
                const currentWebResponse = await this.pingServer('/vm-info.json');
                
                return {
                    primary: currentWebResponse.success,
                    primaryIp: currentWebResponse.ip || window.location.hostname,
                    primaryResponseTime: currentWebResponse.responseTime + 'ms',
                    secondary: Math.random() > 0.3, // 시뮬레이션: 70% 확률로 온라인
                    secondaryIp: '10.0.0.' + (Math.floor(Math.random() * 200) + 50),
                    secondaryResponseTime: Math.floor(Math.random() * 100 + 50) + 'ms'
                };
            } else {
                // App 서버 상태 체크
                const currentAppResponse = await this.pingServer('/api/health');
                const secondaryAppResponse = await this.pingServer('/api/health'); // 실제로는 다른 App 서버 체크
                
                return {
                    primary: currentAppResponse.success,
                    primaryIp: currentAppResponse.hostname || 'unknown',
                    primaryResponseTime: currentAppResponse.responseTime + 'ms',
                    secondary: Math.random() > 0.2, // 시뮬레이션: 80% 확률로 온라인
                    secondaryIp: '10.0.1.' + (Math.floor(Math.random() * 200) + 50),
                    secondaryResponseTime: Math.floor(Math.random() * 150 + 100) + 'ms'
                };
            }
        } catch (error) {
            return {
                primary: false,
                secondary: false,
                primaryIp: 'unknown',
                secondaryIp: 'unknown',
                primaryResponseTime: 'timeout',
                secondaryResponseTime: 'timeout'
            };
        }
    }

    async pingServer(endpoint) {
        const startTime = Date.now();
        try {
            const response = await fetch(endpoint, { 
                method: 'GET',
                cache: 'no-cache',
                signal: AbortSignal.timeout(5000)
            });
            
            const responseTime = Date.now() - startTime;
            const data = await response.json().catch(() => ({}));
            
            return {
                success: response.ok,
                responseTime,
                ip: data.ip_address || data.ip,
                hostname: data.hostname
            };
        } catch (error) {
            return {
                success: false,
                responseTime: Date.now() - startTime,
                error: error.message
            };
        }
    }

    updateDisplay() {
        // Web 서버 아이콘 업데이트
        this.servers.web.forEach(server => {
            const element = document.getElementById(server.id);
            if (element) {
                element.className = `server-icon ${server.status}`;
            }
        });

        // App 서버 아이콘 업데이트
        this.servers.app.forEach(server => {
            const element = document.getElementById(server.id);
            if (element) {
                element.className = `server-icon ${server.status}`;
            }
        });
    }

    startAutoUpdate() {
        // 15초마다 자동 업데이트
        this.updateInterval = setInterval(() => {
            this.loadServerStatus();
        }, 15000);
    }

    stopAutoUpdate() {
        if (this.updateInterval) {
            clearInterval(this.updateInterval);
            this.updateInterval = null;
        }
    }

    destroy() {
        this.stopAutoUpdate();
        if (this.container) {
            this.container.innerHTML = '';
        }
    }
}

// 전역 함수로 컴포넌트 초기화
function initServerStatusIcons(containerId) {
    return new ServerStatusIcons(containerId);
}