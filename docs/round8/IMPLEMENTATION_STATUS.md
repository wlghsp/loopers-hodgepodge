# Round 8 구현 상태 체크리스트

> 최종 업데이트: 2024-12-19
> Git 브랜치: round8

## 📊 전체 진행률

```
Phase 1 (도메인 이벤트): ████████████████████ 100% (완료)
Phase 2 (EventOutbox):   ████████████████████ 100% (완료)
Phase 3 (Kafka Producer): ████████████████████ 100% (완료)
Phase 4 (Kafka Consumer): ████░░░░░░░░░░░░░░░░  20% (진행 중)
Phase 5 (Docker):         ░░░░░░░░░░░░░░░░░░░░   0% (대기)

전체: ████████████░░░░░░░░ 64%
```

---

## ✅ Phase 1: 도메인 이벤트 표준화 (100%)

### 1.1: DomainEvent 인터페이스
- [x] `DomainEvent.kt` 생성 (AM)
- [x] `eventId`, `eventType`, `aggregateId`, `occurredAt` 필드 정의
- [x] 모든 이벤트가 인터페이스 구현

### 1.2: AggregateType 매핑 전략
- [x] `AggregateType.kt` Enum 생성 (AM)
- [x] `PRODUCT`, `ORDER` 타입 정의
- [x] 실제 구현: String 타입 + when 분기 방식 (문서와 다름)

### 1.3: 기존 이벤트 수정
- [x] `ProductLikedEvent` - DomainEvent 구현
- [x] `ProductUnlikedEvent` - DomainEvent 구현
- [x] `ProductViewedEvent` - DomainEvent 구현
- [x] `OrderCreatedEvent` - DomainEvent 구현
- [x] `PaymentCompletedEvent` - DomainEvent 구현
- [x] `PaymentFailedEvent` - DomainEvent 구현

### 1.4: 신규 이벤트 추가
- [x] `StockDecreasedEvent.kt` 생성 (AM)
- [x] `CouponUsedEvent.kt` 생성 (AM)

### 1.5: 기존 핸들러 삭제
- [x] `ProductLikeEventHandler.kt` 삭제 (D)
- [x] `ProductLikeEventProcessor.kt` 삭제 (예상)
- [x] `OrderEventHandler.kt` 삭제 (D)
- [x] `DataPlatformEventHandler.kt` 삭제 (D)
- [x] `UserActionEventHandler.kt` 삭제 (D)
- [x] `UserActionTrackingEventHandler.kt` 삭제 (D)

**Phase 1 상태:** ✅ **완료**

---

## ✅ Phase 2: EventOutbox 인프라 구축 (100%)

### 2.1: EventOutbox 엔티티
- [x] `EventOutbox.kt` 생성 (AM)
- [x] `aggregateType` 필드 추가 (String 타입)
- [x] `processed`, `processedAt` 필드 추가
- [x] `payload` 필드 추가 (JSON)

### 2.2: EventOutbox Repository
- [x] `EventOutboxJpaRepository.kt` 생성 (AM)
- [x] `findTop100ByProcessedFalseOrderByCreatedAtAsc()` 쿼리 메서드
- [x] `deleteByProcessedTrueAndCreatedAtBefore()` 쿼리 메서드

### 2.3: Outbox 이벤트 리스너
- [x] `OutboxEventListener.kt` 생성 (AM)
- [x] `@TransactionalEventListener(BEFORE_COMMIT)` 설정
- [x] `getAggregateType()` when 분기 구현 (Enum 대신)
- [x] EventOutbox 저장 로직

**Phase 2 상태:** ✅ **완료**

---

## ✅ Phase 3: Kafka Producer 설정 (100%)

### 3.1: Kafka 의존성 및 설정
- [x] `build.gradle.kts` - Kafka 의존성 추가 (M)
- [x] `application.yml` - Kafka Producer 설정 (M)
  - [x] `bootstrap-servers`
  - [x] `acks: all`
  - [x] `enable.idempotence: true`
  - [x] `topics` 정의

