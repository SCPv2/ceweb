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

// CORS 설정
const corsOptions = {
  origin: function (origin, callback) {
    const allowedOrigins = process.env.ALLOWED_ORIGINS 
      ? process.env.ALLOWED_ORIGINS.split(',') 
      : [
          'http://www.cesvc.net', 'https://www.cesvc.net',
          'http://www.creative-energy.net', 'https://www.creative-energy.net',
          'http://localhost:3000', 'http://127.0.0.1:3000'
        ];
    
    // origin이 undefined인 경우 (같은 도메인) 허용
    if (!origin) return callback(null, true);
    
    if (allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error('CORS 정책에 의해 접근이 거부되었습니다.'));
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']
};

app.use(cors(corsOptions));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

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
    res.json({
      success: true,
      message: 'Server is healthy',
      database: 'Connected',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Database connection failed',
      error: error.message,
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