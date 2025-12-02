# 쿼리 최적화 이슈 및 해결 방법

실제 애플리케이션 실행 시 발견된 쿼리 문제와 해결 방법입니다.

## 🔍 발견된 문제

### 실제 발생하는 쿼리 (Hibernate 로그)

```sql
-- 메인 쿼리
Hibernate: select p1_0.id,p1_0.brand_id,...
FROM products p1_0
LEFT JOIN brands b1_0 ON b1_0.id=p1_0.brand_id
WHERE b1_0.id=?
ORDER BY p1_0.likes_count desc
LIMIT ?

-- Brand 조회 (N+1 가능성)
Hibernate: select b1_0.id,...
FROM brands b1_0
WHERE b1_0.id=?

-- COUNT 쿼리 (페이징용)
Hibernate: select count(p1_0.id)
FROM products p1_0
LEFT JOIN brands b1_0 ON b1_0.id=p1_0.brand_id
WHERE b1_0.id=?
```

### 문제점

#### 1. 불필요한 LEFT JOIN ❌
```kotlin
// ProductJpaRepository.kt
fun findByBrandId(brandId: Long, pageable: Pageable): Page<Product>
```

Spring Data JPA가 `findByBrandId`를 `findByBrand_Id`로 해석:
- `brand` → Product의 Brand 연관관계
- `id` → Brand의 id 필드
- 결과: `WHERE brand.id = ?` → LEFT JOIN brands 발생

**왜 문제인가?**
- `brand_id` 컬럼만으로 필터링 가능
- 불필요한 조인으로 인덱스 효율 저하
- 쿼리 복잡도 증가

#### 2. 매번 발생하는 COUNT 쿼리 ⚠️
페이징 처리를 위해 `totalElements`를 계산하는 COUNT 쿼리가 매번 실행:
- 10만건 전체 COUNT → 비용 높음
- 인덱스가 있어도 COUNT는 상대적으로 느림

#### 3. Soft Delete 필터링 누락 ⚠️
현재 쿼리에 `deleted_at IS NULL` 조건이 없음:
- 삭제된 데이터도 조회될 수 있음
- 인덱스 설계 시 고려 필요

---

## ✅ 해결 방법

### 해결 1: 쿼리 명시적으로 작성

#### Option A: @Query 어노테이션 사용 (추천)

```kotlin
interface ProductJpaRepository : JpaRepository<Product, Long> {

    @Query("""
        SELECT p FROM Product p
        WHERE p.brand.id = :brandId
          AND p.deletedAt IS NULL
        ORDER BY p.likesCount DESC
    """)
    fun findByBrandIdOrderByLikesCountDesc(
        brandId: Long,
        pageable: Pageable
    ): Page<Product>

    @Query("""
        SELECT p FROM Product p
        WHERE p.deletedAt IS NULL
        ORDER BY p.likesCount DESC
    """)
    fun findAllOrderByLikesCountDesc(pageable: Pageable): Page<Product>
}
```

**장점:**
- 쿼리를 명확하게 제어
- deleted_at 필터링 명시
- JPQL이라 데이터베이스 독립적

**단점:**
- 여전히 Spring Data가 LEFT JOIN 생성 가능

#### Option B: Native Query 사용 (최고 성능)

```kotlin
interface ProductJpaRepository : JpaRepository<Product, Long> {

    @Query(
        value = """
            SELECT * FROM products
            WHERE brand_id = :brandId
              AND deleted_at IS NULL
            ORDER BY likes_count DESC
            LIMIT :limit OFFSET :offset
        """,
        nativeQuery = true
    )
    fun findByBrandIdNative(
        brandId: Long,
        limit: Int,
        offset: Int
    ): List<Product>

    @Query(
        value = """
            SELECT COUNT(*) FROM products
            WHERE brand_id = :brandId
              AND deleted_at IS NULL
        """,
        nativeQuery = true
    )
    fun countByBrandIdNative(brandId: Long): Long
}
```

**장점:**
- LEFT JOIN 완전히 제거
- 정확한 쿼리 제어
- 인덱스 효율 극대화

**단점:**
- 데이터베이스 종속적
- 페이징 처리 수동 구현 필요

#### Option C: QueryDSL 사용 (유연성)

```kotlin
class ProductRepositoryImpl(
    private val queryFactory: JPAQueryFactory
) : ProductRepositoryCustom {

    override fun findByBrandIdWithSort(
        brandId: Long,
        sort: ProductSortType,
        pageable: Pageable
    ): Page<Product> {
        val query = queryFactory
            .selectFrom(product)
            .where(
                product.brand.id.eq(brandId),
                product.deletedAt.isNull
            )
            .orderBy(getOrderSpecifier(sort))
            .offset(pageable.offset)
            .limit(pageable.pageSize.toLong())

        val products = query.fetch()
        val total = queryFactory
            .select(product.count())
            .from(product)
            .where(
                product.brand.id.eq(brandId),
                product.deletedAt.isNull
            )
            .fetchOne() ?: 0L

        return PageImpl(products, pageable, total)
    }
}
```

