/*
==============================================================================
Copyright (c) 2025 Stan H. All rights reserved.

This software and its source code are the exclusive property of Stan H.

Use is strictly limited to 2025 SCPv2 Advance training and education only.
Any reproduction, modification, distribution, or other use beyond this scope is
strictly prohibited without prior written permission from the copyright holder.

Unauthorized use may lead to legal action under applicable law.

Contact: ars4mundus@gmail.com
==============================================================================
*/

/**
 * Template Variables Loader
 * master_config.json 기반 템플릿 변수 동적 로딩 모듈
 * {{PUBLIC_DOMAIN}}, {{OBJECT_STORAGE_MEDIA_BASE}} 등 템플릿 변수를 동적으로 처리
 */

class TemplateVariablesLoader {
    constructor() {
        this.config = null;
        this.isLoaded = false;
        this.fallbackConfig = {
            // 도메인 설정
            publicDomain: 'your_public_domain_name.net',
            privateDomain: 'your_private_domain_name.net',

            // 서버 설정
            webServerHost: 'www.your_private_domain_name.net',
            appServerHost: 'app.your_private_domain_name.net',
            dbServerHost: 'db.your_private_domain_name.net',

            // 포트 설정
            webPort: '80',
            appPort: '3000',
            dbPort: '2866',

            // Load Balancer 설정
            webLbServiceIp: '10.1.1.100',
            appLbServiceIp: '10.1.2.100',

            // IP 설정
            webPrimaryIp: '10.1.1.111',
            webSecondaryIp: '10.1.1.112',
            appPrimaryIp: '10.1.2.121',
            appSecondaryIp: '10.1.2.122',
            dbPrimaryIp: '10.1.3.131',
            bastionIp: '10.1.1.110',

            // 데이터베이스 설정
            databaseName: 'creative_energy_db',
            databaseUser: 'cedbadmin',

            // Object Storage 설정
            objectStorageUrl: './media/img/',
            bucketName: 'ceweb',
            region: 'kr-west1'
        };
    }

