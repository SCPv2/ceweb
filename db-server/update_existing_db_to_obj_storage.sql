--
-- Creative Energy Database Update Script
-- 기존 데이터베이스를 Object Storage URL로 업데이트
-- 기존 상대경로를 Samsung Cloud Platform Object Storage URL로 변경
--

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

-- =====================================
-- 1. 업데이트 전 백업 확인
-- =====================================

-- 업데이트 전 현재 상품 데이터 확인
SELECT 
    'UPDATE 전 상품 이미지 경로 현황' as status,
    COUNT(*) as total_products,
    COUNT(CASE WHEN image LIKE '../media/img/%' THEN 1 END) as relative_path_count,
    COUNT(CASE WHEN image LIKE 'https://object-store%' THEN 1 END) as object_storage_count
FROM products;

-- 업데이트 대상 상품 목록 표시
SELECT 
    id,
    title,
    image as current_image_path,
    'https://object-store.kr-west1.e.samsungsdscloud.com/thisneedstobereplaced1234:ceweb/media/img/' || 
    SUBSTRING(image FROM '[^/]*$') as new_object_storage_url
FROM products 
WHERE image LIKE '../media/img/%'
ORDER BY id;

-- =====================================
-- 2. 상품 이미지 경로 업데이트
-- =====================================

-- 상품 테이블의 이미지 경로를 Object Storage URL로 변경
UPDATE products 
SET 
    image = 'https://object-store.kr-west1.e.samsungsdscloud.com/thisneedstobereplaced1234:ceweb/media/img/' || 
            SUBSTRING(image FROM '[^/]*$'),
    updated_at = CURRENT_TIMESTAMP
WHERE image LIKE '../media/img/%';

-- 업데이트 결과 확인
SELECT 
    'UPDATE 후 상품 이미지 경로 현황' as status,
    COUNT(*) as total_products,
    COUNT(CASE WHEN image LIKE '../media/img/%' THEN 1 END) as relative_path_count,
    COUNT(CASE WHEN image LIKE 'https://object-store%' THEN 1 END) as object_storage_count
FROM products;

-- =====================================
-- 3. 업데이트된 상품 목록 확인
-- =====================================

-- 업데이트된 모든 상품의 새로운 이미지 URL 확인
SELECT 
    id,
    title,
    category,
    image as object_storage_url,
    updated_at
FROM products 
ORDER BY id;

-- =====================================
-- 4. View 업데이트 확인
-- =====================================

-- product_inventory_view에서 Object Storage URL이 제대로 표시되는지 확인
SELECT 
    id,
    title,
    category,
    image as object_storage_url,
    stock_quantity,
    stock_display
FROM product_inventory_view 
ORDER BY id;

-- =====================================
-- 5. 업데이트 완료 상태 확인
-- =====================================

-- 최종 업데이트 성공 여부 확인
DO $$
DECLARE
    relative_path_count INTEGER;
    object_storage_count INTEGER;
    total_count INTEGER;
BEGIN
    SELECT 
        COUNT(CASE WHEN image LIKE '../media/img/%' THEN 1 END),
        COUNT(CASE WHEN image LIKE 'https://object-store%' THEN 1 END),
        COUNT(*)
    INTO relative_path_count, object_storage_count, total_count
    FROM products;
    
    RAISE NOTICE '업데이트 완료 통계:';
    RAISE NOTICE '- 전체 상품 수: %', total_count;
    RAISE NOTICE '- Object Storage URL 적용된 상품: %', object_storage_count;
    RAISE NOTICE '- 상대경로 남은 상품: %', relative_path_count;
    
    IF relative_path_count = 0 AND object_storage_count > 0 THEN
        RAISE NOTICE '✅ Object Storage URL 업데이트가 성공적으로 완료되었습니다!';
    ELSE
        RAISE WARNING '⚠️  일부 상품의 경로 업데이트가 완료되지 않았습니다. 수동 확인이 필요합니다.';
    END IF;
END;
$$;

-- =====================================
-- 6. 롤백을 위한 백업 정보 생성 (선택사항)
-- =====================================

-- 롤백이 필요한 경우를 위한 참고 쿼리 (실행하지 않음, 주석으로 보관)
/*
-- 롤백 쿼리 (필요시 사용)
UPDATE products 
SET 
    image = '../media/img/' || SUBSTRING(image FROM '[^/]*$'),
    updated_at = CURRENT_TIMESTAMP
WHERE image LIKE 'https://object-store.kr-west1.e.samsungsdscloud.com/thisneedstobereplaced1234:ceweb/media/img/%';
*/

-- =====================================
-- 7. 업데이트 완료 메시지
-- =====================================

SELECT 
    'Object Storage URL 업데이트 완료!' as update_status,
    'thisneedstobereplaced1234:ceweb' as bucket_info,
    'https://object-store.kr-west1.e.samsungsdscloud.com' as endpoint,
    current_timestamp as completion_time;