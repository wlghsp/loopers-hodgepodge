# 🎯 Step 5: 테스트 및 검증 가이드

> **목표**: 구현한 랭킹 시스템이 정상 동작하는지 검증하고, 문제 발생 시 해결 방법을 제시합니다.

---

## 🧠 이해하기: 전체 흐름 복습

### 지금까지 만든 전체 시스템

```
[1] 사용자가 상품 조회
    ↓
[2] ProductViewedEvent 발행 (commerce-api)
    ↓
[3] Kafka로 전송
    ↓
[4] RankingKafkaConsumer 수신 (commerce-streamer)
    ↓
[5] RankingService.incrementScore() 호출
    ↓
[6] Redis ZSET에 점수 저장
    예: ranking:all:20251223 → {product:101: 125.5}
    ↓
[7] GET /api/v1/rankings API 호출
    ↓
[8] Redis에서 랭킹 조회 + DB에서 상품 정보 조회
    ↓
[9] 사용자에게 랭킹 반환
```

### 테스트해야 할 것들

1. **이벤트 발행**: 상품 조회 시 이벤트가 발행되는가?
2. **Kafka 전송**: Kafka에 메시지가 전송되는가?
3. **Consumer 처리**: Streamer가 메시지를 받아서 처리하는가?
4. **Redis 저장**: Redis에 랭킹 데이터가 쌓이는가?
5. **API 조회**: API로 랭킹을 조회할 수 있는가?
6. **상품 랭킹**: 상품 상세 조회 시 순위가 나오는가?

### 왜 이 순서대로 테스트하는가?

**Bottom-up 방식**: 하위 레이어부터 확인
1. 인프라 (Docker) → 2. 이벤트 발행 → 3. Consumer → 4. Redis → 5. API

**장점**:
- 문제 발생 시 어디서 막혔는지 명확히 알 수 있음
- 단계별로 검증하므로 디버깅이 쉬움

---

## 📌 테스트 전 준비사항

### 1. 인프라 실행 확인

```bash
# Docker Compose로 인프라 실행
cd docker
docker-compose -f infra-compose.yml up -d

# 컨테이너 상태 확인
docker ps

# 다음이 실행 중이어야 함:
# - mysql (3306)
# - redis-master (6379)
# - redis-readonly (6380)
# - kafka (9092)
# - kafka-ui (9099)
```

### 2. 애플리케이션 실행

```bash
# commerce-streamer 실행 (Consumer)
cd apps/commerce-streamer
./gradlew bootRun

# 다른 터미널에서 commerce-api 실행 (API)
cd apps/commerce-api
./gradlew bootRun
```

### 3. 실행 확인

```bash
# commerce-api 헬스체크
curl http://localhost:8080/actuator/health

# commerce-streamer 로그 확인
# "Kafka consumer started" 메시지 확인
```

---

## 🧪 통합 테스트 시나리오

### 시나리오 1: 이벤트 발행 → 랭킹 적재 → 조회

#### Step 1: 상품 조회 (ProductViewedEvent 발행)

```bash
# 상품 101번을 10번 조회
for i in {1..10}; do
  curl -X GET "http://localhost:8080/api/v1/products/101"
  sleep 0.1
done

# 상품 102번을 5번 조회
for i in {1..5}; do
  curl -X GET "http://localhost:8080/api/v1/products/102"
  sleep 0.1
done
```

#### Step 2: 주문 생성 (OrderCreatedEvent 발행)

```bash
# 상품 101번을 포함한 주문
curl -X POST "http://localhost:8080/api/v1/orders" \
  -H "X-USER-ID: user1" \
  -H "Content-Type: application/json" \
  -d '{
    "items": [
      {
        "productId": 101,
        "quantity": 2
      }
    ]
  }'
```

#### Step 3: Kafka 메시지 확인

**Kafka UI 접속**: http://localhost:9099

1. Topics → `catalog-events` 클릭
2. Messages 탭에서 최근 메시지 확인
3. `PRODUCT_VIEWED`, `ORDER_CREATED` 이벤트 확인

#### Step 4: Commerce-Streamer 로그 확인

```bash
# Docker 로그 확인 (또는 IDE 콘솔)
docker logs -f commerce-streamer

# 다음 로그 확인:
# "랭킹 배치 메시지 수신: N개"
# "랭킹 배치 처리 완료: N개"
```

