const express = require('express');
const router = express.Router();
const pool = require('../config/database');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// 파일 업로드 설정
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = path.join(__dirname, '../../files');
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    // 파일명을 고유하게 생성 (타임스탬프 + 원본 파일명)
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    const name = path.basename(file.originalname, ext);
    cb(null, `${name}_${uniqueSuffix}${ext}`);
  }
});

const fileFilter = function (req, file, cb) {
  // 허용되는 파일 타입
  const allowedTypes = [
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'audio/mpeg',
    'audio/mp3',
    'video/mp4',
    'image/jpeg',
    'image/jpg', 
    'image/png'
  ];
  
  if (allowedTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error('지원하지 않는 파일 형식입니다.'), false);
  }
};

const upload = multer({
  storage: storage,
  fileFilter: fileFilter,
  limits: {
    fileSize: 50 * 1024 * 1024 // 50MB 제한
  }
});

// 공용 상품 목록 조회 (shop.html용)
router.get('/products', async (req, res) => {
  try {
    const query = `
      SELECT 
        p.id,
        p.title,
        p.subtitle,
        p.price,
        p.price_numeric,
        p.image,
        p.category,
        p.type,
        p.badge,
        COALESCE(i.stock_quantity, 0) as stock_quantity,
        CASE 
          WHEN COALESCE(i.stock_quantity, 0) = 0 THEN '매진'
          ELSE COALESCE(i.stock_quantity, 0)::text
        END as stock_display
      FROM products p
      LEFT JOIN inventory i ON p.id = i.product_id
      ORDER BY p.id
    `;
    
    const result = await pool.query(query);
    
    res.json({
      success: true,
      products: result.rows
    });
    
  } catch (error) {
    console.error('상품 목록 조회 오류:', error);
    res.status(500).json({
      success: false,
      message: '상품 목록 조회 중 오류가 발생했습니다.'
    });
  }
});

// 상품 재고 조회
router.get('/products/:productId/inventory', async (req, res) => {
  try {
    const { productId } = req.params;
    
    const query = `
      SELECT 
        p.id,
        p.title,
        p.subtitle,
        p.price,
        p.price_numeric,
        p.image,
        p.category,
        p.type,
        p.badge,
        COALESCE(i.stock_quantity, 0) as stock_quantity,
        CASE 
          WHEN COALESCE(i.stock_quantity, 0) = 0 THEN '매진'
          ELSE COALESCE(i.stock_quantity, 0)::text
        END as stock_display
      FROM products p
      LEFT JOIN inventory i ON p.id = i.product_id
      WHERE p.id = $1
    `;
    
    const result = await pool.query(query, [productId]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: '상품을 찾을 수 없습니다.'
      });
    }
    
    res.json({
      success: true,
      product: result.rows[0]
    });
    
  } catch (error) {
    console.error('상품 재고 조회 오류:', error);
    res.status(500).json({
      success: false,
      message: '서버 오류가 발생했습니다.'
    });
  }
});

// 주문 생성
router.post('/create', async (req, res) => {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    const { customerName, productId, quantity } = req.body;
    
    // 입력 데이터 검증
    if (!customerName || !productId || !quantity || quantity <= 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        message: '주문 정보가 올바르지 않습니다.'
      });
    }
    
    // 상품 정보 조회
    const productQuery = `
      SELECT p.*, i.stock_quantity
      FROM products p
      LEFT JOIN inventory i ON p.id = i.product_id
      WHERE p.id = $1
    `;
    const productResult = await client.query(productQuery, [productId]);
    
    if (productResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        success: false,
        message: '상품을 찾을 수 없습니다.'
      });
    }
    
    const product = productResult.rows[0];
    const currentStock = product.stock_quantity || 0;
    
    // 재고 부족 체크
    if (currentStock < quantity) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        message: `재고가 부족합니다. (현재 재고: ${currentStock}개)`
      });
    }
    
    // 재고 차감
    const updateInventoryQuery = `
      UPDATE inventory 
      SET stock_quantity = stock_quantity - $1,
          updated_at = CURRENT_TIMESTAMP
      WHERE product_id = $2
      RETURNING stock_quantity
    `;
    const inventoryResult = await client.query(updateInventoryQuery, [quantity, productId]);
    
    // 주문 저장
    const totalPrice = product.price_numeric * quantity;
    const insertOrderQuery = `
      INSERT INTO orders (customer_name, product_id, quantity, unit_price, total_price)
      VALUES ($1, $2, $3, $4, $5)
      RETURNING id, order_date
    `;
    const orderResult = await client.query(insertOrderQuery, [
      customerName, 
      productId, 
      quantity, 
      product.price_numeric, 
      totalPrice
    ]);
    
    await client.query('COMMIT');
    
    const newStock = inventoryResult.rows[0].stock_quantity;
    
    res.json({
      success: true,
      message: '주문이 성공적으로 완료되었습니다.',
      order: {
        id: orderResult.rows[0].id,
        customerName,
        productTitle: product.title,
        quantity,
        totalPrice,
        orderDate: orderResult.rows[0].order_date,
        remainingStock: newStock
      }
    });
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('주문 생성 오류:', error);
    res.status(500).json({
      success: false,
      message: '주문 처리 중 오류가 발생했습니다.'
    });
  } finally {
    client.release();
  }
});

