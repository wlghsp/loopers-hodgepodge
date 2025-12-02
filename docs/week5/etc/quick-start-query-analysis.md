# 쿼리 분석 빠른 시작 가이드

10만개 데이터로 쿼리 성능을 분석하는 가장 빠른 방법입니다.

## 1. 환경 준비 (5분)

### Step 1: Docker MySQL 시작
```bash
cd docker
docker-compose -f infra-compose.yml up -d mysql
```

**데이터 생성 확인** (1-2분 소요):
```bash
# 로그 확인
docker-compose -f infra-compose.yml logs -f mysql

# 완료 메시지 확인
# ✅ 브랜드 100개 생성 완료
# ✅ 상품 100000개 생성 완료
```

### Step 2: 애플리케이션 실행
```bash
./gradlew :apps:commerce-api:bootRun
```

**실행 확인**:
- `http://localhost:8080/actuator/health` 접속
- `{"status":"UP"}` 응답 확인

## 2. 쿼리 분석 (IntelliJ 사용)

### Step 1: .http 파일 열기
IntelliJ에서 `.http/product-query-analysis.http` 파일 열기

### Step 2: API 실행
각 요청 옆의 **▶ Run** 버튼 클릭

**주요 시나리오**:
1. `브랜드 필터 + 좋아요 순 정렬` ⭐ (과제)
2. `전체 상품 + 좋아요 순 정렬` ⭐ (과제)
3. `최신순 정렬`
4. `가격 낮은순 정렬`

### Step 3: SQL 로그 확인
IntelliJ 콘솔에서 Hibernate 쿼리 확인:
```
Hibernate: select ... from products p1_0 where p1_0.brand_id=? and p1_0.deleted_at is null order by p1_0.likes_count desc limit ?, ?
```

### Step 4: EXPLAIN 실행
SQL을 복사하여 MySQL에서 분석:

```bash
# MySQL 접속
docker exec -it $(docker ps -qf "name=mysql") mysql -uapplication -papplication loopers
```

```sql
-- 복사한 SQL에 EXPLAIN 추가
EXPLAIN
SELECT p1_0.*
FROM products p1_0
WHERE p1_0.brand_id = 1
  AND p1_0.deleted_at IS NULL
ORDER BY p1_0.likes_count DESC
LIMIT 20;
```

## 3. 결과 분석

### EXPLAIN 주요 컬럼

| 컬럼 | 좋은 값 | 나쁜 값 | 의미 |
|------|---------|---------|------|
| **type** | `ref`, `range` | `ALL` | 인덱스 사용 방식 |
| **key** | 인덱스명 | `NULL` | 사용된 인덱스 |
| **rows** | 적을수록 좋음 | 100000 | 검사할 예상 행 수 |
| **Extra** | `Using index` | `Using filesort` | 추가 정보 |

### 예시 결과

#### AS-IS (최적화 전)
```
+------+------+-------+------+---------+-------------+
| type | key  | rows  | Extra                      |
+------+------+-------+------+---------+-------------+
| ALL  | NULL | 99485 | Using where; Using filesort|
+------+------+-------+------+---------+-------------+
```
❌ 전체 스캔 + 파일 정렬 → **느림**

#### TO-BE (최적화 후 목표)
```
+-------+---------------------------+------+--------------+
| type  | key                       | rows | Extra        |
+-------+---------------------------+------+--------------+
| range | idx_products_brand_likes  | 1000 | Using index  |
+-------+---------------------------+------+--------------+
```
✅ 인덱스 사용 + 커버링 인덱스 → **빠름**

## 4. 응답 시간 측정

### IntelliJ HTTP Client 응답 시간
API 실행 후 하단에 표시:
```
< 200 OK
< Content-Type: application/json
< Duration: 45 ms
```

### 목표 성능
- ✅ 우수: 50ms 이하
- ⚠️ 보통: 50-100ms
- ❌ 개선 필요: 100ms 이상

## 5. 빠른 최적화 체크리스트

### 현재 인덱스 확인
```sql
SHOW INDEXES FROM products;
```

**현재 인덱스**:
- `PRIMARY` (id)
- `idx_products_brand_id` (brand_id)
- `idx_products_likes_count` (likes_count)

### 최적화 고려사항

1. **브랜드 필터 + 좋아요 정렬**
   - 단일 인덱스: `brand_id`, `likes_count` 각각 사용
   - 복합 인덱스: `(brand_id, likes_count)` 고려

2. **전체 상품 + 좋아요 정렬**
   - `likes_count` 인덱스 사용 확인
   - `deleted_at` 필터링 영향 확인

3. **Soft Delete (deleted_at)**
   - 복합 인덱스에 `deleted_at` 포함 고려
   - 예: `(deleted_at, brand_id, likes_count)`

## 6. 문제 해결

### SQL이 로그에 안 보임
`modules/jpa/src/main/resources/jpa.yml` 확인:
```yaml
spring:
  jpa:
    show-sql: true  # ← 이 설정 확인
```

### 데이터가 없다고 나옴
Docker MySQL 컨테이너 재시작:
```bash
cd docker
docker-compose -f infra-compose.yml down -v
docker-compose -f infra-compose.yml up -d mysql
```

### 애플리케이션이 안 뜸
`ddl-auto` 설정 확인:
```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: validate  # ← create가 아닌 validate여야 함
```

## 7. 다음 단계

1. ✅ API로 쿼리 실행 및 SQL 확인
2. ⬜ MySQL에서 EXPLAIN 분석
3. ⬜ 인덱스 추가/변경
4. ⬜ EXPLAIN 재분석 (개선 확인)
5. ⬜ 응답 시간 비교 (AS-IS vs TO-BE)

## 8. 추가 분석 도구

### 준비된 SQL 스크립트 실행
```bash
docker exec -it $(docker ps -qf "name=mysql") mysql -uapplication -papplication loopers < docker/query-analysis.sql
```

### 프로파일링으로 실제 실행 시간 측정
```sql
SET profiling = 1;

-- 쿼리 실행
SELECT * FROM products WHERE brand_id = 1 ORDER BY likes_count DESC LIMIT 20;

-- 실행 시간 확인
SHOW PROFILES;

SET profiling = 0;
```

## 참고 문서
- 상세 가이드: `.codeguide/query-analysis-guide.md`
- SQL 스크립트: `docker/query-analysis.sql`
- HTTP 요청: `.http/product-query-analysis.http`