    /**
     * master_config.json 로드 및 파싱
     * @returns {Promise<Object>} 설정 객체
     */
    async loadConfig() {
        if (this.isLoaded && this.config) {
            return this.config;
        }

        try {
            const response = await fetch('./web-server/master_config.json');
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            const masterConfig = await response.json();

            // Object Storage URL 생성
            let objectStorageUrl = './media/img/';
            let objectStorageFilesUrl = './files/audition/';

            if (masterConfig.object_storage &&
                masterConfig.object_storage.bucket_string !== 'thisneedstobereplaced1234') {
                const bucketString = masterConfig.object_storage.bucket_string;
                const bucketName = masterConfig.object_storage.bucket_name;
                const publicEndpoint = masterConfig.object_storage.public_endpoint;
                objectStorageUrl = `${publicEndpoint}/${bucketString}:${bucketName}/media/img/`;
                objectStorageFilesUrl = `${publicEndpoint}/${bucketString}:${bucketName}/files/audition/`;
            }

            // 모든 설정값 매핑
            this.config = {
                // 도메인 설정
                publicDomain: masterConfig.infrastructure?.domain?.public_domain_name || this.fallbackConfig.publicDomain,
                privateDomain: masterConfig.infrastructure?.domain?.private_domain_name || this.fallbackConfig.privateDomain,

                // 서버 호스트 설정
                webServerHost: `www.${masterConfig.infrastructure?.domain?.private_domain_name || this.fallbackConfig.privateDomain}`,
                appServerHost: `app.${masterConfig.infrastructure?.domain?.private_domain_name || this.fallbackConfig.privateDomain}`,
                dbServerHost: `db.${masterConfig.infrastructure?.domain?.private_domain_name || this.fallbackConfig.privateDomain}`,

                // 포트 설정  
                webPort: masterConfig.application?.web_server?.nginx_port?.toString() || this.fallbackConfig.webPort,
                appPort: masterConfig.application?.app_server?.port?.toString() || this.fallbackConfig.appPort,
                dbPort: masterConfig.application?.database?.port?.toString() || this.fallbackConfig.dbPort,

                // Load Balancer 설정
                webLbServiceIp: masterConfig.infrastructure?.load_balancer?.web_lb_service_ip || this.fallbackConfig.webLbServiceIp,
                appLbServiceIp: masterConfig.infrastructure?.load_balancer?.app_lb_service_ip || this.fallbackConfig.appLbServiceIp,

                // IP 설정
                webPrimaryIp: masterConfig.infrastructure?.servers?.web_primary_ip || this.fallbackConfig.webPrimaryIp,
                webSecondaryIp: masterConfig.infrastructure?.servers?.web_secondary_ip || this.fallbackConfig.webSecondaryIp,
                appPrimaryIp: masterConfig.infrastructure?.servers?.app_primary_ip || this.fallbackConfig.appPrimaryIp,
                appSecondaryIp: masterConfig.infrastructure?.servers?.app_secondary_ip || this.fallbackConfig.appSecondaryIp,
                dbPrimaryIp: masterConfig.infrastructure?.servers?.db_primary_ip || this.fallbackConfig.dbPrimaryIp,
                bastionIp: masterConfig.infrastructure?.servers?.bastion_ip || this.fallbackConfig.bastionIp,

                // 데이터베이스 설정
                databaseName: masterConfig.application?.app_server?.database_name || this.fallbackConfig.databaseName,
                databaseUser: 'cedbadmin', // 보안상 하드코딩 유지

                // Object Storage 설정
                objectStorageUrl: objectStorageUrl,
                objectStorageFilesUrl: objectStorageFilesUrl,
                bucketName: masterConfig.object_storage?.bucket_name || this.fallbackConfig.bucketName,
                region: masterConfig.object_storage?.region || this.fallbackConfig.region,

                // 네트워크 설정
                vpcCidr: masterConfig.infrastructure?.network?.vpc_cidr || '10.1.0.0/16',
                webSubnetCidr: masterConfig.infrastructure?.network?.web_subnet_cidr || '10.1.1.0/24',
                appSubnetCidr: masterConfig.infrastructure?.network?.app_subnet_cidr || '10.1.2.0/24',
                dbSubnetCidr: masterConfig.infrastructure?.network?.db_subnet_cidr || '10.1.3.0/24'
            };

            this.isLoaded = true;
            console.log('✅ Template Variables Loader: Configuration loaded successfully', this.config);
            return this.config;

        } catch (error) {
            console.warn('⚠️ Template Variables Loader: Failed to load master_config.json, using fallback:', error.message);
            this.config = this.fallbackConfig;
            this.isLoaded = true;
            return this.config;
        }
    }