// 주문 내역 조회
router.get('/list', async (req, res) => {
  try {
    const query = `
      SELECT 
        o.id,
        o.customer_name,
        p.title as product_title,
        p.subtitle as product_subtitle,
        p.price,
        o.quantity,
        o.unit_price,
        o.total_price,
        o.order_date,
        o.status
      FROM orders o
      JOIN products p ON o.product_id = p.id
      ORDER BY o.order_date DESC
      LIMIT 100
    `;
    
    const result = await pool.query(query);
    
    res.json({
      success: true,
      orders: result.rows
    });
    
  } catch (error) {
    console.error('주문 내역 조회 오류:', error);
    res.status(500).json({
      success: false,
      message: '주문 내역 조회 중 오류가 발생했습니다.'
    });
  }
});

// 특정 고객의 주문 내역 조회
router.get('/customer/:customerName', async (req, res) => {
  try {
    const { customerName } = req.params;
    
    const query = `
      SELECT 
        o.id,
        o.customer_name,
        p.title as product_title,
        p.subtitle as product_subtitle,
        p.price,
        o.quantity,
        o.unit_price,
        o.total_price,
        o.order_date,
        o.status
      FROM orders o
      JOIN products p ON o.product_id = p.id
      WHERE o.customer_name = $1
      ORDER BY o.order_date DESC
    `;
    
    const result = await pool.query(query, [customerName]);
    
    res.json({
      success: true,
      orders: result.rows
    });
    
  } catch (error) {
    console.error('고객 주문 내역 조회 오류:', error);
    res.status(500).json({
      success: false,
      message: '주문 내역 조회 중 오류가 발생했습니다.'
    });
  }
});

// 재고 리셋 (관리자용)
router.post('/admin/reset-inventory', async (req, res) => {
  try {
    const query = `
      UPDATE inventory 
      SET stock_quantity = 100, 
          reserved_quantity = 0,
          updated_at = CURRENT_TIMESTAMP
    `;
    
    const result = await pool.query(query);
    
    res.json({
      success: true,
      message: `모든 상품의 재고가 100개로 리셋되었습니다.`,
      affectedRows: result.rowCount
    });
    
  } catch (error) {
    console.error('재고 리셋 오류:', error);
    res.status(500).json({
      success: false,
      message: '재고 리셋 중 오류가 발생했습니다.'
    });
  }
});

// 관리자 API - 상품 목록 조회
router.get('/admin/products', async (req, res) => {
  try {
    const query = `
      SELECT 
        p.id,
        p.title,
        p.subtitle,
        p.price,
        p.price_numeric,
        p.image,
        p.category,
        p.type,
        p.badge
      FROM products p
      ORDER BY p.id
    `;
    
    const result = await pool.query(query);
    
    res.json({
      success: true,
      products: result.rows
    });
    
  } catch (error) {
    console.error('상품 목록 조회 오류:', error);
    res.status(500).json({
      success: false,
      message: '상품 목록 조회 중 오류가 발생했습니다.'
    });
  }
});

