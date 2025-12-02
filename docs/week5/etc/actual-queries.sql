-- ================================================
-- 실제 애플리케이션에서 발생하는 쿼리
-- (Hibernate 로그에서 추출)
-- ================================================

USE loopers;

-- ================================================
-- 1. 브랜드 필터 + 좋아요 순 정렬 (실제 쿼리)
-- ================================================

-- 1-1. 메인 쿼리 (LIMIT으로 20건 조회)
EXPLAIN
SELECT
    p1_0.id,
    p1_0.brand_id,
    p1_0.created_at,
    p1_0.deleted_at,
    p1_0.description,
    p1_0.likes_count,
    p1_0.name,
    p1_0.price,
    p1_0.stock,
    p1_0.updated_at
FROM products p1_0
LEFT JOIN brands b1_0 ON b1_0.id = p1_0.brand_id
WHERE b1_0.id = 1
ORDER BY p1_0.likes_count DESC
LIMIT 20;

-- 1-2. COUNT 쿼리 (페이징을 위한 전체 개수)
EXPLAIN
SELECT COUNT(p1_0.id)
FROM products p1_0
LEFT JOIN brands b1_0 ON b1_0.id = p1_0.brand_id
WHERE b1_0.id = 1;

-- ================================================
-- 2. 전체 상품 + 좋아요 순 정렬 (실제 쿼리)
-- ================================================

-- 2-1. 메인 쿼리
EXPLAIN
SELECT
    p1_0.id,
    p1_0.brand_id,
    p1_0.created_at,
    p1_0.deleted_at,
    p1_0.description,
    p1_0.likes_count,
    p1_0.name,
    p1_0.price,
    p1_0.stock,
    p1_0.updated_at
FROM products p1_0
WHERE p1_0.deleted_at IS NULL
ORDER BY p1_0.likes_count DESC
LIMIT 20;

-- 2-2. COUNT 쿼리
EXPLAIN
SELECT COUNT(p1_0.id)
FROM products p1_0
WHERE p1_0.deleted_at IS NULL;

-- ================================================
-- 3. 최적화된 쿼리 (LEFT JOIN 제거)
-- ================================================

-- 3-1. 브랜드 필터 (JOIN 없이)
EXPLAIN
SELECT
    p1_0.id,
    p1_0.brand_id,
    p1_0.created_at,
    p1_0.deleted_at,
    p1_0.description,
    p1_0.likes_count,
    p1_0.name,
    p1_0.price,
    p1_0.stock,
    p1_0.updated_at
FROM products p1_0
WHERE p1_0.brand_id = 1
  AND p1_0.deleted_at IS NULL
ORDER BY p1_0.likes_count DESC
LIMIT 20;

-- 3-2. COUNT 쿼리 (JOIN 없이)
EXPLAIN
SELECT COUNT(*)
FROM products
WHERE brand_id = 1
  AND deleted_at IS NULL;

-- ================================================
-- 4. 실행 시간 측정
-- ================================================

-- 프로파일링 시작
SET profiling = 1;

-- 4-1. 브랜드 필터 + 좋아요순 (실제 쿼리)
SELECT p1_0.*
FROM products p1_0
LEFT JOIN brands b1_0 ON b1_0.id = p1_0.brand_id
WHERE b1_0.id = 1
ORDER BY p1_0.likes_count DESC
LIMIT 20;

-- 4-2. 브랜드 필터 + 좋아요순 (최적화)
SELECT p1_0.*
FROM products p1_0
WHERE p1_0.brand_id = 1
  AND p1_0.deleted_at IS NULL
ORDER BY p1_0.likes_count DESC
LIMIT 20;

-- 실행 시간 확인
SHOW PROFILES;

SET profiling = 0;

-- ================================================
-- 5. 인덱스 추천
-- ================================================

-- 현재 인덱스 확인
SHOW INDEXES FROM products;

-- 추천 인덱스 1: 브랜드 + 좋아요 복합 인덱스
-- CREATE INDEX idx_products_brand_likes ON products(brand_id, likes_count DESC, deleted_at);

-- 추천 인덱스 2: 전체 좋아요 순 조회용
-- CREATE INDEX idx_products_likes_deleted ON products(deleted_at, likes_count DESC);

-- 추천 인덱스 3: 좋아요 카운트만
-- CREATE INDEX idx_products_likes_count ON products(likes_count DESC);

-- ================================================
-- 6. 문제 분석
-- ================================================

-- 문제 1: 불필요한 LEFT JOIN
-- - brand_id 컬럼만으로 필터링 가능한데 brands 테이블 조인
-- - 해결: Repository에서 brand 객체가 아닌 brandId로 조회

-- 문제 2: COUNT 쿼리 성능
-- - 페이징을 위해 매번 전체 COUNT 발생
-- - 해결: 캐시 적용 또는 페이지네이션 방식 변경 (커서 기반)

-- 문제 3: deleted_at 필터링
-- - Soft delete 때문에 모든 쿼리에 deleted_at IS NULL 조건 필요
-- - 해결: 인덱스에 deleted_at 포함

-- ================================================
-- 7. 쿼리 개선 전/후 비교
-- ================================================

-- AS-IS: LEFT JOIN 사용
SELECT '=== AS-IS: LEFT JOIN 사용 ===' as info;
EXPLAIN
SELECT p1_0.*
FROM products p1_0
LEFT JOIN brands b1_0 ON b1_0.id = p1_0.brand_id
WHERE b1_0.id = 1
ORDER BY p1_0.likes_count DESC
LIMIT 20;

-- TO-BE: brand_id 직접 필터링
SELECT '=== TO-BE: brand_id 직접 필터링 ===' as info;
EXPLAIN
SELECT p1_0.*
FROM products p1_0
WHERE p1_0.brand_id = 1
  AND p1_0.deleted_at IS NULL
ORDER BY p1_0.likes_count DESC
LIMIT 20;
