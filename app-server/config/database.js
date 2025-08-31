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

const { Pool } = require('pg');
require('dotenv').config();

// 외부 DB 서버용 PostgreSQL 연결 풀 설정
const pool = new Pool({
  host: process.env.DB_HOST || 'db.your_private_domain_name.net',
  port: process.env.DB_PORT || 2866,
  database: process.env.DB_NAME || 'cedb',
  user: process.env.DB_USER || 'cedbadmin',
  password: process.env.DB_PASSWORD,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,

  // 연결 풀 설정
  min: parseInt(process.env.DB_POOL_MIN) || 2,
  max: parseInt(process.env.DB_POOL_MAX) || 10,
  idleTimeoutMillis: parseInt(process.env.DB_POOL_IDLE_TIMEOUT) || 30000,
  connectionTimeoutMillis: parseInt(process.env.DB_POOL_CONNECTION_TIMEOUT) || 5000,

  // 네트워크 지연을 고려한 타임아웃 설정
  query_timeout: 60000,
  statement_timeout: 60000,

  // 에러 핸들링
  allowExitOnIdle: true
});

// 연결 풀 이벤트 리스너
pool.on('connect', (client) => {
  console.log('✅ PostgreSQL 외부 DB 서버 연결 성공:', {
    host: process.env.DB_HOST || 'db.your_private_domain_name.net',
    port: process.env.DB_PORT || 2866,
    database: process.env.DB_NAME || 'cedb'
  });
});

pool.on('error', (err, client) => {
  console.error('❌ PostgreSQL 연결 풀 오류:', err.message);
  console.error('연결 정보:', {
    host: process.env.DB_HOST || 'db.your_private_domain_name.net',
    port: process.env.DB_PORT || 2866,
    database: process.env.DB_NAME || 'cedb',
    user: process.env.DB_USER || 'cedbadmin'
  });
});

// 애플리케이션 시작 시 DB 연결 테스트
const testConnection = async () => {
  try {
    const client = await pool.connect();
    await client.query('SELECT 1');
    console.log('✅ DB 연결 테스트 성공');
    client.release();
  } catch (error) {
    console.error('❌ DB 연결 테스트 실패:', error.message);
    console.error('DB 서버 연결 정보를 확인해주세요:');
    console.error('- Host:', process.env.DB_HOST || 'db.your_private_domain_name.net');
    console.error('- Port:', process.env.DB_PORT || 2866);
    console.error('- Database:', process.env.DB_NAME || 'cedb');
    console.error('- User:', process.env.DB_USER || 'cedbadmin');
  }
};

// 초기 연결 테스트 실행
testConnection();

// 프로세스 종료 시 연결 풀 정리
process.on('SIGINT', () => {
  console.log('\n🔄 애플리케이션 종료 중... DB 연결 풀 정리');
  pool.end(() => {
    console.log('✅ DB 연결 풀 정리 완료');
    process.exit(0);
  });
});

process.on('SIGTERM', () => {
  console.log('\n🔄 애플리케이션 종료 중... DB 연결 풀 정리');
  pool.end(() => {
    console.log('✅ DB 연결 풀 정리 완료');
    process.exit(0);
  });
});

module.exports = pool;