**장점:**
- 타입 안정성
- 동적 쿼리 작성 용이
- LEFT JOIN 제어 가능

**단점:**
- 설정 필요
- 러닝 커브

---

### 해결 2: COUNT 쿼리 최적화

#### Option A: 캐시 적용
```kotlin
@Cacheable("product:count:brand")
fun countByBrandId(brandId: Long): Long {
    return productRepository.count(...)
}
```

**장점:**
- 간단한 구현
- 대부분의 경우 충분

**단점:**
- 정합성 이슈 (TTL 내 변경 시)

#### Option B: 커서 기반 페이지네이션
```kotlin
// 마지막 ID 기준으로 조회 (totalElements 불필요)
fun findAfter(lastId: Long, limit: Int): List<Product> {
    return queryFactory
        .selectFrom(product)
        .where(product.id.gt(lastId))
        .orderBy(product.likesCount.desc())
        .limit(limit.toLong())
        .fetch()
}
```

**장점:**
- COUNT 쿼리 불필요
- 깊은 페이지도 빠름

**단점:**
- 특정 페이지 이동 불가
- UI 변경 필요 (무한 스크롤 등)

---

### 해결 3: 인덱스 설계

#### 현재 상태
```sql
-- 현재 인덱스
CREATE INDEX idx_products_brand_id ON products(brand_id);
CREATE INDEX idx_products_likes_count ON products(likes_count);
```

#### 권장 인덱스

```sql
-- 1. 브랜드 + 좋아요 + Soft Delete 복합 인덱스
CREATE INDEX idx_products_brand_likes_active
ON products(brand_id, deleted_at, likes_count DESC);

-- 2. 전체 좋아요 순 조회용
CREATE INDEX idx_products_active_likes
ON products(deleted_at, likes_count DESC);

-- 3. 커버링 인덱스 (성능 극대화)
CREATE INDEX idx_products_covering
ON products(brand_id, deleted_at, likes_count DESC, id, name, price, stock);
```

**인덱스 선택 기준:**
- 카디널리티 높은 컬럼 먼저 (brand_id > deleted_at)
- 정렬 컬럼은 마지막에 (likes_count DESC)
- 커버링 인덱스는 조회 컬럼이 확정적일 때만

---

## 📊 성능 비교 (예상)

### AS-IS (LEFT JOIN 사용)
```
EXPLAIN 결과:
- type: ALL
- key: NULL
- rows: 99485
- Extra: Using where; Using filesort; Using join buffer
응답 시간: ~400ms
```

### TO-BE 1 (JOIN 제거, 단일 인덱스)
```
EXPLAIN 결과:
- type: ref
- key: idx_products_brand_id
- rows: ~1000
- Extra: Using where; Using filesort
응답 시간: ~80ms
```

### TO-BE 2 (JOIN 제거, 복합 인덱스)
```
EXPLAIN 결과:
- type: range
- key: idx_products_brand_likes_active
- rows: ~1000
- Extra: Using where; Using index
응답 시간: ~15ms
```

---

## 🎯 권장 구현 순서

### 1단계: 즉시 적용 (코드 수정 최소)
1. `@Query` 어노테이션으로 명시적 쿼리 작성
2. `deleted_at IS NULL` 조건 추가
3. 복합 인덱스 추가

### 2단계: 점진적 개선
1. Native Query로 변경 (성능 중요 API만)
2. COUNT 쿼리 캐싱
3. 페이지네이션 전략 재검토

### 3단계: 장기 개선
1. QueryDSL 도입
2. 커서 기반 페이지네이션
3. 읽기 전용 Replica 분리

---

## 💡 과제 수행 시 고려사항

### EXPLAIN 분석 시
- **AS-IS**: 현재 LEFT JOIN이 발생하는 쿼리로 분석
- **TO-BE**: 위의 해결 방법 적용 후 재분석
- 둘 다 기록해서 비교하면 좋은 자료

### 블로그 작성 시
- "왜 LEFT JOIN이 발생했는가?" → Spring Data JPA 메서드 네이밍 규칙
- "어떻게 해결했는가?" → @Query 명시 + 복합 인덱스
- "성능이 얼마나 개선되었는가?" → EXPLAIN + 응답 시간 비교

---

## 🔗 참고 파일
- 실제 쿼리: `.codeguide/actual-queries.sql`
- 분석용 쿼리: `docker/query-analysis.sql`
- API 테스트: `.http/week5-assignment.http`