// 관리자 API - 상품 등록
router.post('/admin/products', async (req, res) => {
  try {
    const { title, subtitle, price_numeric, price, category, type, badge, image } = req.body;
    
    // 입력 데이터 검증
    if (!title || !price_numeric || !category) {
      return res.status(400).json({
        success: false,
        message: '필수 항목을 모두 입력해주세요.'
      });
    }
    
    const query = `
      INSERT INTO products (title, subtitle, price_numeric, price, category, type, badge, image)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING id
    `;
    
    const result = await pool.query(query, [
      title, subtitle, price_numeric, price, category, type, badge, image
    ]);
    
    // 새 상품의 재고 초기화
    const productId = result.rows[0].id;
    await pool.query(
      'INSERT INTO inventory (product_id, stock_quantity) VALUES ($1, 100)',
      [productId]
    );
    
    res.json({
      success: true,
      message: '상품이 등록되었습니다.',
      productId: productId
    });
    
  } catch (error) {
    console.error('상품 등록 오류:', error);
    res.status(500).json({
      success: false,
      message: '상품 등록 중 오류가 발생했습니다.'
    });
  }
});

// 관리자 API - 상품 수정
router.put('/admin/products/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { title, subtitle, price_numeric, price, category, type, badge, image } = req.body;
    
    const query = `
      UPDATE products 
      SET title = $1, subtitle = $2, price_numeric = $3, price = $4, 
          category = $5, type = $6, badge = $7, image = $8,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = $9
    `;
    
    const result = await pool.query(query, [
      title, subtitle, price_numeric, price, category, type, badge, image, id
    ]);
    
    if (result.rowCount === 0) {
      return res.status(404).json({
        success: false,
        message: '상품을 찾을 수 없습니다.'
      });
    }
    
    res.json({
      success: true,
      message: '상품이 수정되었습니다.'
    });
    
  } catch (error) {
    console.error('상품 수정 오류:', error);
    res.status(500).json({
      success: false,
      message: '상품 수정 중 오류가 발생했습니다.'
    });
  }
});

// 관리자 API - 상품 삭제
router.delete('/admin/products/:id', async (req, res) => {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    const { id } = req.params;
    
    // 관련 주문이 있는지 확인
    const orderCheck = await client.query(
      'SELECT COUNT(*) as count FROM orders WHERE product_id = $1',
      [id]
    );
    
    if (parseInt(orderCheck.rows[0].count) > 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        message: '주문 내역이 있는 상품은 삭제할 수 없습니다.'
      });
    }
    
    // 재고 정보 삭제
    await client.query('DELETE FROM inventory WHERE product_id = $1', [id]);
    
    // 상품 삭제
    const result = await client.query('DELETE FROM products WHERE id = $1', [id]);
    
    if (result.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        success: false,
        message: '상품을 찾을 수 없습니다.'
      });
    }
    
    await client.query('COMMIT');
    
    res.json({
      success: true,
      message: '상품이 삭제되었습니다.'
    });
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('상품 삭제 오류:', error);
    res.status(500).json({
      success: false,
      message: '상품 삭제 중 오류가 발생했습니다.'
    });
  } finally {
    client.release();
  }
});

// 관리자 API - 재고 목록 조회
router.get('/admin/inventory', async (req, res) => {
  try {
    const query = `
      SELECT 
        p.id as product_id,
        p.title as product_title,
        COALESCE(i.stock_quantity, 0) as stock_quantity
      FROM products p
      LEFT JOIN inventory i ON p.id = i.product_id
      ORDER BY p.id
    `;
    
    const result = await pool.query(query);
    
    res.json({
      success: true,
      inventory: result.rows
    });
    
  } catch (error) {
    console.error('재고 목록 조회 오류:', error);
    res.status(500).json({
      success: false,
      message: '재고 목록 조회 중 오류가 발생했습니다.'
    });
  }
});

