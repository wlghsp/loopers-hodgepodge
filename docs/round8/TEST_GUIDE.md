# Round 8 Kafka 이벤트 파이프라인 테스트 가이드

## 🚀 빠른 시작 (5분 안에 테스트 시작)

### 1단계: 인프라 환경 시작

```bash
# MySQL, Redis, Kafka 시작 (프로젝트 기본 인프라)
docker-compose -f ./docker/infra-compose.yml up -d

# 상태 확인
docker-compose -f ./docker/infra-compose.yml ps
```

**참고:**
- Kafka는 KRaft 모드로 실행 (Zookeeper 불필요)
- Kafka 포트: `localhost:19092` (외부 접속용)
- Kafka UI: `http://localhost:9099`

### 2단계: 토픽 생성

```bash
# Kafka 컨테이너 이름 확인 (kafka)
docker ps | grep kafka

# catalog-events 토픽 생성
docker exec -it kafka kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --topic catalog-events \
  --partitions 3 \
  --replication-factor 1

# order-events 토픽 생성
docker exec -it kafka kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --topic order-events \
  --partitions 3 \
  --replication-factor 1

# 토픽 확인
docker exec -it kafka kafka-topics.sh --list \
  --bootstrap-server localhost:9092
```

### 3단계: 애플리케이션 실행

**터미널 1: commerce-api (Producer)**
```bash
cd apps/commerce-api
./gradlew bootRun
```

**터미널 2: commerce-streamer (Consumer)**
```bash
cd apps/commerce-streamer
./gradlew bootRun
```

---

## 📊 테스트 시나리오

### 시나리오 1: 좋아요 이벤트 (단건 처리)

**1. 상품 좋아요 추가**
```bash
curl -X POST http://localhost:8080/api/products/1/likes \
  -H "Content-Type: application/json" \
  -H "X-USER-ID: user123"
```

**2. 로그 확인**

**commerce-api (Producer):**
```
[OutboxEventListener] EventOutbox 저장: eventId=xxx, eventType=PRODUCT_LIKED, aggregateType=PRODUCT
[OutboxEventPublisher] Kafka 발행 성공: eventId=xxx, partition=0, offset=5
```

**commerce-streamer (Consumer):**
```
[MetricsKafkaConsumer] 메시지 수신: partition=0, offset=5, key=1
[MetricsEventFacade] 이벤트 처리 완료: eventId=xxx, type=PRODUCT_LIKED
[ProductMetricsService] ProductMetrics 업데이트: productId=1, likes=1, views=0, sales=0
```

**3. DB 확인**

**commerce_api:**
```sql
-- EventOutbox 확인
SELECT * FROM event_outbox WHERE event_type = 'PRODUCT_LIKED' ORDER BY created_at DESC LIMIT 5;
```

**commerce_streamer:**
```sql
-- EventHandled 확인 (멱등성)
SELECT * FROM event_handled WHERE event_type = 'PRODUCT_LIKED' ORDER BY handled_at DESC LIMIT 5;

-- ProductMetrics 확인
SELECT * FROM product_metrics WHERE product_id = 1;
```

---

### 시나리오 2: 멱등성 테스트

**1. 같은 이벤트를 Kafka에 직접 발행 (중복 테스트)**

```bash
# Kafka 프로듀서로 같은 eventId 발행
docker exec -it kafka kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic catalog-events \
  --property "parse.key=true" \
  --property "key.separator=:"

# 입력 (key:value 형식)
1:{"eventId":"test-duplicate-001","eventType":"PRODUCT_LIKED","aggregateId":1,"occurredAt":"2024-12-19T10:00:00Z","likeId":999,"memberId":"user123","productId":1,"likedAt":"2024-12-19T10:00:00Z"}
```

**2. 같은 eventId로 재발행**
```bash
# 동일한 메시지 재입력 (위 JSON 다시 입력)
1:{"eventId":"test-duplicate-001","eventType":"PRODUCT_LIKED","aggregateId":1,"occurredAt":"2024-12-19T10:00:00Z","likeId":999,"memberId":"user123","productId":1,"likedAt":"2024-12-19T10:00:00Z"}
```

**3. 로그 확인**

**첫 번째 처리:**
```
[MetricsEventFacade] 이벤트 처리 완료: eventId=test-duplicate-001, type=PRODUCT_LIKED
```

**두 번째 처리 (중복):**
```
[MetricsEventFacade] 중복 이벤트 무시: eventId=test-duplicate-001, eventType=PRODUCT_LIKED
```

**4. DB 확인**
```sql
-- event_handled에 1개만 있어야 함
SELECT COUNT(*) FROM event_handled WHERE event_id = 'test-duplicate-001';
-- 결과: 1

-- product_metrics의 likes_count는 1 증가만 되어야 함
SELECT likes_count FROM product_metrics WHERE product_id = 1;
```

---

### 시나리오 3: 배치 처리 테스트

**1. 배치 메시지 발행**