### 3.2: KafkaProducerConfig
- [x] `KafkaProducerConfig.kt` 생성 (AM)
- [x] `ProducerFactory` 빈 설정
- [x] `KafkaTemplate` 빈 설정
- [x] `@EnableScheduling` 추가

### 3.3: OutboxEventPublisher
- [x] `OutboxEventPublisher.kt` 생성 (AM)
- [x] `@Scheduled(fixedDelay = 1000)` 설정
- [x] Kafka 발행 로직
- [x] `processed = true` 업데이트
- [x] PartitionKey = aggregateId 설정

### 3.4: EventOutboxCleanupScheduler
- [x] `EventOutboxCleanupScheduler.kt` 생성 (AM)
- [x] 7일 이상 된 processed=true 이벤트 삭제
- [x] 스케줄러 설정 (매일 새벽 3시)

### 3.5: Dead Letter Queue
- [x] `DeadLetterQueue.kt` 엔티티 생성 (AM)
- [x] `DeadLetterQueueRepository.kt` 생성 (AM)
- [x] `DeadLetterQueueService.kt` 생성 (AM)
- [x] BaseEntity 상속 (id 필드 중복 제거)
- [x] CoreException 사용

### 3.6: Graceful Shutdown
- [x] `CoroutineConfig.kt` 수정 (M)
- [x] `@PreDestroy` shutdown 로직
- [x] `application.yml` - `timeout-per-shutdown-phase: 30s`

**Phase 3 상태:** ✅ **완료**

---

## 🚧 Phase 4: Kafka Consumer 구현 (20%)

### 4.1: commerce-streamer 설정
- [x] `application.yml` - Kafka Consumer 설정 (M)
  - [x] `bootstrap-servers`
  - [x] `group-id: metrics-consumer-group`
  - [x] `enable-auto-commit: false`
  - [x] `auto-offset-reset: earliest`
- [x] `datasource.url` - commerce_streamer DB 설정

### 4.2: EventHandled 테이블 (멱등성)
- [ ] `EventHandled.kt` 엔티티 생성
- [ ] `EventHandledRepository.kt` 생성
- [ ] `existsByEventId()` 쿼리 메서드
- [ ] Index: `idx_event_id` (unique)

### 4.3: ProductMetrics 테이블
- [ ] `ProductMetrics.kt` 엔티티 생성
- [ ] `likesCount`, `viewCount`, `salesCount` 필드
- [ ] `@Version` 낙관적 락
- [ ] `updatedAt` - 이벤트 순서 보장용
- [ ] `ProductMetricsRepository.kt` 생성
- [ ] `findByProductId()` 쿼리 메서드

### 4.4: KafkaConsumerConfig
- [ ] `KafkaConsumerConfig.kt` 생성
- [ ] `ConsumerFactory` 빈 설정
- [ ] `ConcurrentKafkaListenerContainerFactory` 설정
- [ ] Manual ACK 설정

### 4.5: Consumer 계층 구현

#### 옵션 1: 단일 클래스 (현재 진행 중)
- [ ] `MetricsEventConsumer.kt` 구현
  - [ ] `@KafkaListener` 메서드
  - [ ] `parseEvent()` - JSON → DomainEvent
  - [ ] 멱등성 체크
  - [ ] 이벤트 타입별 라우팅
  - [ ] ProductMetrics 업데이트
  - [ ] Manual ACK

#### 옵션 2: 계층 분리 (CONSUMER_REFACTORED.md 참조)
- [ ] `MetricsKafkaConsumer.kt` (Interfaces Layer)
- [ ] `MetricsEventFacade.kt` (Application Layer)
- [ ] `ProductMetricsService.kt` (Domain Layer)
- [ ] `EventHandledRepository.kt` (Infrastructure Layer)

