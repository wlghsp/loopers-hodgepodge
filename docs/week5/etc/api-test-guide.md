# API 테스트 가이드

5주차 과제 수행을 위한 전체 API 테스트 방법입니다.

## 📁 테스트 파일

### 1. `.http/week5-assignment.http` ⭐ (과제 전체)
**5주차 과제의 모든 테스트 시나리오 포함**

- **Part 1**: Product 조회 API (Index 최적화)
- **Part 2**: Like 좋아요 API (비정규화 구조)
- **Part 3**: 동시성 테스트
- **Part 4**: 캐시 효과 검증
- **Part 5**: 성능 벤치마크
- **Part 6**: 엣지 케이스

### 2. `.http/product-query-analysis.http` (상품 조회 전용)
**Product API만 집중적으로 테스트**

## 🚀 빠른 시작

### Step 1: 환경 준비
```bash
# MySQL 시작 (10만개 데이터 자동 생성)
cd docker
docker-compose -f infra-compose.yml up -d mysql

# 데이터 생성 확인 (1-2분 소요)
docker-compose -f infra-compose.yml logs -f mysql
# ✅ 브랜드 100개 생성 완료
# ✅ 상품 100000개 생성 완료
```

### Step 2: 애플리케이션 실행
```bash
./gradlew :apps:commerce-api:bootRun
```

### Step 3: API 테스트
IntelliJ에서 `.http/week5-assignment.http` 파일 열고 **▶ Run** 버튼 클릭

## 📊 테스트 시나리오별 가이드

### 1️⃣ Index 최적화 검증

#### 목표
인덱스 적용 전/후 성능 비교

#### 테스트 대상
- 브랜드 필터 + 좋아요 순 정렬 ⭐
- 전체 상품 + 좋아요 순 정렬 ⭐
- 내 좋아요 목록 조회

#### 절차
1. **AS-IS 측정** (인덱스 없는 상태)
   ```
   GET /api/v1/products?brandId=1&sort=LIKES_DESC
   ```
   - 콘솔에서 SQL 복사
   - MySQL에서 `EXPLAIN` 실행
   - 응답 시간 기록

2. **인덱스 추가**
   ```kotlin
   @Table(
       indexes = [
           Index(name = "idx_products_brand_likes", columnList = "brand_id, likes_count DESC"),
           Index(name = "idx_products_likes_count", columnList = "likes_count DESC")
       ]
   )
   ```

3. **TO-BE 측정** (인덱스 있는 상태)
   - 같은 API 재실행
   - `EXPLAIN` 재분석
   - 응답 시간 비교

#### 비교 항목
| 항목 | AS-IS | TO-BE |
|------|-------|-------|
| **type** | ALL | range/ref |
| **key** | NULL | idx_products_brand_likes |
| **rows** | 99485 | ~1000 |
| **Extra** | Using filesort | Using index |
| **응답 시간** | ~350ms | ~15ms |

---

### 2️⃣ Structure 비정규화 검증

#### 목표
`Product.likesCount` 비정규화 구조 동작 확인

#### 테스트 시나리오
1. **좋아요 등록**
   ```
   POST /api/v1/likes/products/1
   X-USER-ID: testuser01
   ```
   - SQL 로그에서 `UPDATE products SET likes_count = likes_count + 1` 확인
   - `FOR UPDATE` (비관적 락) 확인

2. **상품 조회로 증가 확인**
   ```
   GET /api/v1/products/1
   ```
   - `likesCount` 값이 1 증가했는지 확인

3. **좋아요 취소**
   ```
   DELETE /api/v1/likes/products/1
   X-USER-ID: testuser01
   ```
   - `likesCount` 값이 1 감소하는지 확인

#### 동시성 테스트
여러 사용자가 동시에 좋아요 등록:
```
POST /api/v1/likes/products/12345
X-USER-ID: user001

POST /api/v1/likes/products/12345
X-USER-ID: user002

POST /api/v1/likes/products/12345
X-USER-ID: user003
```
→ `likesCount`가 정확히 +3 증가하는지 확인

---

### 3️⃣ Cache 효과 검증

#### 목표
Redis 캐시 적용으로 DB 조회 감소 및 응답 속도 향상

#### 테스트 시나리오

**캐시 히트 확인:**
```
# 첫 조회 (캐시 미스 → DB 조회)
GET /api/v1/products/1
Duration: ~50ms

# 재조회 (캐시 히트 → Redis 조회)
GET /api/v1/products/1
Duration: ~5ms
```

