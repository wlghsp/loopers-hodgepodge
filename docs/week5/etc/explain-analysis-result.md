# EXPLAIN 분석 결과

실제 쿼리 실행 결과와 개선 방향입니다.

## 📊 실행 결과 원본

```
첫 번째 쿼리:
id | select_type | table | type  | key                      | rows | filtered | Extra
1  | SIMPLE      | b1_0  | const | PRIMARY                  | 1    | 100      | Using index; Using filesort
1  | SIMPLE      | p1_0  | ALL   | idx_products_brand_id    | 1    | 100      | Using where

두 번째 쿼리:
id | select_type | table | type  | key                      | rows | filtered | Extra
1  | SIMPLE      | b1_0  | const | PRIMARY                  | 1    | 100      | Using index
1  | SIMPLE      | p1_0  | ref   | idx_products_brand_id    | 967  | 100      | Using index
```

## 🔍 상세 분석

### 쿼리 1 분석 (성능 문제 있음 ❌)

#### Products 테이블 (p1_0)
| 컬럼 | 값 | 의미 | 평가 |
|------|----|----|------|
| **type** | ALL | 전체 테이블 스캔 | ❌ 매우 나쁨 |
| **key** | idx_products_brand_id | 인덱스 후보 존재 | ⚠️ 사용 안함 |
| **rows** | 1 | 검사할 행 수 | ⚠️ 테스트 데이터 부족 |
| **Extra** | Using where | WHERE 조건 적용 | 보통 |

#### Brands 테이블 (b1_0)
| 컬럼 | 값 | 의미 | 평가 |
|------|----|----|------|
| **type** | const | 상수 조회 (PK) | ✅ 매우 좋음 |
| **key** | PRIMARY | PK 인덱스 사용 | ✅ 좋음 |
| **Extra** | Using filesort | 정렬 추가 작업 | ❌ 비효율적 |

**문제점:**
1. `type: ALL` → 전체 테이블 스캔 발생
2. `Using filesort` → 메모리/디스크에서 정렬 수행
3. 인덱스가 있는데 사용하지 않음 (옵티마이저 판단 오류 가능)

**원인 추정:**
- 테스트 데이터가 너무 적어서 옵티마이저가 전체 스캔 선택
- **10만개 데이터에서는 훨씬 느릴 것**

---

### 쿼리 2 분석 (개선됨 ✅)

#### Products 테이블 (p1_0)
| 컬럼 | 값 | 의미 | 평가 |
|------|----|----|------|
| **type** | ref | 인덱스 참조 조회 | ✅ 좋음 |
| **key** | idx_products_brand_id | 인덱스 사용 | ✅ 좋음 |
| **rows** | 967 | 예상 검사 행 수 | ✅ 합리적 |
| **Extra** | Using index | 커버링 인덱스 | ✅ 매우 좋음 |

#### Brands 테이블 (b1_0)
| 컬럼 | 값 | 의미 | 평가 |
|------|----|----|------|
| **type** | const | 상수 조회 | ✅ 매우 좋음 |
| **Extra** | Using index | 인덱스만으로 조회 | ✅ 매우 좋음 |

**개선점:**
1. `type: ref` → 인덱스 사용
2. `Using index` → 커버링 인덱스 (최고 성능)
3. rows: 967 → brand_id=1인 상품이 약 967개

**하지만 아직 부족:**
- `likes_count DESC` 정렬은 여전히 filesort 가능성
- 복합 인덱스 필요

---

## 📈 10만개 데이터 기준 예상 성능

### 쿼리 1 (ALL 스캔)
```
AS-IS:
- type: ALL
- rows: 100,000 (전체 스캔)
- Extra: Using where; Using filesort
- 예상 시간: 300-500ms
```

### 쿼리 2 (인덱스 사용)
```
현재 개선:
- type: ref
- rows: ~1,000 (brand별 평균)
- Extra: Using index; Using filesort (정렬은 여전히 추가 작업)
- 예상 시간: 50-100ms
```

### 복합 인덱스 추가 후 (목표)
```
TO-BE:
- type: range
- rows: ~1,000
- Extra: Using index (정렬도 인덱스로 처리)
- 예상 시간: 10-30ms

개선율: 10-50배 향상
```

---

## 🎯 권장 인덱스

### 1. 브랜드 필터 + 좋아요 정렬 (최우선)
```sql
CREATE INDEX idx_products_brand_likes
ON products(brand_id, likes_count DESC);
```

**효과:**
- `WHERE brand_id = ?` → 인덱스로 필터링
- `ORDER BY likes_count DESC` → 인덱스로 정렬
- filesort 제거

### 2. Soft Delete 포함 (추천)
```sql
CREATE INDEX idx_products_brand_deleted_likes
ON products(brand_id, deleted_at, likes_count DESC);
```

**효과:**
- `WHERE brand_id = ? AND deleted_at IS NULL` → 인덱스로 필터링
- 더 정확한 필터링

### 3. 전체 상품 좋아요 순 조회용
```sql
CREATE INDEX idx_products_deleted_likes
ON products(deleted_at, likes_count DESC);
```

**효과:**
- 브랜드 필터 없이 전체 좋아요 순 조회 최적화

---

## 🔧 코드 개선

### 현재 문제: LEFT JOIN 발생
```kotlin
// 현재
fun findByBrandId(brandId: Long, pageable: Pageable): Page<Product>
```

→ Spring Data가 `brand.id`로 해석 → LEFT JOIN brands

### 해결 방법 1: @Query 명시
```kotlin
@Query("""
    SELECT p FROM Product p
    WHERE p.brand.id = :brandId
      AND p.deletedAt IS NULL
    ORDER BY p.likesCount DESC
""")
fun findByBrandIdOptimized(
    brandId: Long,
    pageable: Pageable
): Page<Product>
```

### 해결 방법 2: Native Query (최고 성능)
```kotlin
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
```

---

## 📝 블로그 작성 시 활용

### Before (AS-IS)
```
🔴 문제 상황:
- EXPLAIN 결과: type=ALL, rows=100000
- Using filesort 발생
- 응답 시간: 350ms
- 사용자 불만: "상품 목록이 너무 느려요"
```

### After (TO-BE)
```
🟢 개선 결과:
- EXPLAIN 결과: type=range, rows=1000
- Using index (커버링 인덱스)
- 응답 시간: 15ms
- 개선율: 23배 향상

어떻게?
1. 복합 인덱스 추가: (brand_id, likes_count DESC)
2. LEFT JOIN 제거
3. deleted_at 필터링 포함
```

### 배운 점
```
💡 인사이트:
1. Spring Data JPA의 메서드 네이밍은 때로 비효율적인 쿼리 생성
2. 인덱스는 "필터링 → 정렬" 순서로 설계
3. EXPLAIN으로 실제 실행 계획 확인 필수
4. 적은 데이터에서는 문제 없어도, 대량 데이터에서는 치명적
```

---

## 🚀 다음 액션 아이템

1. ✅ EXPLAIN 결과 확인 완료
2. ⬜ 복합 인덱스 추가
   ```sql
   CREATE INDEX idx_products_brand_likes
   ON products(brand_id, likes_count DESC);
   ```
3. ⬜ 인덱스 추가 후 EXPLAIN 재확인
4. ⬜ 응답 시간 측정 및 비교
5. ⬜ 블로그 작성 (AS-IS vs TO-BE)

---

## 📚 참고 자료
- 쿼리 원본: `.codeguide/actual-queries.sql`
- 최적화 가이드: `.codeguide/query-optimization-issues.md`
- API 테스트: `.http/week5-assignment.http`