#### Step 5: Redis 데이터 검증

```bash
# Redis CLI 접속
docker exec -it redis-master redis-cli

# 오늘 날짜 확인 (예: 20251225)
> KEYS ranking:all:*
1) "ranking:all:20251225"

# Top 10 조회
> ZREVRANGE ranking:all:20251225 0 9 WITHSCORES
 1) "product:101"
 2) "8.33"           # 점수 예시 (조회 10×0.1 + 주문 점수)
 3) "product:102"
 4) "0.5"            # 조회 5×0.1
 ...

# 상품 101번 순위 확인 (0-based)
> ZREVRANK ranking:all:20251225 product:101
(integer) 0  # 0위 = 1등

# 상품 101번 점수 확인
> ZSCORE ranking:all:20251225 product:101
"8.33"

# TTL 확인 (2일 = 172800초)
> TTL ranking:all:20251225
(integer) 172750  # 약 2일 남음
```

#### Step 6: Ranking API 호출

```bash
# Top 20 조회
curl -X GET "http://localhost:8080/api/v1/rankings?page=0&size=20" | jq

# 특정 날짜 조회
curl -X GET "http://localhost:8080/api/v1/rankings?date=20251225&page=0&size=20" | jq
```

**예상 응답**:
```json
{
  "success": true,
  "data": {
    "content": [
      {
        "productId": 101,
        "productName": "상품명",
        "price": 150000,
        "stock": 48,
        "likesCount": 123,
        "rank": 1,
        "score": 8.33
      }
    ],
    "pageable": {
      "pageNumber": 0,
      "pageSize": 20
    },
    "totalElements": 5,
    "totalPages": 1
  }
}
```

#### Step 7: 상품 상세 조회 (랭킹 포함)

```bash
# 1위 상품 조회
curl -X GET "http://localhost:8080/api/v1/products/101" | jq

# 순위권 밖 상품 조회
curl -X GET "http://localhost:8080/api/v1/products/999" | jq
```

**예상 응답** (순위권 내):
```json
{
  "success": true,
  "data": {
    "id": 101,
    "name": "상품명",
    "price": 150000,
    "rank": 1,          // 랭킹 정보 포함
    "score": 8.33
  }
}
```

**예상 응답** (순위권 밖):
```json
{
  "success": true,
  "data": {
    "id": 999,
    "name": "상품명",
    "price": 50000,
    "rank": null,       // 순위 없음
    "score": null
  }
}
```

---

## 🔍 멱등성 테스트

### 왜 멱등성을 테스트하는가?

Kafka Consumer가 재시작되면 같은 이벤트를 다시 처리할 수 있습니다.
멱등성이 보장되지 않으면 점수가 중복 증가하여 랭킹이 왜곡됩니다.

### 테스트 방법

#### Step 1: 현재 점수 확인

```bash
# Redis에서 현재 점수 저장
docker exec -it redis-master redis-cli
> ZSCORE ranking:all:20251225 product:101
"8.33"  # 현재 점수 기억
```

#### Step 2: Commerce-Streamer 재시작

```bash
# Consumer 중지
# (IDE에서 중지 또는 docker stop commerce-streamer)

# Consumer 재시작
# (IDE에서 실행 또는 docker start commerce-streamer)

# 로그 확인: "모든 이벤트가 이미 처리됨" 메시지 확인
```

#### Step 3: 점수 재확인

```bash
# Redis에서 점수 확인
> ZSCORE ranking:all:20251225 product:101
"8.33"  # 점수가 그대로 유지되어야 함 (중복 증가 없음)
```

#### Step 4: event_handled 테이블 확인

```bash
# MySQL 접속
docker exec -it mysql mysql -uroot -proot loopers

# event_handled 테이블 조회
SELECT event_type, COUNT(*) as cnt
FROM event_handled
WHERE event_type IN ('PRODUCT_VIEWED', 'ORDER_CREATED')
GROUP BY event_type;

# 결과: 각 이벤트가 1번만 처리되었는지 확인
```

---

## 🧪 점수 계산 검증

### 수동 계산 vs 실제 점수

#### 예시 시나리오:
- 상품 101번: 조회 10회, 주문 1건 (가격 100,000원, 수량 2)