**캐시 무효화 확인:**
```
# 1. 상품 조회 (캐시 저장)
GET /api/v1/products/88888

# 2. 좋아요 등록 (캐시 무효화)
POST /api/v1/likes/products/88888

# 3. 재조회 (캐시 미스 → 최신 데이터)
GET /api/v1/products/88888
→ likesCount가 증가된 값으로 조회됨
```

#### 캐시 전략 문서화
- **TTL**: 상품 상세 5분, 목록 1분
- **무효화**: 좋아요 등록/취소 시 해당 상품 캐시 삭제
- **폴백**: Redis 연결 실패 시 DB 직접 조회

---

## 🔍 EXPLAIN 분석 방법

### MySQL 접속
```bash
docker exec -it $(docker ps -qf "name=mysql") mysql -uapplication -papplication loopers
```

### EXPLAIN 실행
IntelliJ 콘솔에서 Hibernate SQL 복사:
```sql
Hibernate: select p1_0.* from products p1_0 where p1_0.brand_id=? and p1_0.deleted_at is null order by p1_0.likes_count desc limit ?, ?
```

MySQL에서 EXPLAIN 실행:
```sql
EXPLAIN
SELECT p1_0.*
FROM products p1_0
WHERE p1_0.brand_id = 1
  AND p1_0.deleted_at IS NULL
ORDER BY p1_0.likes_count DESC
LIMIT 20;
```

### 결과 해석
| 컬럼 | 의미 | 좋은 값 | 나쁜 값 |
|------|------|---------|---------|
| **type** | 접근 방법 | `ref`, `range` | `ALL` |
| **key** | 사용된 인덱스 | 인덱스명 | `NULL` |
| **rows** | 검사할 행 수 | 적을수록 좋음 | 100000 |
| **Extra** | 추가 정보 | `Using index` | `Using filesort` |

---

## 📈 성능 측정 방법

### IntelliJ HTTP Client
각 요청 실행 후 하단에 Duration 표시:
```
< 200 OK
< Content-Type: application/json
< Duration: 45 ms
```

### MySQL 프로파일링
```sql
SET profiling = 1;

-- 쿼리 실행
SELECT * FROM products WHERE brand_id = 1 ORDER BY likes_count DESC LIMIT 20;

-- 실행 시간 확인
SHOW PROFILES;

SET profiling = 0;
```

---

## 📝 테스트 결과 기록 템플릿

### Index 최적화 결과

#### AS-IS (인덱스 없음)
```
EXPLAIN 결과:
- type: ALL
- key: NULL
- rows: 99485
- Extra: Using where; Using filesort

응답 시간: 350ms
```

#### TO-BE (인덱스 적용)
```
EXPLAIN 결과:
- type: range
- key: idx_products_brand_likes
- rows: 1000
- Extra: Using index

응답 시간: 15ms
```

#### 개선율
- 응답 시간: **23배 향상** (350ms → 15ms)
- 검사 행 수: **99배 감소** (99485 → 1000)

---

### Structure 비정규화 검증

#### 테스트 결과
- ✅ 좋아요 등록 시 `likesCount` 자동 증가
- ✅ 좋아요 취소 시 `likesCount` 자동 감소
- ✅ 비관적 락으로 동시성 제어 (`FOR UPDATE` 확인)
- ✅ 멱등성 보장 (중복 요청 시 에러 없음)

#### 동시성 테스트 결과
- 10명 동시 좋아요 → `likesCount` 정확히 +10 증가 ✅

---

### Cache 적용 결과

#### 캐시 히트율
- 첫 조회: 50ms (캐시 미스)
- 재조회: 5ms (캐시 히트)
- **응답 시간 90% 감소**

#### 캐시 전략
- TTL: 상품 상세 5분, 목록 1분
- 무효화: 좋아요 등록/취소 시
- 폴백: Redis 장애 시 DB 직접 조회

---

## 🛠️ 문제 해결

### SQL 로그가 안 보임
`modules/jpa/src/main/resources/jpa.yml` 확인:
```yaml
spring:
  jpa:
    show-sql: true
```

### 테스트 유저가 없다고 나옴
Member 데이터 추가:
```sql
INSERT INTO members (member_id, email, birth_date, gender, point, created_at, updated_at)
VALUES ('testuser01', 'test@example.com', '1990-01-01', 'MALE', 100000, NOW(), NOW());
```

### 데이터가 없음
Docker MySQL 재시작:
```bash
cd docker
docker-compose -f infra-compose.yml down -v
docker-compose -f infra-compose.yml up -d mysql
```

---

## 📚 참고 문서
- 빠른 시작: `.codeguide/quick-start-query-analysis.md`
- 상세 가이드: `.codeguide/query-analysis-guide.md`
- SQL 스크립트: `docker/query-analysis.sql`
- 과제 계획: `.codeguide/week5-task-plan.md`