    /**
     * 템플릿 변수들을 동적으로 교체
     * @param {Object} options 교체 옵션
     */
    async replaceAllVariables(options = {}) {
        const config = await this.loadConfig();

        const defaultOptions = {
            replaceTemplateVariables: true,
            replaceObjectStorage: true,
            replaceServerIps: true,
            replaceDatabaseHosts: true,
            logChanges: false
        };

        const opts = { ...defaultOptions, ...options };

        // 1. 템플릿 변수 교체
        if (opts.replaceTemplateVariables) {
            // PUBLIC_DOMAIN 변수 교체
            this.replaceInElements('a[href*="{{PUBLIC_DOMAIN}}"]', 'href',
                /\{\{PUBLIC_DOMAIN\}\}/g,
                `http://www.${config.publicDomain}`, opts.logChanges);

            // PRIVATE_DOMAIN 변수 교체
            this.replaceInElements('a[href*="{{PRIVATE_DOMAIN}}"]', 'href',
                /\{\{PRIVATE_DOMAIN\}\}/g,
                `http://www.${config.privateDomain}`, opts.logChanges);

            // DOMAIN_NAME 변수 교체 (이메일 등)
            this.replaceTextContent(/\{\{DOMAIN_NAME\}\}/g, config.publicDomain, opts.logChanges);
        }

        // 2. Object Storage 템플릿 변수 교체
        if (opts.replaceObjectStorage) {
            // OBJECT_STORAGE_MEDIA_BASE 변수 교체
            this.replaceInElements('img[src*="{{OBJECT_STORAGE_MEDIA_BASE}}"]', 'src',
                /\{\{OBJECT_STORAGE_MEDIA_BASE\}\}/g,
                config.objectStorageUrl, opts.logChanges);

            // 비디오 src도 교체
            this.replaceInAttributes('onclick', /\{\{OBJECT_STORAGE_MEDIA_BASE\}\}/g,
                config.objectStorageUrl, opts.logChanges);

            // CSS background-image 변수 교체
            this.replaceInStyleElements(/\{\{OBJECT_STORAGE_MEDIA_BASE\}\}/g,
                config.objectStorageUrl, opts.logChanges);

            // 파일 업로드 URL 교체
            this.replaceInElements('[src*="{{OBJECT_STORAGE_FILES_BASE}}"]', 'src',
                /\{\{OBJECT_STORAGE_FILES_BASE\}\}/g,
                config.objectStorageFilesUrl, opts.logChanges);
        }

        // 3. 서버 IP 및 호스트 템플릿 변수 교체
        if (opts.replaceServerIps) {
            // APP_SERVER_URL 변수 교체
            this.replaceTextContent(/\{\{APP_SERVER_URL\}\}/g,
                `http://${config.appServerHost}:${config.appPort}`, opts.logChanges);

            // DB_SERVER_URL 변수 교체
            this.replaceTextContent(/\{\{DB_SERVER_URL\}\}/g,
                `postgresql://${config.dbServerHost}:${config.dbPort}/${config.databaseName}`, opts.logChanges);
        }

        console.log('✅ Template Variables Loader: All template variables replacement completed');
    }

    /**
     * DOM 요소의 속성값 교체
     * @param {string} selector CSS 선택자
     * @param {string} attribute 속성명
     * @param {RegExp} pattern 교체할 패턴
     * @param {string} replacement 교체할 값
     * @param {boolean} logChanges 변경사항 로그 출력 여부
     */
    replaceInElements(selector, attribute, pattern, replacement, logChanges = false) {
        const elements = document.querySelectorAll(selector);
        elements.forEach(element => {
            const oldValue = element.getAttribute(attribute);
            if (oldValue && pattern.test(oldValue)) {
                const newValue = oldValue.replace(pattern, replacement);
                element.setAttribute(attribute, newValue);

                if (logChanges) {
                    console.log(`🔄 Template variable replacement: ${selector} ${attribute}`, {
                        old: oldValue,
                        new: newValue
                    });
                }
            }
        });
    }

    /**
     * 특정 속성 내 템플릿 변수 교체 (onclick 등)
     * @param {string} attributeName 속성명
     * @param {RegExp} pattern 교체할 패턴
     * @param {string} replacement 교체할 값
     * @param {boolean} logChanges 변경사항 로그 출력 여부
     */
    replaceInAttributes(attributeName, pattern, replacement, logChanges = false) {
        const elements = document.querySelectorAll(`[${attributeName}*="{{"]`);
        elements.forEach(element => {
            const oldValue = element.getAttribute(attributeName);
            if (oldValue && pattern.test(oldValue)) {
                const newValue = oldValue.replace(pattern, replacement);
                element.setAttribute(attributeName, newValue);

                if (logChanges) {
                    console.log(`🔄 Template variable in attribute: ${attributeName}`, {
                        element: element.tagName,
                        old: oldValue,
                        new: newValue
                    });
                }
            }
        });
    }

