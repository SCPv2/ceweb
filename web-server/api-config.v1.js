/**
 * Creative Energy API Configuration
 * API 엔드포인트 및 설정 관리
 */

// API 기본 설정
const API_CONFIG = {
    // 환경별 API 기본 URL
    development: {
        baseURL: 'http://localhost:3000/api',
        timeout: 5000
    },
    production: {
        baseURL: '/api',
        timeout: 10000
    },
    
    // 현재 환경 (자동 감지)
    getCurrentEnv() {
        // 로컬 개발환경 감지
        if (window.location.hostname === 'localhost' || 
            window.location.hostname === '127.0.0.1' ||
            window.location.hostname.includes('192.168.') ||
            window.location.hostname.includes('10.0.')) {
            return 'development';
        }
        return 'production';
    },
    
    // 현재 환경 설정 반환
    get current() {
        const env = this.getCurrentEnv();
        return this[env];
    }
};

// API 엔드포인트 정의
const API_ENDPOINTS = {
    // 상품 관련
    products: {
        list: '/orders/products',
        detail: (id) => `/orders/products/${id}`,
        inventory: (id) => `/orders/products/${id}/inventory`
    },
    
    // 주문 관련  
    orders: {
        create: '/orders/create',
        list: '/orders/list',
        detail: (id) => `/orders/${id}`
    }
};

/**
 * API 요청을 위한 기본 함수
 * @param {string} endpoint - API 엔드포인트
 * @param {object} options - 요청 옵션
 * @returns {Promise} 응답 데이터
 */
async function apiRequest(endpoint, options = {}) {
    const config = API_CONFIG.current;
    const url = config.baseURL + endpoint;
    
    const defaultOptions = {
        method: 'GET',
        headers: {
            'Content-Type': 'application/json',
        },
        timeout: config.timeout
    };
    
    const requestOptions = { ...defaultOptions, ...options };
    
    try {
        console.log(`API 요청: ${requestOptions.method} ${url}`);
        
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), requestOptions.timeout);
        
        const response = await fetch(url, {
            ...requestOptions,
            signal: controller.signal
        });
        
        clearTimeout(timeoutId);
        
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        const data = await response.json();
        console.log('API 응답:', data);
        
        return data;
        
    } catch (error) {
        console.error('API 요청 실패:', error);
        
        // 네트워크 오류 처리
        if (error.name === 'AbortError') {
            throw new Error('요청 시간이 초과되었습니다.');
        }
        
        if (error.message.includes('Failed to fetch')) {
            throw new Error('서버에 연결할 수 없습니다. 네트워크 연결을 확인해주세요.');
        }
        
        throw error;
    }
}

/**
 * 상품 목록 조회
 * @returns {Promise} 상품 목록
 */
async function getProducts() {
    return await apiRequest(API_ENDPOINTS.products.list);
}

/**
 * 상품 재고 정보 조회
 * @param {number} productId - 상품 ID
 * @returns {Promise} 상품 재고 정보
 */
async function getProductInventory(productId) {
    return await apiRequest(API_ENDPOINTS.products.inventory(productId));
}

/**
 * 주문 생성
 * @param {object} orderData - 주문 데이터
 * @returns {Promise} 주문 생성 결과
 */
async function createOrder(orderData) {
    return await apiRequest(API_ENDPOINTS.orders.create, {
        method: 'POST',
        body: JSON.stringify(orderData)
    });
}

// 환경 정보 출력 (개발용)
console.log('API 환경 설정:', {
    environment: API_CONFIG.getCurrentEnv(),
    baseURL: API_CONFIG.current.baseURL,
    timeout: API_CONFIG.current.timeout
});