#### 수동 계산:
```
조회 점수 = 10 × 0.1 = 1.0
주문 점수 = 0.6 × ln(1 + 100,000 × 2) = 0.6 × ln(200,001) ≈ 0.6 × 12.21 ≈ 7.33

총 점수 = 1.0 + 7.33 = 8.33
```

#### Redis 점수 확인:
```bash
> ZSCORE ranking:all:20251225 product:101
"8.33"  # 수동 계산과 일치해야 함
```

---

## 🔧 트러블슈팅 가이드

### 문제 1: Kafka Consumer가 메시지를 소비하지 않음

**증상**:
- 로그에 "랭킹 배치 메시지 수신" 없음
- Redis에 데이터 적재 안됨

**원인 및 해결**:

1. **Kafka 연결 실패**
```bash
# Kafka 상태 확인
docker logs kafka

# commerce-streamer 로그 확인
# "Connection to node -1 (localhost:9092) could not be established" 에러 확인

# 해결: bootstrap-servers 설정 확인
# application.yml에서 KAFKA_BOOTSTRAP_SERVERS 확인
```

2. **Consumer Group Offset 문제**
```bash
# Kafka UI에서 Consumer Groups 확인
# ranking-consumer-group의 Lag 확인

# Offset 리셋 (개발 환경에서만)
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group ranking-consumer-group \
  --reset-offsets --to-earliest --all-topics --execute
```

3. **Topic이 생성되지 않음**
```bash
# Kafka UI에서 Topics 확인
# catalog-events, order-events 존재 여부 확인

# Topic 수동 생성 (필요 시)
kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic catalog-events --partitions 3 --replication-factor 1
```

---

### 문제 2: Redis 데이터가 적재되지 않음

**증상**:
- Consumer 로그는 정상
- Redis에 키가 없음

**원인 및 해결**:

1. **Redis 연결 실패**
```bash
# Redis 상태 확인
docker exec -it redis-master redis-cli PING
# "PONG" 응답 확인

# commerce-streamer 로그 확인
# "Cannot get Jedis connection" 에러 확인

# 해결: Redis 설정 확인
# application.yml에서 REDIS_MASTER_HOST 확인
```

2. **RankingService Bean 주입 실패**
```bash
# 로그 확인: "No qualifying bean of type RankingService"

# 해결: RankingService에 @Service 어노테이션 있는지 확인
# modules/redis에 RankingService가 있는지 확인
# build.gradle.kts에 redis 모듈 의존성 있는지 확인
```

3. **TTL 설정 문제**
```bash
# Redis에서 TTL 확인
> TTL ranking:all:20251222
(integer) -1  # TTL이 설정되지 않음

# 원인: ensureTtl() 로직 버그
# 해결: Step 1의 RankingService 코드 재확인
```

---

### 문제 3: API가 빈 결과를 반환함

**증상**:
- GET /api/v1/rankings → `content: []`
- Redis에는 데이터가 있음

**원인 및 해결**:

1. **날짜 불일치**
```bash
# API 요청 날짜 확인
curl "http://localhost:8080/api/v1/rankings?date=20251221"

# Redis 키 확인
> KEYS ranking:all:*
1) "ranking:all:20251222"  # 날짜 불일치

# 해결: 올바른 날짜로 요청
curl "http://localhost:8080/api/v1/rankings?date=20251222"
```

2. **상품 정보 조회 실패**
```bash
# 로그 확인: "상품 정보 없음: productId=101"

# 원인: 상품이 삭제되었거나 DB에 없음
# 해결: 상품 데이터 확인
mysql> SELECT id, name FROM products WHERE id = 101;
```

3. **페이지네이션 범위 초과**
```bash
# 전체 개수 확인
> ZCARD ranking:all:20251222
(integer) 5  # 5개만 있음

# 2페이지 요청 시 빈 결과
curl "http://localhost:8080/api/v1/rankings?page=2&size=20"

# 해결: 1페이지 요청
curl "http://localhost:8080/api/v1/rankings?page=0&size=20"
```

---

### 문제 4: 멱등성이 보장되지 않음

**증상**:
- Consumer 재시작 후 점수가 중복 증가
- event_handled 테이블에 중복 레코드