```bash
# Kafka 프로듀서로 여러 메시지 발행
docker exec -it kafka kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic catalog-events \
  --property "parse.key=true" \
  --property "key.separator=:"

# 같은 productId에 대한 여러 이벤트 입력
1:{"eventId":"batch-001","eventType":"PRODUCT_LIKED","aggregateId":1,"occurredAt":"2024-12-19T10:00:00Z","likeId":1,"memberId":"user1","productId":1,"likedAt":"2024-12-19T10:00:00Z"}
1:{"eventId":"batch-002","eventType":"PRODUCT_VIEWED","aggregateId":1,"occurredAt":"2024-12-19T10:00:01Z","productId":1,"viewedAt":"2024-12-19T10:00:01Z"}
1:{"eventId":"batch-003","eventType":"PRODUCT_UNLIKED","aggregateId":1,"occurredAt":"2024-12-19T10:00:02Z","likeId":1,"memberId":"user1","productId":1,"unlikedAt":"2024-12-19T10:00:02Z"}
1:{"eventId":"batch-004","eventType":"PRODUCT_VIEWED","aggregateId":1,"occurredAt":"2024-12-19T10:00:03Z","productId":1,"viewedAt":"2024-12-19T10:00:03Z"}
```

**2. 로그 확인**

**BatchMetricsKafkaConsumer:**
```
[BatchMetricsKafkaConsumer] 배치 메시지 수신: 4개
[BatchMetricsEventFacade] 배치 이벤트 처리 시작: 4개
[BatchMetricsEventFacade] 배치 이벤트 처리 완료: 4개 (중복 제외: 0개)
[ProductMetricsService] 배치 ProductMetrics 업데이트: productId=1, eventCount=4, likes=0, views=2, sales=0
```

**3. DB 확인**
```sql
-- 4개 이벤트 모두 처리 완료
SELECT COUNT(*) FROM event_handled WHERE event_id LIKE 'batch-%';
-- 결과: 4

-- ProductMetrics 확인 (likes=0, views=2)
SELECT * FROM product_metrics WHERE product_id = 1;
```

---

### 시나리오 4: 주문 생성 (여러 상품 동시 처리)

**1. 주문 생성 API 호출**
```bash
curl -X POST http://localhost:8080/api/orders \
  -H "Content-Type: application/json" \
  -H "X-USER-ID: user123" \
  -d '{
    "orderItems": [
      {"productId": 1, "quantity": 2, "price": 10000},
      {"productId": 2, "quantity": 1, "price": 20000}
    ]
  }'
```

**2. 로그 확인**

**commerce-api:**
```
[OutboxEventPublisher] Kafka 발행 성공: eventType=ORDER_CREATED, partition=1, offset=10
```

**commerce-streamer:**
```
[MetricsEventFacade] 이벤트 처리 완료: eventId=xxx, type=ORDER_CREATED
[ProductMetricsService] ProductMetrics 업데이트: productId=1, sales=2
[ProductMetricsService] ProductMetrics 업데이트: productId=2, sales=1
```

**3. DB 확인**
```sql
-- 두 상품의 판매량 확인
SELECT product_id, sales_count FROM product_metrics WHERE product_id IN (1, 2);
```

---

### 시나리오 5: 이벤트 순서 역전 테스트

**1. 미래 이벤트 발행 → 과거 이벤트 발행**

```bash
# 1. 미래 시간 이벤트 발행
docker exec -it kafka kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic catalog-events \
  --property "parse.key=true" \
  --property "key.separator=:"

# 미래 이벤트
1:{"eventId":"future-001","eventType":"PRODUCT_LIKED","aggregateId":1,"occurredAt":"2024-12-19T12:00:00Z","likeId":100,"memberId":"user1","productId":1,"likedAt":"2024-12-19T12:00:00Z"}

# 과거 이벤트 (순서 역전)
1:{"eventId":"past-001","eventType":"PRODUCT_VIEWED","aggregateId":1,"occurredAt":"2024-12-19T11:00:00Z","productId":1,"viewedAt":"2024-12-19T11:00:00Z"}
```

**2. 로그 확인**

**미래 이벤트 처리:**
```
[ProductMetricsService] ProductMetrics 업데이트: productId=1, likes=1
```

**과거 이벤트 무시:**
```
[ProductMetricsService] 이벤트 순서 역전 무시: productId=1, eventOccurredAt=2024-12-19T11:00:00Z, metricsUpdatedAt=2024-12-19T12:00:00Z
```

**3. DB 확인**
```sql
-- product_metrics의 updated_at이 미래 시간이어야 함
SELECT product_id, updated_at, likes_count, view_count
FROM product_metrics WHERE product_id = 1;
```

---

## 🔍 모니터링 & 디버깅

### Kafka UI 접속
```
http://localhost:9099
```

### 토픽 메시지 확인
```bash
# catalog-events 토픽 메시지 조회
docker exec -it kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic catalog-events \
  --from-beginning \
  --property print.key=true \
  --property key.separator=":"
```

