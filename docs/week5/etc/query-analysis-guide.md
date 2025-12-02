# Product 쿼리 분석 가이드

10만개 상품 데이터로 쿼리 성능을 분석하고 최적화하는 방법입니다.

## 1. 환경 준비

### 1.1 Docker MySQL 시작 (데이터 자동 생성)

```bash
cd docker
docker-compose -f infra-compose.yml up -d mysql

# 로그 확인 (데이터 생성 완료 확인)
docker-compose -f infra-compose.yml logs -f mysql
```

데이터 생성 완료 메시지:
- `✅ 브랜드 100개 생성 완료`
- `✅ 상품 100000개 생성 완료`

### 1.2 애플리케이션 실행

```bash
./gradlew :apps:commerce-api:bootRun
```

## 2. 쿼리 분석 방법

### 방법 1: 테스트 코드로 분석

#### 2.1 테스트 실행

IntelliJ에서 `ProductQueryAnalysisTest` 실행:
- 위치: `apps/commerce-api/src/test/kotlin/com/loopers/domain/product/ProductQueryAnalysisTest.kt`
- 개별 테스트 실행 가능

#### 2.2 SQL 로그 확인

테스트 실행 시 콘솔에 출력되는 SQL을 확인:

```sql
Hibernate: select ... from products p1_0 where p1_0.brand_id=? and p1_0.deleted_at is null order by p1_0.likes_count desc limit ?, ?
```

#### 2.3 실행 시간 확인

테스트 출력:
```
✅ 조회 완료
- 총 개수: 1000
- 페이지 크기: 20
- 실행 시간: 45ms
```

### 방법 2: MySQL에서 직접 분석

#### 2.1 MySQL 접속

```bash
docker exec -it $(docker ps -qf "name=mysql") mysql -uapplication -papplication loopers
```

#### 2.2 분석 스크립트 실행

준비된 스크립트 파일: `docker/query-analysis.sql`

```sql
-- 1. EXPLAIN으로 실행 계획 확인
EXPLAIN
SELECT p.*
FROM products p
WHERE p.brand_id = 1
  AND p.deleted_at IS NULL
ORDER BY p.likes_count DESC
LIMIT 20;

-- 2. 실제 실행 시간 측정
SET profiling = 1;

SELECT p.*
FROM products p
WHERE p.brand_id = 1
  AND p.deleted_at IS NULL
ORDER BY p.likes_count DESC
LIMIT 20;

SHOW PROFILES;
SET profiling = 0;
```

#### 2.3 EXPLAIN 결과 해석

중요한 컬럼:
- **type**: 조인 타입 (ALL, index, range, ref 등)
  - `ALL`: 전체 테이블 스캔 (느림) ❌
  - `index`: 인덱스 풀 스캔 (보통)
  - `range`: 인덱스 범위 스캔 (빠름) ✅
  - `ref`: 인덱스 참조 (빠름) ✅

- **key**: 사용된 인덱스
  - `NULL`: 인덱스 미사용 ❌
  - 인덱스명: 인덱스 사용 ✅

- **rows**: 예상 처리 행 수 (적을수록 좋음)

- **Extra**: 추가 정보
  - `Using filesort`: 정렬을 위한 추가 작업 필요 (느림) ⚠️
  - `Using index`: 커버링 인덱스 사용 (빠름) ✅
  - `Using where`: WHERE 조건 적용

## 3. 테스트 시나리오

### 시나리오 1: 브랜드 필터 + 좋아요 순 정렬

```kotlin
productRepository.findAll(
    brandId = 1L,
    sort = ProductSortType.LIKES_DESC,
    pageable = PageRequest.of(0, 20)
)
```

**분석 포인트:**
- `brand_id` 인덱스 사용 여부
- `likes_count` 정렬 성능
- Using filesort 발생 여부

### 시나리오 2: 전체 상품 + 좋아요 순 정렬

```kotlin
productRepository.findAll(
    brandId = null,
    sort = ProductSortType.LIKES_DESC,
    pageable = PageRequest.of(0, 20)
)
```

**분석 포인트:**
- 전체 스캔 발생 여부
- `likes_count` 인덱스 사용 여부
- 10만 건 중 상위 20건 조회 성능

### 시나리오 3: 최신순 정렬

```kotlin
productRepository.findAll(
    brandId = null,
    sort = ProductSortType.LATEST,
    pageable = PageRequest.of(0, 20)
)
```

**분석 포인트:**
- `created_at` 인덱스 필요 여부
- 성능 비교

## 4. 현재 인덱스 상태 확인

```sql
SHOW INDEXES FROM products;
```

**현재 인덱스:**
- PRIMARY KEY (`id`)
- `idx_products_brand_id` (`brand_id`)
- `idx_products_likes_count` (`likes_count`)

## 5. 최적화 방향

### 5.1 복합 인덱스 고려

브랜드 필터 + 좋아요 정렬이 자주 사용되면:
```sql
CREATE INDEX idx_products_brand_likes ON products(brand_id, likes_count DESC);
```

### 5.2 커버링 인덱스 고려

조회하는 컬럼만 인덱스에 포함:
```sql
CREATE INDEX idx_products_covering ON products(brand_id, likes_count, name, price, stock, created_at);
```

### 5.3 deleted_at 필터링

Soft delete를 사용하므로 복합 인덱스에 포함:
```sql
CREATE INDEX idx_products_active_brand_likes ON products(deleted_at, brand_id, likes_count);
```

## 6. 성능 목표

- **응답 시간**: 100ms 이하
- **인덱스 사용**: EXPLAIN에서 key가 NULL이 아님
- **처리 행 수**: EXPLAIN의 rows가 가능한 적게
- **Extra**: Using filesort 최소화

## 7. 비교 분석 예시

### AS-IS (인덱스 최적화 전)
```
type: ALL
key: NULL
rows: 100000
Extra: Using where; Using filesort
실행 시간: 350ms
```

### TO-BE (인덱스 최적화 후)
```
type: range
key: idx_products_brand_likes
rows: 1000
Extra: Using where; Using index
실행 시간: 15ms
```

## 8. 트러블슈팅

### 문제: SQL이 로그에 안 보임
**해결**: `application.yml`에서 `show-sql: true` 확인

### 문제: 데이터가 없음
**해결**: Docker MySQL 컨테이너 재시작 후 초기화 스크립트 실행 확인

### 문제: 테스트가 너무 느림
**해결**: 데이터 양이 많아서 정상. 첫 실행은 캐시 워밍업 시간 포함

## 9. 다음 단계

1. ✅ 현재 쿼리 EXPLAIN 분석
2. ⬜ 인덱스 추가/변경
3. ⬜ EXPLAIN 재분석 (개선 확인)
4. ⬜ 실행 시간 비교
5. ⬜ 문서화 및 정리
