# Step 9: 최종 테스트 & 체크리스트

> 전체 시스템 통합 테스트

---

## 9.1 전체 시스템 구조 확인

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Commerce-API   │────▶│  Redis ZSET      │◀────│ Commerce-Batch  │
│  (Ranking API)  │     │  (일간 랭킹)      │     │  (집계 Job)     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                                                 │
         │                                                 │
         ▼                                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                      MySQL Database                              │
│  - mv_product_rank_weekly   (주간 TOP 100)                      │
│  - mv_product_rank_monthly  (월간 TOP 100)                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9.2 전체 플로우 테스트

### 0단계: 테스트 데이터 초기화 ⭐️

**배치를 테스트하려면 Redis에 일간 랭킹 데이터가 필요합니다!**

**방법 1: 간단한 버전 (7일치, 상위 10개 상품) - 추천**

```bash
# Redis에 테스트 데이터 적재
docker exec -i redis-master redis-cli < http/commerce-api/init-ranking-simple.redis

# 데이터 확인
docker exec -it redis-master redis-cli KEYS "ranking:all:*"
```

**방법 2: 자동 생성 스크립트 (30일치, 100개 상품)**

```bash
# 실행 권한 부여 (최초 1회)
chmod +x http/commerce-api/init-ranking-data.sh

# 스크립트 실행
./http/commerce-api/init-ranking-data.sh
```

---

### 1단계: 일간 랭킹 데이터 확인 (Redis)

```bash
# Redis 접속
docker exec -it redis-master redis-cli

# 생성된 키 확인
KEYS ranking:all:*

# 예시 키 조회 (2025-12-26)
ZREVRANGE ranking:all:20251226 0 9 WITHSCORES
```

**예상 결과:**
```
1) "product:1"
2) "140"
3) "product:2"
4) "115"
5) "product:3"
6) "110"
...
```

**주간 합산 예상 (2025-W52, 12/22~12/28):**
- product:1 = 910점 (1위)
- product:2 = 770점 (2위)
- product:3 = 735점 (3위)

---

### 2단계: 배치 실행 (commerce-batch)

```bash
# 서버 시작
./gradlew :apps:commerce-batch:bootRun
```

다른 터미널에서:

```bash
# 주간 랭킹 생성
curl -X POST "http://localhost:8085/batch/weekly?yearWeek=2025-W52"

# 월간 랭킹 생성
curl -X POST "http://localhost:8085/batch/monthly?yearMonth=2025-12"
```

**예상 결과:**
```
주간 랭킹 배치: COMPLETED
월간 랭킹 배치: COMPLETED
```

---

### 3단계: MV 테이블 확인 (MySQL)

```bash
docker exec -it loopers-mysql mysql -uroot -ppassword loopers
```

```sql
-- 주간 랭킹 확인
SELECT product_id, year_week, score, rank_position
FROM mv_product_rank_weekly
WHERE year_week = '2025-W52'
ORDER BY rank_position
LIMIT 10;

-- 월간 랭킹 확인
SELECT product_id, year_month, score, rank_position
FROM mv_product_rank_monthly
WHERE year_month = '2025-12'
ORDER BY rank_position
LIMIT 10;
```

**예상 결과:**
```
+------------+----------+-------+---------------+
| product_id | year_week| score | rank_position |
+------------+----------+-------+---------------+
|        101 | 2025-W52 | 850.2 |             1 |
|        205 | 2025-W52 | 720.5 |             2 |
...
```

---

### 4단계: API 테스트 (commerce-api)

```bash
# 서버 시작
./gradlew :apps:commerce-api:bootRun
```

다른 터미널에서:

```bash
# 일간 랭킹
curl -s "http://localhost:8080/api/v1/rankings?period=daily&date=20251226&size=5" | jq

# 주간 랭킹
curl -s "http://localhost:8080/api/v1/rankings?period=weekly&date=2025-W52&size=5" | jq

# 월간 랭킹
curl -s "http://localhost:8080/api/v1/rankings?period=monthly&date=2025-12&size=5" | jq
```

**예상 결과:**
```json
{
  "success": true,
  "data": {
    "content": [
      {
        "product": {
          "id": 101,
          "name": "상품명",
          ...
        },
        "rank": 1,
        "score": 850.2
      },
      ...
    ],
    "totalElements": 100,
    "totalPages": 20,
    "number": 0
  }
}
```

---