### Consumer Lag 확인
```bash
docker exec -it kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe \
  --group metrics-consumer-group
```

### Dead Letter Queue 확인
```sql
-- DLQ에 저장된 실패 이벤트 확인
SELECT * FROM dead_letter_queue ORDER BY failed_at DESC LIMIT 10;
```

---

## 🧪 통합 테스트 스크립트

### 전체 흐름 자동 테스트

**파일**: `test-kafka-pipeline.sh`

```bash
#!/bin/bash

echo "=== Round 8 Kafka 파이프라인 테스트 ==="

# 1. 좋아요 추가
echo "\n[1] 상품 좋아요 추가..."
curl -s -X POST http://localhost:8080/api/products/1/likes \
  -H "Content-Type: application/json" \
  -H "X-USER-ID: user123"
sleep 2

# 2. DB 확인
echo "\n[2] ProductMetrics 확인..."
docker exec -i mysql-container mysql -u root -ppassword commerce_streamer \
  -e "SELECT product_id, likes_count, view_count, sales_count FROM product_metrics WHERE product_id = 1;"

# 3. 멱등성 확인
echo "\n[3] 중복 이벤트 발행 (멱등성 테스트)..."
# Kafka에 직접 발행 (같은 eventId)

# 4. 배치 처리 확인
echo "\n[4] 배치 이벤트 발행..."
# Kafka에 여러 메시지 발행

echo "\n=== 테스트 완료 ==="
```

---

## 🎯 성공 기준

### 1. 단건 처리 성공
- ✅ 이벤트가 Kafka로 발행됨
- ✅ Consumer가 메시지 수신
- ✅ ProductMetrics 업데이트됨
- ✅ EventHandled에 기록됨

### 2. 멱등성 보장
- ✅ 중복 이벤트 무시됨
- ✅ DB에 1번만 반영됨

### 3. 배치 처리 성공
- ✅ 여러 메시지를 한 번에 처리
- ✅ 트랜잭션 1회로 처리

### 4. 이벤트 순서 보장
- ✅ occurredAt 기준으로 역전 이벤트 무시

### 5. DLQ 동작
- ✅ 3회 재시도 후 DLQ로 이동
- ✅ EventOutbox에서 processed=true 처리

---

## 🐛 트러블슈팅

### 문제 1: Consumer가 메시지를 받지 못함

**원인:**
- Kafka 연결 실패
- 토픽이 생성되지 않음
- Consumer Group Offset 문제

**해결:**
```bash
# Kafka 상태 확인
docker-compose -f ./docker/infra-compose.yml ps

# 토픽 확인
docker exec -it kafka kafka-topics.sh --list \
  --bootstrap-server localhost:9092

# Consumer Group Offset 리셋
docker exec -it kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group metrics-consumer-group \
  --reset-offsets \
  --to-earliest \
  --topic catalog-events \
  --execute
```

### 문제 2: 중복 이벤트가 처리됨

**원인:**
- EventHandled 테이블 인덱스 없음
- 멱등성 체크 로직 누락

**해결:**
```sql
-- 인덱스 확인
SHOW INDEX FROM event_handled;

-- 없으면 생성
CREATE UNIQUE INDEX idx_event_handled_event_id ON event_handled(event_id);
```

### 문제 3: 배치 Consumer가 동작하지 않음

**원인:**
- `batchKafkaListenerContainerFactory` Bean 없음
- `isBatchListener = true` 설정 누락

**해결:**
- [KafkaConsumerConfig.kt](apps/commerce-streamer/src/main/kotlin/com/loopers/config/KafkaConsumerConfig.kt:42) 확인

---

## 📈 성능 측정

### 처리량 테스트

```bash
# 1000개 이벤트 발행
for i in {1..1000}; do
  curl -X POST http://localhost:8080/api/products/1/likes \
    -H "X-USER-ID: user$i" &
done

# Consumer Lag 확인
docker exec -it <kafka-container-id> kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --describe \
  --group metrics-consumer-group
```

### 예상 결과

**단건 처리:**
- 처리량: 약 100-200 TPS
- 트랜잭션: 1000회

**배치 처리:**
- 처리량: 약 1000-5000 TPS
- 트랜잭션: 10-50회

---

## ✅ 최종 체크리스트

- [ ] 인프라 실행 중 (`docker-compose -f ./docker/infra-compose.yml up -d`)
- [ ] Kafka 실행 중 (KRaft 모드, Zookeeper 불필요)
- [ ] 토픽 생성 완료 (catalog-events, order-events)
- [ ] Kafka UI 접속 확인 (`http://localhost:9099`)
- [ ] commerce-api 실행 중
- [ ] commerce-streamer 실행 중
- [ ] 단건 처리 테스트 성공
- [ ] 멱등성 테스트 성공
- [ ] 배치 처리 테스트 성공
- [ ] 이벤트 순서 보장 테스트 성공
- [ ] DB 데이터 확인 완료
