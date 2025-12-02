# 5주차 과제: 조회 성능 최적화 완벽 가이드

> **이 문서 하나로 과제 완료하기**
>
> 환경 준비 → 쿼리 실행 → 측정 → 인덱스 적용 → 재측정 → 결과 정리

---

## 📋 목차

1. [환경 준비](#1-환경-준비)
2. [AS-IS 측정 (인덱스 없음)](#2-as-is-측정-인덱스-없음)
3. [인덱스 적용](#3-인덱스-적용)
4. [TO-BE 측정 (인덱스 적용)](#4-to-be-측정-인덱스-적용)
5. [결과 정리 및 블로그 작성](#5-결과-정리-및-블로그-작성)

---

## 1. 환경 준비

### 1-1. Docker MySQL 시작 (10만개 데이터 자동 생성)

```bash
cd docker
docker-compose -f infra-compose.yml up -d mysql

# 데이터 생성 확인 (1-2분 소요)
docker-compose -f infra-compose.yml logs -f mysql
# ✅ 브랜드 100개 생성 완료
# ✅ 상품 100000개 생성 완료
```

### 1-2. 애플리케이션 실행

```bash
./gradlew :apps:commerce-api:bootRun
```

### 1-3. MySQL Workbench 연결

```
Host: 127.0.0.1
Port: 3306
Username: application
Password: application
Schema: loopers
```

### 1-4. Grafana 설정 (선택사항)

성능 모니터링을 원하면:
```bash
cd docker
docker-compose -f monitoring-compose.yml up -d
# Grafana: http://localhost:3000
```

**권장 측정 도구:**
- ✅ **MySQL Workbench** - EXPLAIN, 쿼리 실행 시간
- ✅ **IntelliJ HTTP Client** - API 응답 시간
- ⬜ Grafana - 실시간 모니터링 (선택)
- ⬜ JMeter/k6 - 부하 테스트 (선택)

---

## 2. AS-IS 측정 (인덱스 없음)

### 2-1. 현재 인덱스 상태 확인

**MySQL Workbench에서 실행:**

```sql
USE loopers;

-- 현재 인덱스 확인
SHOW INDEXES FROM products;
```

**📸 캡처 포인트 1: 현재 인덱스 목록**
- PRIMARY (id)
- idx_products_brand_id (brand_id)
- idx_products_likes_count (likes_count)

---

### 2-2. API 실행 및 SQL 확인

**IntelliJ에서 `.http/week5-assignment.http` 실행:**

```http
### 브랜드 필터 + 좋아요 순 정렬
GET http://localhost:8080/api/v1/products?brandId=1&sort=LIKES_DESC&page=0&size=20
```

**콘솔에서 Hibernate SQL 복사:**
```sql
Hibernate: select p1_0.id,... from products p1_0 left join brands b1_0 on b1_0.id=p1_0.brand_id where b1_0.id=? order by p1_0.likes_count desc limit ?
```

**📸 캡처 포인트 2: API 응답 시간**
- IntelliJ 하단의 `Duration: XXX ms` 기록

---

### 2-3. EXPLAIN 실행 (AS-IS)

**MySQL Workbench에서 실행:**

```sql
-- ================================================
-- 쿼리 1: 브랜드 필터 + 좋아요 순 정렬
-- ================================================
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
```

**📸 캡처 포인트 3: EXPLAIN 결과 (AS-IS)**

중요 컬럼:
- `type`: ALL이면 전체 스캔 ❌
- `key`: NULL이면 인덱스 미사용 ❌
- `rows`: 검사할 행 수 (많을수록 느림)
- `Extra`: Using filesort면 정렬 추가 작업 ⚠️

**예상 결과:**
```
type: ALL 또는 ref
key: NULL 또는 idx_products_brand_id
rows: 약 1000-10000
Extra: Using where; Using filesort
```

---

### 2-4. 실행 시간 측정 (AS-IS)

**MySQL Workbench에서 실행:**

```sql
-- 프로파일링 시작
SET profiling = 1;

-- 쿼리 실행 (3번 반복하여 평균 측정)
SELECT p1_0.*
FROM products p1_0
LEFT JOIN brands b1_0 ON b1_0.id = p1_0.brand_id
WHERE b1_0.id = 1
ORDER BY p1_0.likes_count DESC
LIMIT 20;

-- 실행 시간 확인
SHOW PROFILES;

SET profiling = 0;
```

**📸 캡처 포인트 4: 실행 시간 (AS-IS)**
- Duration 컬럼 값 기록 (예: 0.05초 = 50ms)

---

### 2-5. 전체 상품 좋아요 순 조회 (AS-IS)

**MySQL Workbench에서 실행:**

```sql
-- ================================================
-- 쿼리 2: 전체 상품 + 좋아요 순 정렬
-- ================================================
EXPLAIN
SELECT p1_0.*
FROM products p1_0
WHERE p1_0.deleted_at IS NULL
ORDER BY p1_0.likes_count DESC
LIMIT 20;
```

**📸 캡처 포인트 5: EXPLAIN 결과 (전체 좋아요순 AS-IS)**

---

## 3. 인덱스 적용

### 3-1. 권장 인덱스 분석

**쿼리 패턴 분석:**
1. `WHERE brand_id = ? AND deleted_at IS NULL`
2. `ORDER BY likes_count DESC`

**인덱스 설계 원칙:**
- 필터링 컬럼 먼저: `brand_id`, `deleted_at`
- 정렬 컬럼 마지막: `likes_count DESC`

---

### 3-2. 인덱스 추가

**방법 1: JPA Entity에 추가 (추천)**

```kotlin
// Product.kt
@Entity
@Table(
    name = "products",
    indexes = [
        Index(name = "idx_products_brand_likes", columnList = "brand_id, likes_count DESC"),
        Index(name = "idx_products_deleted_likes", columnList = "deleted_at, likes_count DESC"),
    ]
)
class Product(...)
```

**애플리케이션 재시작 후 인덱스 자동 생성**

---

**방법 2: MySQL에서 직접 추가 (빠른 테스트)**

```sql
-- 브랜드 필터 + 좋아요 순 최적화
CREATE INDEX idx_products_brand_likes
ON products(brand_id, likes_count DESC);

-- 전체 좋아요 순 최적화
CREATE INDEX idx_products_deleted_likes
ON products(deleted_at, likes_count DESC);

-- 인덱스 생성 확인
SHOW INDEXES FROM products;
```

**📸 캡처 포인트 6: 인덱스 추가 후 목록**

---

## 4. TO-BE 측정 (인덱스 적용)

### 4-1. EXPLAIN 재실행 (TO-BE)

**MySQL Workbench에서 실행:**

```sql
-- ================================================
-- 쿼리 1: 브랜드 필터 + 좋아요 순 (인덱스 적용 후)
-- ================================================
EXPLAIN
SELECT p1_0.*
FROM products p1_0
WHERE p1_0.brand_id = 1
  AND p1_0.deleted_at IS NULL
ORDER BY p1_0.likes_count DESC
LIMIT 20;
```

**📸 캡처 포인트 7: EXPLAIN 결과 (TO-BE)**

**기대 결과:**
```
type: range (인덱스 범위 스캔) ✅
key: idx_products_brand_likes ✅
rows: 약 1000 (필터링 효율적) ✅
Extra: Using index condition 또는 Using where ✅
```

**개선 확인 포인트:**
- ✅ type이 `ALL` → `range` 또는 `ref`로 변경
- ✅ key에 새로 만든 인덱스 이름 표시
- ✅ Extra에서 `Using filesort` 제거

---

### 4-2. 실행 시간 재측정 (TO-BE)

```sql
SET profiling = 1;

-- 인덱스 적용된 쿼리 (3번 반복)
SELECT p1_0.*
FROM products p1_0
WHERE p1_0.brand_id = 1
  AND p1_0.deleted_at IS NULL
ORDER BY p1_0.likes_count DESC
LIMIT 20;

SHOW PROFILES;
SET profiling = 0;
```

**📸 캡처 포인트 8: 실행 시간 (TO-BE)**

---

### 4-3. 전체 상품 좋아요 순 재측정 (TO-BE)

```sql
EXPLAIN
SELECT p1_0.*
FROM products p1_0
WHERE p1_0.deleted_at IS NULL
ORDER BY p1_0.likes_count DESC
LIMIT 20;
```

**📸 캡처 포인트 9: EXPLAIN 결과 (전체 좋아요순 TO-BE)**

---

### 4-4. API 응답 시간 재측정

**IntelliJ에서 같은 API 재실행:**

```http
GET http://localhost:8080/api/v1/products?brandId=1&sort=LIKES_DESC&page=0&size=20
```

**📸 캡처 포인트 10: API 응답 시간 (TO-BE)**

---

## 5. 결과 정리 및 블로그 작성

### 5-1. 성능 비교 표

| 측정 항목 | AS-IS | TO-BE | 개선율 |
|----------|-------|-------|--------|
| **EXPLAIN - type** | ALL | range | - |
| **EXPLAIN - key** | NULL | idx_products_brand_likes | - |
| **EXPLAIN - rows** | 10000 | 1000 | 10배 감소 |
| **EXPLAIN - Extra** | Using filesort | Using where | filesort 제거 |
| **쿼리 실행 시간** | 350ms | 15ms | **23배 향상** |
| **API 응답 시간** | 400ms | 50ms | **8배 향상** |

*실제 측정값으로 대체하세요*

---

### 5-2. 블로그 글감

#### 제목 후보
- "상품 목록 조회가 느려요? 인덱스로 23배 빠르게 만들기"
- "좋아요 순 정렬에서 발생한 Using filesort 잡기"
- "10만개 상품 데이터에서 인덱스의 위력 (EXPLAIN 실전)"
- "DTO Projection으로 N+1 문제 원천 차단하기"

#### TL;DR (1줄 요약)
> 브랜드 필터 + 좋아요 순 정렬 쿼리에 복합 인덱스 `(brand_id, likes_count DESC)`를 추가하여 응답 시간을 350ms에서 15ms로 **23배 개선**했습니다.

#### 글 구성

**1. 문제 상황**
```
🔴 사용자 불만:
"상품 목록이 너무 느려요. 브랜드별로 인기 상품을 보려고 하는데 몇 초씩 걸려요."

📊 현황:
- 상품 데이터: 10만개
- 쿼리: 브랜드 필터 + 좋아요 많은 순 정렬
- 응답 시간: 350ms (너무 느림)
```

**2. 원인 분석 (EXPLAIN)**
```sql
EXPLAIN SELECT ...

결과:
- type: ALL → 전체 테이블 스캔!
- rows: 10000 → 1만개 행 검사
- Extra: Using filesort → 정렬을 위한 추가 작업
```

**AS-IS EXPLAIN 캡처 첨부**

**3. 해결 방법**
```
💡 아이디어:
- WHERE 조건: brand_id
- ORDER BY: likes_count DESC
→ 복합 인덱스로 필터링과 정렬 모두 커버!

CREATE INDEX idx_products_brand_likes
ON products(brand_id, likes_count DESC);
```

**4. 개선 결과 (EXPLAIN)**
```sql
EXPLAIN SELECT ...

결과:
- type: range → 인덱스 범위 스캔 ✅
- key: idx_products_brand_likes ✅
- rows: 1000 → 90% 감소 ✅
- Extra: Using where (filesort 제거) ✅
```

**TO-BE EXPLAIN 캡처 첨부**

**5. 성능 개선**
```
📈 개선 결과:
- 쿼리 실행 시간: 350ms → 15ms (23배)
- API 응답 시간: 400ms → 50ms (8배)
- 사용자 만족도 ⬆️
```

**성능 비교 그래프/표 첨부**

**6. 배운 점**
```
💡 인사이트:

1. 인덱스 설계는 "필터링 → 정렬" 순서
   - WHERE절 컬럼 먼저: brand_id
   - ORDER BY 컬럼 나중: likes_count DESC

2. EXPLAIN은 추측이 아닌 확인
   - type, key, rows, Extra 모두 중요
   - Using filesort는 성능 저하의 신호

3. 10만건은 작다? 아니다!
   - 적은 데이터에서는 문제 없어도
   - 실제 서비스에서는 치명적

4. DTO Projection으로 N+1 원천 차단
   - Entity 조회 → 연관 엔티티 접근 가능 → LAZY 로딩 위험
   - DTO Projection → 필요한 컬럼만 → LAZY 로딩 불가능
   - Native Query로 명시적 제어

5. LEFT JOIN 주의
   - Spring Data JPA의 메서드 네이밍 규칙
   - @Query로 명시적 쿼리 작성 권장
```

**7. 추가 개선 아이디어**
```
🚀 더 나아가기:

1. DTO Projection으로 Brand 조회 제거 ✅
   - Native Query로 필요한 컬럼만 SELECT
   - ProductProjection 인터페이스 활용
   - LEFT JOIN과 LAZY 로딩 완전 차단

2. 캐시 적용
   - Redis로 인기 상품 목록 캐싱
   - TTL 1분, 좋아요 등록 시 무효화

3. COUNT 쿼리 최적화
   - 페이징용 COUNT 쿼리도 매번 실행
   - 캐시 또는 커서 기반 페이지네이션

4. 비정규화 구조
   - Product.likesCount 컬럼 활용
   - COUNT 집계 대신 컬럼 직접 조회
```

---

### 5-3. 과제 체크리스트

#### 🔖 Index (인덱스 최적화)
- ✅ 브랜드 필터 + 좋아요 순 정렬 쿼리 분석
- ✅ EXPLAIN으로 AS-IS 측정 (캡처)
- ✅ 복합 인덱스 추가: `(brand_id, likes_count DESC)`
- ✅ EXPLAIN으로 TO-BE 측정 (캡처)
- ✅ 성능 개선 확인 (응답 시간 측정)

#### ❤️ Structure (비정규화)
- ✅ Product.likesCount 컬럼 존재 확인
- ✅ 좋아요 등록 시 likesCount 자동 증가 확인
- ✅ 비관적 락 적용 확인 (FOR UPDATE)

#### ⚡ Cache (Redis 캐시)
- ⬜ Redis 캐시 적용 (별도 과제)
- ⬜ TTL 및 무효화 전략 수립

---

## 📸 캡처 체크리스트

총 10개 캡처 포인트:

1. ✅ 현재 인덱스 목록 (AS-IS)
2. ✅ API 응답 시간 (AS-IS)
3. ✅ EXPLAIN 결과 - 브랜드 필터 (AS-IS)
4. ✅ 쿼리 실행 시간 (AS-IS)
5. ✅ EXPLAIN 결과 - 전체 좋아요순 (AS-IS)
6. ✅ 인덱스 추가 후 목록
7. ✅ EXPLAIN 결과 - 브랜드 필터 (TO-BE)
8. ✅ 쿼리 실행 시간 (TO-BE)
9. ✅ EXPLAIN 결과 - 전체 좋아요순 (TO-BE)
10. ✅ API 응답 시간 (TO-BE)

---

## 🛠️ 트러블슈팅

### 인덱스가 사용되지 않음
```sql
-- 통계 정보 갱신
ANALYZE TABLE products;

-- 옵티마이저 힌트 사용
SELECT * FROM products USE INDEX (idx_products_brand_likes)
WHERE brand_id = 1
ORDER BY likes_count DESC
LIMIT 20;
```

### 데이터가 너무 적음
- 현재 10만개 데이터가 있어야 함
- Docker MySQL 재시작: `docker-compose down -v && docker-compose up -d`

### LEFT JOIN 여전히 발생
- Repository 메서드를 `@Query`로 명시적 작성
- 또는 Native Query 사용

---

## 📚 참고 파일

- **API 테스트**: `.http/week5-assignment.http`
- **실제 쿼리**: `.codeguide/actual-queries.sql`
- **과제 계획**: `.codeguide/week5-task-plan.md`

---

## ✅ 최종 점검

- [ ] 10만개 데이터 생성 완료
- [ ] AS-IS EXPLAIN 캡처 완료
- [ ] 인덱스 추가 완료
- [ ] TO-BE EXPLAIN 캡처 완료
- [ ] 성능 비교 표 작성 완료
- [ ] 블로그 초안 작성 완료

---

**끝! 이 문서 하나로 과제 완료하세요.** 🚀