**원인 및 해결**:

1. **@Transactional 누락**
```kotlin
// RankingEventFacade에 @Transactional 있는지 확인
@Transactional  // 이게 없으면 멱등성 보장 안됨
fun handleBatchEvents(events: List<DomainEvent>) {
    // ...
}
```

2. **event_handled 테이블 저장 실패**
```bash
# 로그 확인: "Could not execute JDBC batch update"

# 원인: event_handled 테이블이 없음
# 해결: JPA가 자동 생성하도록 설정 또는 수동 생성
CREATE TABLE event_handled (
    event_id VARCHAR(255) PRIMARY KEY,
    event_type VARCHAR(50),
    occurred_at DATETIME(6),
    handled_at DATETIME(6)
);
```

3. **Offset Commit 타이밍 문제**
```kotlin
// Consumer에서 ACK를 try 블록 안에서 호출해야 함
try {
    rankingEventFacade.handleBatchEvents(events)
    acknowledgment.acknowledge()  // 성공 시에만 ACK
} catch (e: Exception) {
    // ACK 하지 않음 → 재처리됨
}
```

---

## 📊 성능 테스트

### 부하 테스트 (Apache Bench)

```bash
# 상품 조회 1000번
ab -n 1000 -c 10 http://localhost:8080/api/v1/products/101

# 랭킹 조회 1000번
ab -n 1000 -c 10 http://localhost:8080/api/v1/rankings?page=0&size=20
```

### Redis 성능 확인

```bash
# Redis Slowlog 확인
> SLOWLOG GET 10

# Latency 모니터링
> LATENCY DOCTOR
```

### Kafka Lag 확인

**Kafka UI**: http://localhost:9099
- Consumer Groups → ranking-consumer-group
- Lag이 0에 가까우면 정상 (실시간 처리 중)
- Lag이 계속 증가하면 Consumer 처리 속도 부족

---

## ✅ 최종 체크리스트

### 기능 검증
- [ ] 상품 조회 시 ProductViewedEvent 발행 확인
- [ ] Kafka Topic에 이벤트 적재 확인
- [ ] Consumer가 메시지 소비 확인 (로그)
- [ ] Redis ZSET에 랭킹 데이터 적재 확인
- [ ] TTL이 2일로 설정되었는지 확인
- [ ] GET /api/v1/rankings API 정상 동작 확인
- [ ] 상품 정보가 Aggregation되어 반환되는지 확인
- [ ] 상품 상세 조회 시 랭킹 정보 포함 확인
- [ ] 순위권 밖 상품은 rank: null 확인

### 멱등성 검증
- [ ] Consumer 재시작 후 점수 중복 증가 없음 확인
- [ ] event_handled 테이블에 중복 레코드 없음 확인

### 점수 계산 검증
- [ ] 수동 계산과 Redis 점수 일치 확인
- [ ] 로그 정규화가 적용되었는지 확인 (주문 점수)

### 성능 검증
- [ ] 랭킹 API 응답 시간 100ms 이하
- [ ] Kafka Lag이 0에 가까운지 확인
- [ ] Redis Slowlog에 느린 명령어 없는지 확인

---

## 🎉 축하합니다!

Round 9 랭킹 시스템 구현이 완료되었습니다!

**달성한 것들**:
- ✅ Redis ZSET 기반 실시간 랭킹 시스템
- ✅ Kafka를 통한 비동기 이벤트 처리
- ✅ 멱등성 보장으로 데이터 정합성 유지
- ✅ 로그 정규화로 공정한 랭킹 계산
- ✅ 상품 정보 Aggregation으로 사용자 경험 개선

**배운 것들**:
- Redis ZSET의 강력함 (O(logN) 삽입, O(N) Top-N 조회)
- 시간의 양자화로 신선한 랭킹 유지
- 가중치 기반 점수 계산의 비즈니스 가치
- 멱등성이 분산 시스템에서 얼마나 중요한지

**다음 단계**:
- Technical Writing: 블로그에 구현 과정과 고민을 정리해보세요
- Nice-to-Have: 1시간 단위 실시간 랭킹, 콜드 스타트 해결 (Scheduler)
- 성능 최적화: Redis Pipeline, Lua Script 활용

수고하셨습니다! 🚀