    /**
     * CSS 스타일 요소 내 변수 교체
     * @param {RegExp} pattern 교체할 패턴
     * @param {string} replacement 교체할 값
     * @param {boolean} logChanges 변경사항 로그 출력 여부
     */
    replaceInStyleElements(pattern, replacement, logChanges = false) {
        // <style> 태그 내용 교체
        const styleElements = document.querySelectorAll('style');
        styleElements.forEach(styleElement => {
            const oldContent = styleElement.textContent;
            if (oldContent && pattern.test(oldContent)) {
                const newContent = oldContent.replace(pattern, replacement);
                styleElement.textContent = newContent;

                if (logChanges) {
                    console.log('🔄 CSS style replacement:', {
                        pattern: pattern.toString(),
                        replacement: replacement
                    });
                }
            }
        });

        // inline style 속성 교체
        const elementsWithStyle = document.querySelectorAll('[style*="background-image"], [style*="url("]');
        elementsWithStyle.forEach(element => {
            const oldStyle = element.getAttribute('style');
            if (oldStyle && pattern.test(oldStyle)) {
                const newStyle = oldStyle.replace(pattern, replacement);
                element.setAttribute('style', newStyle);

                if (logChanges) {
                    console.log('🔄 Inline style replacement:', {
                        element: element.tagName,
                        old: oldStyle,
                        new: newStyle
                    });
                }
            }
        });
    }

    /**
     * 텍스트 컨텐츠 내 변수 교체 (JavaScript 변수, JSON 데이터 등)
     * @param {RegExp} pattern 교체할 패턴
     * @param {string} replacement 교체할 값
     * @param {boolean} logChanges 변경사항 로그 출력 여부
     */
    replaceTextContent(pattern, replacement, logChanges = false) {
        // script 태그 내용 교체 (JSON 데이터, 변수 등)
        const scriptElements = document.querySelectorAll('script:not([src])');
        scriptElements.forEach(scriptElement => {
            const oldContent = scriptElement.textContent;
            if (oldContent && pattern.test(oldContent)) {
                const newContent = oldContent.replace(pattern, replacement);
                scriptElement.textContent = newContent;

                if (logChanges) {
                    console.log('🔄 Script content replacement:', {
                        pattern: pattern.toString(),
                        replacement: replacement
                    });
                }
            }
        });

        // data-* 속성 내 변수 교체
        const elementsWithData = document.querySelectorAll('[data-api-url], [data-server-url], [data-config]');
        elementsWithData.forEach(element => {
            Array.from(element.attributes).forEach(attr => {
                if (attr.name.startsWith('data-') && pattern.test(attr.value)) {
                    const newValue = attr.value.replace(pattern, replacement);
                    element.setAttribute(attr.name, newValue);

                    if (logChanges) {
                        console.log('🔄 Data attribute replacement:', {
                            element: element.tagName,
                            attribute: attr.name,
                            old: attr.value,
                            new: newValue
                        });
                    }
                }
            });
        });
    }

    /**
     * 설정값 조회
     * @param {string} key 설정 키
     * @returns {any} 설정값
     */
    getConfig(key) {
        if (!this.config) {
            console.warn('⚠️ Configuration not loaded. Call loadConfig() first.');
            return this.fallbackConfig[key];
        }
        return this.config[key];
    }

    /**
     * 모든 설정값 조회
     * @returns {Object} 전체 설정 객체
     */
    getAllConfig() {
        return this.config || this.fallbackConfig;
    }

    /**
     * Public 도메인 URL 생성
     * @param {string} path 경로
     * @returns {string} 완전한 URL
     */
    getPublicUrl(path = '') {
        const domain = this.getConfig('publicDomain');
        const cleanPath = path.startsWith('/') ? path : '/' + path;
        return `http://www.${domain}${cleanPath}`;
    }

    /**
     * Private 도메인 URL 생성  
     * @param {string} path 경로
     * @returns {string} 완전한 URL
     */
    getPrivateUrl(path = '') {
        const domain = this.getConfig('privateDomain');
        const cleanPath = path.startsWith('/') ? path : '/' + path;
        return `http://www.${domain}${cleanPath}`;
    }

    /**
     * App Server URL 생성
     * @param {string} path 경로
     * @returns {string} 완전한 URL
     */
    getAppServerUrl(path = '') {
        const host = this.getConfig('appServerHost');
        const port = this.getConfig('appPort');
        const cleanPath = path.startsWith('/') ? path : '/' + path;
        return `http://${host}:${port}${cleanPath}`;
    }

