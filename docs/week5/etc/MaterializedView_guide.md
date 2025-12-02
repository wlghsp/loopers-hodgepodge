# Materialized View 적용 가이드

## 개요

Materialized View는 복잡한 쿼리 결과를 미리 계산해서 테이블처럼 저장하는 기법입니다.

---

## 언제 사용하나?

### ✅ 적합한 경우
- 복잡한 JOIN이 많은 조회 쿼리
- 집계 연산(COUNT, SUM, AVG)이 빈번한 경우
- 실시간성이 중요하지 않은 통계 데이터
- 읽기가 쓰기보다 훨씬 많은 경우

### ❌ 부적합한 경우
- 실시간 데이터가 필요한 경우
- 쓰기가 빈번한 테이블
- 데이터 변경이 즉시 반영되어야 하는 경우

---

## Materialized View로 정렬 성능 개선하기

### 시나리오: Product에 likes_count가 없다면?

**문제 상황 (likes_count 컬럼 없음):**
```sql
-- 좋아요 수로 정렬하려면 매번 이렇게 해야 함
SELECT 
    p.id,
    p.name,
    p.price,
    COUNT(l.id) as likes_count
FROM products p
LEFT JOIN likes l ON l.product_id = p.id
GROUP BY p.id, p.name, p.price
ORDER BY COUNT(l.id) DESC
LIMIT 20;
```

**문제점:**
- 매번 `likes` 테이블과 JOIN 필요
- COUNT 집계 연산 매번 수행
- 상품 10만개 + 좋아요 100만개면 매우 느림
- 정렬 시 filesort 발생

**Materialized View 적용 시:**
```sql
-- 1. Materialized View 테이블 생성
CREATE TABLE product_with_likes_count (
    id BIGINT PRIMARY KEY,
    name VARCHAR(200),
    description TEXT,
    price BIGINT,
    stock INT,
    brand_id BIGINT,
    likes_count INT DEFAULT 0,
    created_at DATETIME(6),
    updated_at DATETIME(6),
    -- 정렬 최적화를 위한 인덱스
    INDEX idx_likes_count (likes_count DESC),
    INDEX idx_brand_likes (brand_id, likes_count DESC)
) ENGINE=InnoDB;

-- 2. 데이터 적재 (JOIN + COUNT 미리 계산)
INSERT INTO product_with_likes_count
SELECT 
    p.id,
    p.name,
    p.description,
    p.price,
    p.stock,
    p.brand_id,
    COUNT(l.id) as likes_count,
    p.created_at,
    NOW(6)
FROM products p
LEFT JOIN likes l ON l.product_id = p.id
GROUP BY p.id;

-- 3. 조회는 단순하고 빠름
SELECT * 
FROM product_with_likes_count
WHERE brand_id = 1
ORDER BY likes_count DESC
LIMIT 20;
```

**개선 효과:**
- ✅ JOIN 제거 - 단순 SELECT만 수행
- ✅ COUNT 제거 - 이미 계산된 값 사용
- ✅ 정렬 최적화 - 인덱스로 filesort 제거
- ✅ 성능 향상 - 수백ms → 수십ms

**결론:**
> **`likes_count` 컬럼이 없다면 Materialized View는 정렬 성능 개선에 효과적입니다.**
> 하지만 비정규화(`likes_count` 컬럼 추가)가 더 간단하고 실시간성도 보장됩니다.

---

## 적용 방법

### 1. Materialized View 생성 (MySQL)

```sql
-- MySQL은 Materialized View를 직접 지원하지 않음
-- 일반 테이블로 구현

CREATE TABLE brand_statistics (
    brand_id BIGINT PRIMARY KEY,
    brand_name VARCHAR(100),
    product_count INT DEFAULT 0,
    avg_price BIGINT DEFAULT 0,
    total_likes INT DEFAULT 0,
    updated_at DATETIME(6) NOT NULL,
    INDEX idx_brand_stats_likes (total_likes DESC),
    INDEX idx_brand_stats_count (product_count DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### 2. 초기 데이터 적재

```sql
INSERT INTO brand_statistics (brand_id, brand_name, product_count, avg_price, total_likes, updated_at)
SELECT 
    b.id,
    b.name,
    COUNT(p.id),
    COALESCE(AVG(p.price), 0),
    COALESCE(SUM(p.likes_count), 0),
    NOW(6)