### 4.6: 테이블 분리 이유 (문서 참조)
- ✅ 설계 문서 작성 완료

### 4.7: 배치 처리 고민 (문서 참조)
- ✅ 설계 문서 작성 완료

**Phase 4 상태:** 🚧 **20% 완료** (설정만 완료, 구현 대기)

---

## ⏳ Phase 5: Docker Compose 환경 구축 (0%)

### 5.1: Kafka & Zookeeper
- [ ] `docker-compose.yml` 생성
- [ ] Kafka 서비스 정의
- [ ] Zookeeper 서비스 정의
- [ ] 네트워크 설정

### 5.2: MySQL
- [ ] commerce-api DB 설정
- [ ] commerce-streamer DB 설정

### 5.3: Redis (기존)
- [ ] Redis 설정 확인

**Phase 5 상태:** ⏳ **0% 완료** (대기)

---

## 📋 Git Status 요약 (2024-12-19 기준)

### Modified (M)
```
M apps/commerce-api/build.gradle.kts
M apps/commerce-api/src/main/resources/application.yml
M apps/commerce-streamer/src/main/resources/application.yml
M apps/commerce-api/src/main/kotlin/com/loopers/config/CoroutineConfig.kt
M apps/commerce-api/src/main/kotlin/com/loopers/domain/coupon/Coupon.kt
M apps/commerce-api/src/main/kotlin/com/loopers/domain/coupon/CouponService.kt
M apps/commerce-api/src/main/kotlin/com/loopers/domain/like/LikeService.kt
M apps/commerce-api/src/main/kotlin/com/loopers/domain/order/Order.kt
M apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderService.kt
M apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackService.kt
M apps/commerce-api/src/main/kotlin/com/loopers/domain/like/event/ProductLikedEvent.kt
M apps/commerce-api/src/main/kotlin/com/loopers/domain/like/event/ProductUnlikedEvent.kt
M apps/commerce-api/src/main/kotlin/com/loopers/domain/order/event/OrderCreatedEvent.kt
M apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/event/PaymentCompletedEvent.kt
M apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/event/PaymentFailedEvent.kt
M apps/commerce-api/src/main/kotlin/com/loopers/domain/product/event/ProductViewedEvent.kt
```

### Added (AM)
```
AM apps/commerce-api/src/main/kotlin/com/loopers/config/KafkaProducerConfig.kt
AM apps/commerce-api/src/main/kotlin/com/loopers/domain/coupon/event/CouponUsedEvent.kt
AM apps/commerce-api/src/main/kotlin/com/loopers/domain/event/AggregateType.kt
AM apps/commerce-api/src/main/kotlin/com/loopers/domain/event/DeadLetterQueue.kt
AM apps/commerce-api/src/main/kotlin/com/loopers/domain/event/DomainEvent.kt
AM apps/commerce-api/src/main/kotlin/com/loopers/domain/event/EventOutbox.kt
AM apps/commerce-api/src/main/kotlin/com/loopers/domain/product/event/StockDecreasedEvent.kt
AM apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/DeadLetterQueueRepository.kt
AM apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/DeadLetterQueueService.kt
AM apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/EventOutboxCleanupScheduler.kt
AM apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/EventOutboxJpaRepository.kt
AM apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/OutboxEventListener.kt
AM apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/OutboxEventPublisher.kt
```

### Deleted (D)
```
D apps/commerce-api/src/main/kotlin/com/loopers/application/order/OrderEventHandler.kt
D apps/commerce-api/src/main/kotlin/com/loopers/domain/like/event/ProductLikeEventHandler.kt
D apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/DataPlatformEventHandler.kt
D apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/UserActionEventHandler.kt
D apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/UserActionTrackingEventHandler.kt
```

---

## 🔍 검증 필요 항목

### 1. OrderCreatedEvent.orderItems
**위치:** `apps/commerce-api/src/main/kotlin/com/loopers/domain/order/event/OrderCreatedEvent.kt`