// 관리자 API - 재고 추가
router.post('/admin/inventory/:productId/add', async (req, res) => {
  try {
    const { productId } = req.params;
    const { quantity } = req.body;
    
    if (!quantity || quantity < 1) {
      return res.status(400).json({
        success: false,
        message: '올바른 수량을 입력해주세요.'
      });
    }
    
    const query = `
      UPDATE inventory 
      SET stock_quantity = stock_quantity + $1,
          updated_at = CURRENT_TIMESTAMP
      WHERE product_id = $2
      RETURNING stock_quantity
    `;
    
    const result = await pool.query(query, [quantity, productId]);
    
    if (result.rowCount === 0) {
      // 재고 정보가 없으면 새로 생성
      await pool.query(
        'INSERT INTO inventory (product_id, stock_quantity) VALUES ($1, $2)',
        [productId, quantity]
      );
    }
    
    res.json({
      success: true,
      message: `재고가 ${quantity}개 추가되었습니다.`,
      newStock: result.rows[0]?.stock_quantity || quantity
    });
    
  } catch (error) {
    console.error('재고 추가 오류:', error);
    res.status(500).json({
      success: false,
      message: '재고 추가 중 오류가 발생했습니다.'
    });
  }
});

// 관리자 API - 주문 삭제
router.delete('/admin/orders/:id', async (req, res) => {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    const { id } = req.params;
    
    // 주문 정보 조회
    const orderQuery = `
      SELECT product_id, quantity 
      FROM orders 
      WHERE id = $1
    `;
    const orderResult = await client.query(orderQuery, [id]);
    
    if (orderResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        success: false,
        message: '주문을 찾을 수 없습니다.'
      });
    }
    
    const order = orderResult.rows[0];
    
    // 재고 복원
    await client.query(
      `UPDATE inventory 
       SET stock_quantity = stock_quantity + $1,
           updated_at = CURRENT_TIMESTAMP
       WHERE product_id = $2`,
      [order.quantity, order.product_id]
    );
    
    // 주문 삭제
    await client.query('DELETE FROM orders WHERE id = $1', [id]);
    
    await client.query('COMMIT');
    
    res.json({
      success: true,
      message: '주문이 삭제되고 재고가 복원되었습니다.'
    });
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('주문 삭제 오류:', error);
    res.status(500).json({
      success: false,
      message: '주문 삭제 중 오류가 발생했습니다.'
    });
  } finally {
    client.release();
  }
});

// 오디션 파일 업로드
router.post('/audition/upload', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: '파일이 업로드되지 않았습니다.'
      });
    }

    const fileInfo = {
      originalName: req.file.originalname,
      fileName: req.file.filename,
      filePath: req.file.path,
      mimeType: req.file.mimetype,
      size: req.file.size,
      uploadDate: new Date()
    };

    // 데이터베이스에 파일 정보 저장 (테이블이 있는 경우)
    try {
      const query = `
        INSERT INTO audition_files (original_name, file_name, file_path, mime_type, file_size, upload_date)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id
      `;
      
      const result = await pool.query(query, [
        fileInfo.originalName,
        fileInfo.fileName,
        fileInfo.filePath,
        fileInfo.mimeType,
        fileInfo.size,
        fileInfo.uploadDate
      ]);

      res.json({
        success: true,
        message: '파일이 성공적으로 업로드되었습니다.',
        fileId: result.rows[0].id,
        fileName: fileInfo.originalName
      });

    } catch (dbError) {
      console.log('데이터베이스 저장 실패, 파일만 저장됨:', dbError.message);
      
      // DB 저장 실패해도 파일은 업로드된 상태이므로 성공으로 처리
      res.json({
        success: true,
        message: '파일이 성공적으로 업로드되었습니다.',
        fileName: fileInfo.originalName,
        note: '데이터베이스 연동은 준비 중입니다.'
      });
    }

  } catch (error) {
    console.error('파일 업로드 오류:', error);
    res.status(500).json({
      success: false,
      message: error.message || '파일 업로드 중 오류가 발생했습니다.'
    });
  }
});

