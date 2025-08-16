const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const cron = require('node-cron');
require('dotenv').config();

const pool = require('./config/database');
const ordersRoutes = require('./routes/orders');
const auditionRoutes = require('./routes/audition');

const app = express();
const PORT = process.env.PORT || 3000;

// 미들웨어 설정
app.use(helmet());
app.use(morgan('combined'));

// CORS 설정 (Load Balancer 환경)
const corsOptions = {
  origin: function (origin, callback) {
    const allowedOrigins = process.env.ALLOWED_ORIGINS 
      ? process.env.ALLOWED_ORIGINS.split(',') 
      : [
          // Load Balancer 도메인들
          'http://www.cesvc.net', 'https://www.cesvc.net',
          'http://app.cesvc.net', 'https://app.cesvc.net',
          
          // 실제 웹서버 IP들
          'http://10.1.1.111', 'https://10.1.1.111',
          'http://10.1.1.112', 'https://10.1.1.112',
          
          // Load Balancer IP들
          'http://10.1.1.100', 'https://10.1.1.100',
          'http://10.1.2.100', 'https://10.1.2.100',
          
          // 개발용
          'http://localhost:3000', 'http://127.0.0.1:3000',
          'http://localhost', 'http://127.0.0.1'
        ];
    
    // origin이 undefined인 경우 (서버 간 통신, 같은 도메인) 허용
    if (!origin) return callback(null, true);
    
    // Load Balancer 환경에서는 X-Forwarded-Host 헤더도 확인
    if (allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      console.log(`CORS 차단: 허용되지 않은 origin ${origin}`);
      callback(new Error('CORS 정책에 의해 접근이 거부되었습니다.'));
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'HEAD'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'X-Forwarded-For', 'X-Forwarded-Host', 'X-Real-IP']
};

app.use(cors(corsOptions));
app.use(express.json({ charset: 'utf-8' }));
app.use(express.urlencoded({ extended: true, charset: 'utf-8' }));

// 라우트 설정
app.use('/api/orders', ordersRoutes);
app.use('/api/audition', auditionRoutes);

// 기본 라우트
app.get('/', (req, res) => {
  res.json({
    success: true,
    message: 'Creative Energy Order Management API Server',
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

// 헬스체크 엔드포인트
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    
    // 서버 정보 포함
    const os = require('os');
    const fs = require('fs');
    const path = require('path');
    
    // VM 정보 파일에서 VM 번호 읽기
    let vmNumber = '1';
    let vmInfo = {};
    try {
      const vmInfoPath = path.join(process.cwd(), 'vm-info.json');
      if (fs.existsSync(vmInfoPath)) {
        vmInfo = JSON.parse(fs.readFileSync(vmInfoPath, 'utf8'));
        vmNumber = vmInfo.vm_number || '1';
      }
    } catch (vmError) {
      console.warn('VM 정보 파일 읽기 실패:', vmError.message);
    }
    
    // Load Balancer 환경을 위한 추가 정보
    const hostname = os.hostname();
    const internalIp = Object.values(os.networkInterfaces()).flat().find(i => !i.internal && i.family === 'IPv4')?.address || 'unknown';
    
    res.json({
      success: true,
      message: 'Server is healthy',
      database: 'Connected',
      hostname: hostname,
      ip: internalIp,
      vm_number: vmNumber,
      vm_type: 'app',
      load_balancer: {
        name: 'app.cesvc.net',
        ip: '10.1.2.100',
        policy: 'Round Robin'
      },
      architecture: {
        tier: 'App Server',
        role: 'API Processing + Business Logic',
        database: 'db.cesvc.net:2866'
      },
      performance: {
        uptime: process.uptime(),
        memory: process.memoryUsage(),
        node_version: process.version,
        pm2_status: 'online'
      },
      timestamp: new Date().toISOString(),
      request_headers: {
        'x-forwarded-for': req.headers['x-forwarded-for'] || 'direct',
        'x-forwarded-host': req.headers['x-forwarded-host'] || hostname,
        'user-agent': req.headers['user-agent'] || 'unknown'
      }
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Database connection failed',
      error: error.message,
      hostname: require('os').hostname(),
      timestamp: new Date().toISOString()
    });
  }
});

// 에러 핸들러
app.use((err, req, res, next) => {
  console.error('서버 오류:', err.stack);
  
  if (err.message.includes('CORS')) {
    res.status(403).json({
      success: false,
      message: '접근이 거부되었습니다.'
    });
  } else {
    res.status(500).json({
      success: false,
      message: '서버 내부 오류가 발생했습니다.'
    });
  }
});

// 404 핸들러
app.use('*', (req, res) => {
  res.status(404).json({
    success: false,
    message: '요청하신 리소스를 찾을 수 없습니다.'
  });
});

// 매일 자정 재고 리셋 스케줄러
cron.schedule('0 0 * * *', async () => {
  try {
    console.log('일일 재고 리셋 시작...');
    
    const query = `
      UPDATE inventory 
      SET stock_quantity = 100, 
          reserved_quantity = 0,
          updated_at = CURRENT_TIMESTAMP
    `;
    
    const result = await pool.query(query);
    console.log(`재고 리셋 완료: ${result.rowCount}개 상품의 재고가 100개로 리셋되었습니다.`);
    
  } catch (error) {
    console.error('재고 리셋 오류:', error);
  }
}, {
  timezone: "Asia/Seoul"
});

// 서버 시작 - 모든 인터페이스에서 접근 허용 (별도 App Server용)
const BIND_HOST = process.env.BIND_HOST || '0.0.0.0';
app.listen(PORT, BIND_HOST, () => {
  console.log(`=================================`);
  console.log(`Creative Energy API Server`);
  console.log(`Host: ${BIND_HOST}`);
  console.log(`Port: ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`Database: ${process.env.DB_HOST || 'db.cesvc.net'}`);
  console.log(`Server URL: http://${BIND_HOST === '0.0.0.0' ? 'app.cesvc.net' : BIND_HOST}:${PORT}`);
  console.log(`Started at: ${new Date().toISOString()}`);
  console.log(`=================================`);
});

// 프로세스 종료 시 정리 작업
process.on('SIGINT', () => {
  console.log('서버 종료 중...');
  pool.end(() => {
    console.log('데이터베이스 연결 종료됨');
    process.exit(0);
  });
});

process.on('SIGTERM', () => {
  console.log('서버 종료 중...');
  pool.end(() => {
    console.log('데이터베이스 연결 종료됨');
    process.exit(0);
  });
});