**확인 사항:**
- [ ] `orderItems` 필드 존재 여부
- [ ] `orderItems`에 `productId`, `quantity` 포함 여부
- [ ] Consumer에서 `event.orderItems.forEach { ... }` 동작 가능 여부

### 2. PaymentEvent aggregateId
**확인 필요:**
- [ ] `PaymentCompletedEvent.aggregateId` - 주문 ID인지 결제 ID인지
- [ ] `PaymentFailedEvent.aggregateId` - 주문 ID인지 결제 ID인지

### 3. AggregateType 구현 방식
**문서 vs 실제:**
- 문서: `AggregateType` Enum 사용
- 실제: `String` + when 분기

**확인 필요:**
- [ ] `EventOutbox.aggregateType` 타입 확인
- [ ] `OutboxEventListener.getAggregateType()` 반환 타입 확인
- [ ] `OutboxEventPublisher` Topic 매핑 방식 확인

---

## 📝 다음 작업 (우선순위)

### 🔴 1순위 (필수)
1. **Consumer 엔티티 구현**
   - `EventHandled.kt`
   - `ProductMetrics.kt`
   - 각 Repository

2. **Consumer 서비스 구현**
   - 옵션 1: `MetricsEventConsumer.kt` 단일 클래스
   - 옵션 2: Facade Pattern 계층 분리

3. **KafkaConsumerConfig 구현**
   - Manual ACK 설정
   - 에러 핸들링

### 🟡 2순위 (권장)
4. **통합 테스트**
   - Producer → Kafka → Consumer 전체 흐름
   - 멱등성 테스트
   - 이벤트 순서 보장 테스트

5. **Docker Compose 환경**
   - Kafka, Zookeeper
   - MySQL (2개 DB)
   - Redis

### 🟢 3순위 (선택)
6. **모니터링**
   - Kafka Lag 체크
   - DLQ 모니터링
   - EventOutbox 처리량

7. **성능 최적화**
   - Batch Size 조정
   - 인덱스 최적화
   - Cleanup 주기 조정

---

## 💡 주요 변경 사항 (문서 vs 실제)

### 1. AggregateType 구현 방식
- **문서:** Enum의 `fromEventType()` static 메서드
- **실제:** when 분기로 이벤트 인스턴스 타입 체크
- **영향:** 기능적으로 동일, 실제 구현이 더 타입 안전

### 2. EventOutbox.aggregateType 타입
- **문서:** `AggregateType` Enum
- **실제:** `String`
- **영향:** Topic 매핑 시 when 분기 사용

### 3. OutboxEventPublisher Topic 매핑
- **문서:** `outbox.aggregateType.topic` (Enum 프로퍼티)
- **실제:** when 분기로 String 비교
- **영향:** aggregateType이 String이므로 불가피

### 4. Consumer 패키지 구조
- **문서:** `interfaces/consumer/`
- **실제:** `infrastructure/event/` (예상)
- **영향:** 프로젝트 패키지 표준 따름

---

## ✅ 완료 기준

### Phase 4 완료 조건
- [ ] EventHandled, ProductMetrics 엔티티 생성
- [ ] Repository 생성 및 쿼리 메서드 구현
- [ ] KafkaConsumerConfig 설정 완료
- [ ] Consumer 구현 (옵션 1 또는 2)
- [ ] 로컬 테스트 통과

### Phase 5 완료 조건
- [ ] docker-compose.yml 작성
- [ ] Kafka, Zookeeper 실행 확인
- [ ] 양방향 통신 확인 (Producer → Consumer)

### Round 8 전체 완료 조건
- [ ] 모든 Phase 구현 완료
- [ ] 통합 테스트 통과
- [ ] 문서 최종 검토
- [ ] PR 생성 및 리뷰 요청

---

**마지막 업데이트:** 2024-12-19
**다음 검토:** Phase 4 구현 완료 후