// 오디션 파일 목록 조회
router.get('/audition/files', async (req, res) => {
  try {
    // 데이터베이스에서 파일 목록 조회
    const query = `
      SELECT id, original_name as name, file_name, mime_type, file_size as size, upload_date
      FROM audition_files
      ORDER BY upload_date DESC
    `;
    
    const result = await pool.query(query);
    
    res.json({
      success: true,
      files: result.rows
    });

  } catch (dbError) {
    console.log('데이터베이스 조회 실패, 파일 시스템에서 조회:', dbError.message);
    
    // DB 조회 실패시 파일 시스템에서 직접 조회
    try {
      const filesDir = path.join(__dirname, '../../files');
      
      if (!fs.existsSync(filesDir)) {
        return res.json({
          success: true,
          files: []
        });
      }

      const files = fs.readdirSync(filesDir);
      const fileList = files.map(filename => {
        const filePath = path.join(filesDir, filename);
        const stats = fs.statSync(filePath);
        const ext = path.extname(filename).toLowerCase();
        
        let mimeType = 'application/octet-stream';
        if (ext === '.pdf') mimeType = 'application/pdf';
        else if (ext === '.doc') mimeType = 'application/msword';
        else if (ext === '.docx') mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        else if (ext === '.mp3') mimeType = 'audio/mpeg';
        else if (ext === '.mp4') mimeType = 'video/mp4';
        else if (['.jpg', '.jpeg'].includes(ext)) mimeType = 'image/jpeg';
        else if (ext === '.png') mimeType = 'image/png';

        return {
          id: filename,
          name: filename,
          file_name: filename,
          mime_type: mimeType,
          size: stats.size,
          upload_date: stats.mtime
        };
      });

      res.json({
        success: true,
        files: fileList
      });

    } catch (fsError) {
      console.error('파일 시스템 조회 오류:', fsError);
      res.json({
        success: true,
        files: []
      });
    }
  }
});

// 오디션 파일 다운로드
router.get('/audition/download/:fileId', async (req, res) => {
  try {
    const { fileId } = req.params;
    let filePath;
    let fileName;

    // 데이터베이스에서 파일 정보 조회
    try {
      const query = 'SELECT file_name, file_path, original_name FROM audition_files WHERE id = $1';
      const result = await pool.query(query, [fileId]);
      
      if (result.rows.length === 0) {
        throw new Error('파일을 찾을 수 없습니다.');
      }
      
      filePath = result.rows[0].file_path;
      fileName = result.rows[0].original_name;

    } catch (dbError) {
      console.log('데이터베이스 조회 실패, 파일명으로 직접 접근:', dbError.message);
      
      // DB 조회 실패시 fileId를 파일명으로 사용
      filePath = path.join(__dirname, '../../files', fileId);
      fileName = fileId;
    }

    // 파일 존재 확인
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({
        success: false,
        message: '파일을 찾을 수 없습니다.'
      });
    }

    // 파일 다운로드
    res.download(filePath, fileName, (err) => {
      if (err) {
        console.error('파일 다운로드 오류:', err);
        if (!res.headersSent) {
          res.status(500).json({
            success: false,
            message: '파일 다운로드 중 오류가 발생했습니다.'
          });
        }
      }
    });

  } catch (error) {
    console.error('파일 다운로드 오류:', error);
    res.status(500).json({
      success: false,
      message: error.message || '파일 다운로드 중 오류가 발생했습니다.'
    });
  }
});

// 오디션 파일 삭제
router.delete('/audition/delete/:fileId', async (req, res) => {
  try {
    const { fileId } = req.params;
    let filePath;

    // 데이터베이스에서 파일 정보 조회 및 삭제
    try {
      const query = 'SELECT file_path FROM audition_files WHERE id = $1';
      const result = await pool.query(query, [fileId]);
      
      if (result.rows.length === 0) {
        throw new Error('파일을 찾을 수 없습니다.');
      }
      
      filePath = result.rows[0].file_path;

      // 데이터베이스에서 레코드 삭제
      await pool.query('DELETE FROM audition_files WHERE id = $1', [fileId]);

    } catch (dbError) {
      console.log('데이터베이스 삭제 실패, 파일명으로 직접 삭제:', dbError.message);
      
      // DB 삭제 실패시 fileId를 파일명으로 사용
      filePath = path.join(__dirname, '../../files', fileId);
    }

    // 실제 파일 삭제
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
    }

    res.json({
      success: true,
      message: '파일이 성공적으로 삭제되었습니다.'
    });

  } catch (error) {
    console.error('파일 삭제 오류:', error);
    res.status(500).json({
      success: false,
      message: error.message || '파일 삭제 중 오류가 발생했습니다.'
    });
  }
});

module.exports = router;