## 9.3 페이지네이션 테스트

```bash
# 1페이지 (0~9위)
curl "http://localhost:8080/api/v1/rankings?period=weekly&date=2025-W52&size=10&page=0"

# 2페이지 (10~19위)
curl "http://localhost:8080/api/v1/rankings?period=weekly&date=2025-W52&size=10&page=1"

# 10페이지 (90~99위)
curl "http://localhost:8080/api/v1/rankings?period=weekly&date=2025-W52&size=10&page=9"

# 11페이지 (없음, 빈 배열)
curl "http://localhost:8080/api/v1/rankings?period=weekly&date=2025-W52&size=10&page=10"
```

---

## 9.4 엣지 케이스 테스트

### 존재하지 않는 기간
```bash
curl "http://localhost:8080/api/v1/rankings?period=weekly&date=2024-W01&size=10"
```
**예상**: 빈 배열 반환

### 잘못된 period
```bash
curl "http://localhost:8080/api/v1/rankings?period=invalid&date=20251226&size=10"
```
**예상**: daily로 fallback

### date 파라미터 없음
```bash
curl "http://localhost:8080/api/v1/rankings?period=weekly&size=10"
```
**예상**: 현재 주차 랭킹 반환

---

## 9.5 스케줄러 동작 확인

### 테스트용 Cron 설정 (1분마다)

`RankingBatchScheduler.kt` 임시 수정:

```kotlin
@Scheduled(cron = "0 */1 * * * *")  // 매 1분마다
fun testWeeklyRanking() {
    runWeeklyRanking()
}
```

### 로그 확인

```bash
./gradlew :apps:commerce-batch:bootRun
```

**1분마다 로그 출력 확인:**
```
2025-12-29 10:01:00 ... : ===== 주간 랭킹 스케줄 실행: 2025-W52 =====
2025-12-29 10:01:02 ... : 주간 랭킹 배치 성공: COMPLETED
2025-12-29 10:02:00 ... : ===== 주간 랭킹 스케줄 실행: 2025-W52 =====
...
```

**테스트 완료 후 원래 Cron으로 복원:**
```kotlin
@Scheduled(cron = "0 0 1 * * MON")  // 매주 월요일 1시
```

---

## ✅ 최종 체크리스트

### 🗄️ Database
- [ ] mv_product_rank_weekly 테이블 존재
- [ ] mv_product_rank_monthly 테이블 존재
- [ ] 데이터 정상 저장 확인

### 🔧 commerce-batch
- [ ] 빌드 성공
- [ ] 서버 실행 성공
- [ ] 주간 배치 수동 실행 성공
- [ ] 월간 배치 수동 실행 성공
- [ ] 스케줄러 동작 확인
- [ ] Batch Meta Tables 생성 확인 (BATCH_JOB_EXECUTION 등)

### 🚀 commerce-api
- [ ] 빌드 성공
- [ ] 서버 실행 성공
- [ ] 일간 랭킹 API 동작
- [ ] 주간 랭킹 API 동작
- [ ] 월간 랭킹 API 동작
- [ ] 페이지네이션 동작
- [ ] 상품 정보 Aggregation 확인

### 📊 데이터 흐름
- [ ] Redis → Batch → MySQL → API 전체 흐름 확인
- [ ] TOP 100 필터링 동작 확인
- [ ] 멱등성 확인 (같은 기간 재실행 시 덮어쓰기)

---

## 9.6 트러블슈팅

### Batch Meta Tables 없음
Spring Batch 메타데이터 테이블은 `docker/01-schema.sql`에 포함되어 있어야 합니다.

```bash
docker-compose down -v
docker-compose up -d
```

또는:
```
spring.batch.jdbc.initialize-schema: never
```
설정 확인 (`docker/01-schema.sql`에서 관리)

### Redis 연결 실패
```bash
docker ps  # Redis 컨테이너 확인
docker-compose up -d redis
```

### MV 테이블 없음
```bash
docker exec -i loopers-mysql mysql -uroot -ppassword loopers < docker/01-schema.sql
```

### Entity 인식 안됨
```
@EntityScan 설정 확인
@EnableJpaRepositories 설정 확인
```

---

## 🎉 완료!

모든 체크리스트를 통과했다면 Round 10 구현이 완료되었습니다!

**다음 단계**:
- Technical Writing 작성
- PR 생성

---

**고생하셨습니다! 🎉🔥**