FROM brands b
LEFT JOIN products p ON p.brand_id = b.id AND p.deleted_at IS NULL
GROUP BY b.id, b.name;
```

### 3. 갱신 전략

#### Option 1: 스케줄러로 주기적 갱신

```kotlin
@Component
class ProductMaterializedViewScheduler(
    private val jdbcTemplate: JdbcTemplate
) {
    @Scheduled(cron = "0 */5 * * * *") // 5분마다
    fun refreshProductWithLikes() {
        jdbcTemplate.execute("""
            TRUNCATE TABLE product_with_likes_count;
            
            INSERT INTO product_with_likes_count
            SELECT 
                p.id,
                p.name,
                p.description,
                p.price,
                p.stock,
                p.brand_id,
                COUNT(l.id) as likes_count,
                p.created_at,
                NOW(6)
            FROM products p
            LEFT JOIN likes l ON l.product_id = p.id
            GROUP BY p.id;
        """)
    }
}
```

**장점:** 구현 간단, 전체 데이터 정합성 보장  
**단점:** 갱신 주기만큼 지연 (5분 지연)

#### Option 2: 증분 갱신 (좋아요 이벤트 발생 시)

```kotlin
@Component
class LikeEventListener(
    private val jdbcTemplate: JdbcTemplate
) {
    @EventListener
    fun onLikeAdded(event: LikeAddedEvent) {
        jdbcTemplate.update(
            "UPDATE product_with_likes_count SET likes_count = likes_count + 1 WHERE id = ?",
            event.productId
        )
    }
    
    @EventListener
    fun onLikeCanceled(event: LikeCanceledEvent) {
        jdbcTemplate.update(
            "UPDATE product_with_likes_count SET likes_count = likes_count - 1 WHERE id = ?",
            event.productId
        )
    }
}
```

**장점:** 실시간 반영  
**단점:** 이벤트 누락 시 정합성 깨짐, 동시성 이슈

### 4. 조회 쿼리 (빠름!)

```kotlin
@Repository
interface ProductWithLikesRepository : JpaRepository<ProductWithLikesCount, Long> {
    
    // 브랜드별 좋아요 순 정렬 - 매우 빠름
    @Query("""
        SELECT p FROM ProductWithLikesCount p 
        WHERE p.brandId = :brandId 
        ORDER BY p.likesCount DESC
    """)
    fun findByBrandIdOrderByLikes(brandId: Long, pageable: Pageable): Page<ProductWithLikesCount>
    
    // 전체 좋아요 순 정렬 - 매우 빠름
    @Query("SELECT p FROM ProductWithLikesCount p ORDER BY p.likesCount DESC")
    fun findAllOrderByLikes(pageable: Pageable): Page<ProductWithLikesCount>
}
```

**성능 비교:**
```
AS-IS (likes_count 없음):
- JOIN likes 테이블 (100만 건)
- COUNT 집계
- filesort 정렬
→ 300-500ms

TO-BE (Materialized View):
- 단순 SELECT
- 인덱스 활용 정렬
→ 10-30ms
```

---

## 비정규화 vs Materialized View (좋아요 수 정렬)

### 비정규화 방식 (`likes_count` 컬럼 추가) ⭐ 권장

```kotlin
@Entity
class Product(
    @Column(name = "likes_count")
    var likesCount: Int = 0  // Product 테이블에 직접 저장
)

// 좋아요 등록 시 증가
product.increaseLikesCount()

// 조회 시 단순 정렬
SELECT * FROM products ORDER BY likes_count DESC
```

**장점:**
- ✅ 실시간 반영 (좋아요 즉시 증가/감소)
- ✅ 구현 간단 (엔티티에 컬럼 추가만)
- ✅ 추가 테이블 불필요
- ✅ 트랜잭션 안전 (Product 수정과 함께 커밋)

**단점:**
- ❌ 동시성 제어 필요 (비관적 락 사용)

---

### Materialized View 방식 (별도 테이블)

```sql
CREATE TABLE product_with_likes_count (
    id BIGINT PRIMARY KEY,
    likes_count INT,
    ...
);

