const express = require('express');
const router = express.Router();
const pool = require('../config/database');
const { getObjectStorageService } = require('../objService');

// Object Storage 서비스 인스턴스
const objectStorageService = getObjectStorageService();

// 공용 상품 목록 조회 (shop_obj.html용)
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
    
    // 상품 이미지 경로를 Object Storage URL로 변환
    const products = result.rows.map(product => ({
      ...product,
      image: objectStorageService.convertRelativePathToObjectStorageUrl(product.image)
    }));
    
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
    
    res.json({
      success: true,
      products: products,
      server_info: {
        hostname: os.hostname(),
        ip: Object.values(os.networkInterfaces()).flat().find(i => !i.internal && i.family === 'IPv4')?.address || 'unknown',
        vm_number: vmNumber,
        vm_type: 'app',
        response_time: new Date().toISOString(),
        products_count: products.length,
        object_storage: 'enabled'
      }
    });
    
  } catch (error) {
    console.error('상품 목록 조회 오류:', error);
    res.status(500).json({
      success: false,
      message: '상품 목록 조회 중 오류가 발생했습니다.',
      server_info: {
        hostname: require('os').hostname(),
        error: true,
        timestamp: new Date().toISOString()
      }
    });
  }
});

// 상품 재고 조회 (Object Storage 버전)
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
    
    const product = result.rows[0];
    // 상품 이미지 경로를 Object Storage URL로 변환
    product.image = objectStorageService.convertRelativePathToObjectStorageUrl(product.image);
    
    res.json({
      success: true,
      product: product
    });
    
  } catch (error) {
    console.error('상품 재고 조회 오류:', error);
    res.status(500).json({
      success: false,
      message: '서버 오류가 발생했습니다.'
    });
  }
});

// 주문 생성 (Object Storage 버전)
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

// 주문 내역 조회 (Object Storage 버전)
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

// 특정 고객의 주문 내역 조회 (Object Storage 버전)
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

// 관리자 API - 상품 목록 조회 (Object Storage 버전)
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
    
    // 상품 이미지 경로를 Object Storage URL로 변환
    const products = result.rows.map(product => ({
      ...product,
      image: objectStorageService.convertRelativePathToObjectStorageUrl(product.image)
    }));
    
    res.json({
      success: true,
      products: products
    });
    
  } catch (error) {
    console.error('상품 목록 조회 오류:', error);
    res.status(500).json({
      success: false,
      message: '상품 목록 조회 중 오류가 발생했습니다.'
    });
  }
});

// 관리자 API - 상품 등록 (Object Storage 버전)
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
    
    // 이미지 경로가 Object Storage URL이 아닌 경우 변환
    let finalImageUrl = image;
    if (image && !image.startsWith('https://object-store.')) {
      finalImageUrl = objectStorageService.convertRelativePathToObjectStorageUrl(image);
    }
    
    const query = `
      INSERT INTO products (title, subtitle, price_numeric, price, category, type, badge, image)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING id
    `;
    
    const result = await pool.query(query, [
      title, subtitle, price_numeric, price, category, type, badge, finalImageUrl
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
      productId: productId,
      imageUrl: finalImageUrl
    });
    
  } catch (error) {
    console.error('상품 등록 오류:', error);
    res.status(500).json({
      success: false,
      message: '상품 등록 중 오류가 발생했습니다.'
    });
  }
});

// 관리자 API - 상품 수정 (Object Storage 버전)
router.put('/admin/products/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { title, subtitle, price_numeric, price, category, type, badge, image } = req.body;
    
    // 이미지 경로가 Object Storage URL이 아닌 경우 변환
    let finalImageUrl = image;
    if (image && !image.startsWith('https://object-store.')) {
      finalImageUrl = objectStorageService.convertRelativePathToObjectStorageUrl(image);
    }
    
    const query = `
      UPDATE products 
      SET title = $1, subtitle = $2, price_numeric = $3, price = $4, 
          category = $5, type = $6, badge = $7, image = $8,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = $9
    `;
    
    const result = await pool.query(query, [
      title, subtitle, price_numeric, price, category, type, badge, finalImageUrl, id
    ]);
    
    if (result.rowCount === 0) {
      return res.status(404).json({
        success: false,
        message: '상품을 찾을 수 없습니다.'
      });
    }
    
    res.json({
      success: true,
      message: '상품이 수정되었습니다.',
      imageUrl: finalImageUrl
    });
    
  } catch (error) {
    console.error('상품 수정 오류:', error);
    res.status(500).json({
      success: false,
      message: '상품 수정 중 오류가 발생했습니다.'
    });
  }
});

// 관리자 API - 상품 삭제 (Object Storage 버전)
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

// 관리자 API - 재고 목록 조회 (Object Storage 버전)
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

// 관리자 API - 재고 추가 (Object Storage 버전)
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

// 관리자 API - 주문 삭제 (Object Storage 버전)
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

module.exports = router;