    /**
     * Database Server URL 생성
     * @param {string} database 데이터베이스명
     * @returns {string} 데이터베이스 연결 문자열
     */
    getDatabaseUrl(database = '') {
        const host = this.getConfig('dbServerHost');
        const port = this.getConfig('dbPort');
        const dbName = database || this.getConfig('databaseName');
        return `postgresql://${host}:${port}/${dbName}`;
    }

    /**
     * Object Storage 미디어 URL 생성
     * @param {string} filename 파일명
     * @returns {string} 완전한 URL
     */
    getMediaUrl(filename = '') {
        const baseUrl = this.getConfig('objectStorageUrl');
        return baseUrl + filename;
    }

    /**
     * Object Storage 파일 URL 생성
     * @param {string} filename 파일명
     * @returns {string} 완전한 URL
     */
    getFileUrl(filename = '') {
        const baseUrl = this.getConfig('objectStorageFilesUrl');
        return baseUrl + filename;
    }

    /**
     * CORS 허용 도메인 목록 생성
     * @returns {Array} 허용 도메인 배열
     */
    getCorsOrigins() {
        const publicDomain = this.getConfig('publicDomain');
        const privateDomain = this.getConfig('privateDomain');

        return [
            `http://www.${publicDomain}`,
            `https://www.${publicDomain}`,
            `http://${publicDomain}`,
            `https://${publicDomain}`,
            `http://www.${privateDomain}`,
            `https://www.${privateDomain}`,
            `http://${privateDomain}`,
            `https://${privateDomain}`
        ];
    }
}

// 전역 인스턴스 생성 (하위 호환성을 위해 기존 이름도 유지)
window.TemplateVariablesLoader = window.TemplateVariablesLoader || new TemplateVariablesLoader();
window.MasterVariablesLoader = window.TemplateVariablesLoader; // 하위 호환성

/**
 * 페이지 로드 시 자동 실행 함수
 * @param {Object} options 실행 옵션
 */
window.initTemplateVariables = async function (options = {}) {
    try {
        await window.TemplateVariablesLoader.replaceAllVariables(options);
    } catch (error) {
        console.error('❌ Template Variables Loader initialization failed:', error);
    }
};

// 하위 호환성을 위한 기존 함수명 유지
window.initMasterVariables = window.initTemplateVariables;

/**
 * 설정값 조회 전역 함수
 * @param {string} key 설정 키
 * @returns {any} 설정값
 */
window.getConfigValue = function (key) {
    return window.TemplateVariablesLoader.getConfig(key);
};

/**
 * URL 생성 헬퍼 함수들
 */
window.TemplateVariables = {
    getPublicUrl: (path) => window.TemplateVariablesLoader.getPublicUrl(path),
    getPrivateUrl: (path) => window.TemplateVariablesLoader.getPrivateUrl(path),
    getAppServerUrl: (path) => window.TemplateVariablesLoader.getAppServerUrl(path),
    getDatabaseUrl: (database) => window.TemplateVariablesLoader.getDatabaseUrl(database),
    getMediaUrl: (filename) => window.TemplateVariablesLoader.getMediaUrl(filename),
    getFileUrl: (filename) => window.TemplateVariablesLoader.getFileUrl(filename),
    getCorsOrigins: () => window.TemplateVariablesLoader.getCorsOrigins(),
    getAllConfig: () => window.TemplateVariablesLoader.getAllConfig()
};

// 하위 호환성을 위한 기존 객체명 유지
window.MasterVariables = window.TemplateVariables;

// DOM 로드 완료 시 자동 실행 (옵션)
document.addEventListener('DOMContentLoaded', function () {
    // 자동 실행을 원하지 않는 페이지는 data-no-auto-variables 속성 추가
    if (document.documentElement.hasAttribute('data-no-auto-variables')) {
        console.log('🔧 Template Variables Loader: Auto-execution disabled');
        return;
    }

    // 개발 환경에서는 로그 출력
    const isDevelopment = window.location.hostname === 'localhost' ||
        window.location.hostname === '127.0.0.1' ||
        window.location.hostname.startsWith('192.168.');

    window.initTemplateVariables({
        logChanges: isDevelopment
    });
});

console.log('✅ Template Variables Loader module loaded successfully');