-- 스케줄러로 주기적 갱신
INSERT INTO product_with_likes_count
SELECT p.id, COUNT(l.id), ...
FROM products p
LEFT JOIN likes l ON l.product_id = p.id
GROUP BY p.id;
```

**장점:**
- ✅ 조회 성능 좋음 (JOIN 제거)
- ✅ 원본 테이블 독립적

**단점:**
- ❌ 실시간성 부족 (5분 지연)
- ❌ 추가 저장 공간 필요
- ❌ 갱신 로직 복잡 (스케줄러 or 이벤트)
- ❌ 정합성 관리 어려움

---

### 결론: 좋아요 수 정렬은 비정규화가 적합

| 항목 | 비정규화 | Materialized View |
|------|---------|------------------|
| **실시간성** | ⭐⭐⭐⭐⭐ 즉시 반영 | ⭐⭐ 5분 지연 |
| **구현 난이도** | ⭐⭐⭐⭐⭐ 매우 쉬움 | ⭐⭐ 복잡함 |
| **정합성** | ⭐⭐⭐⭐⭐ 트랜잭션 보장 | ⭐⭐⭐ 갱신 주기에 의존 |
| **조회 성능** | ⭐⭐⭐⭐ 빠름 | ⭐⭐⭐⭐⭐ 매우 빠름 |
| **저장 공간** | ⭐⭐⭐⭐⭐ 컬럼만 추가 | ⭐⭐⭐ 테이블 전체 복제 |

**과제 요구사항:**
> "비정규화(like_count) 혹은 MaterializedView 중 하나를 선택"

**선택 기준:**
- 실시간 좋아요 반영 필요 → **비정규화** ⭐
- 5-10분 지연 허용 가능 → Materialized View
- 좋아요 외 복잡한 집계 필요 → Materialized View

**현재 프로젝트:**
- ✅ 좋아요는 실시간 반영 필요
- ✅ 비정규화가 더 간단하고 효과적
- ✅ `likes_count` 컬럼 + 비관적 락으로 해결

---

## 현재 프로젝트에 적용한다면?

### 적용 가능한 케이스

**1. 브랜드별 인기 상품 TOP 10**
```sql
CREATE TABLE brand_top_products (
    brand_id BIGINT,
    product_id BIGINT,
    product_name VARCHAR(200),
    likes_count INT,
    rank_order INT,
    PRIMARY KEY (brand_id, rank_order)
);
```

**2. 일별 상품 판매 통계**
```sql
CREATE TABLE daily_product_sales (
    product_id BIGINT,
    sale_date DATE,
    order_count INT,
    total_amount BIGINT,
    PRIMARY KEY (product_id, sale_date)
);
```

### 적용하지 않는 이유

**현재 프로젝트는:**
- ✅ 인덱스 최적화만으로 충분히 빠름 (15ms)
- ✅ Redis 캐시로 추가 성능 개선 (5ms)
- ✅ 실시간 데이터 필요 (좋아요 수, 재고)

**Materialized View는:**
- ⚠️ 과도한 최적화 (Over-engineering)
- ⚠️ 복잡도만 증가
- ⚠️ 실시간성 저하

---

## 결론

### Materialized View는 언제 사용하나?

**✅ 사용하면 좋은 경우:**
- `likes_count` 같은 비정규화 컬럼이 없을 때
- 복잡한 JOIN + 집계 쿼리가 많을 때
- 5-10분 지연이 허용되는 통계/리포트
- 원본 테이블을 수정할 수 없을 때

**❌ 사용하지 않는 게 좋은 경우:**
- 실시간 데이터가 필요할 때 (좋아요, 재고 등)
- 비정규화로 간단히 해결 가능할 때
- 인덱스 + 캐시로 충분히 빠를 때

---

### 좋아요 수 정렬 성능 개선 방법 비교

**현재 프로젝트 선택: 비정규화 (`likes_count` 컬럼)**

| 방법 | 조회 성능 | 실시간성 | 구현 난이도 | 선택 |
|------|----------|----------|------------|------|
| 비정규화 | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ✅ 선택 |
| Materialized View | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐ | 대안 |
| 매번 COUNT | ⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ❌ 느림 |

**적용 우선순위:**
```
1. 비정규화 (likes_count 컬럼) - 간단하고 실시간
2. 인덱스 최적화 - 정렬 성능 향상
3. Redis 캐시 - 추가 성능 개선
4. Materialized View - 복잡한 집계가 많을 때만
```

---

### 정리

> **`Product`에 `likes_count`가 없다면?**
> → Materialized View로 정렬 성능을 개선할 수 있습니다!
> 
> **하지만 실무에서는?**
> → 비정규화가 더 간단하고 실시간성도 보장됩니다.

**핵심:**
- Materialized View = JOIN + COUNT를 미리 계산해서 저장
- 조회는 빠르지만, 갱신 주기만큼 지연 발생
- 좋아요처럼 실시간 반영이 필요하면 비정규화 사용

---

_참고: PostgreSQL은 Materialized View를 네이티브로 지원하지만, MySQL은 일반 테이블로 구현해야 합니다._

