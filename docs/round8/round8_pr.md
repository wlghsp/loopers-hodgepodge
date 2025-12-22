## 📌 Summary

Kafka 기반 이벤트 파이프라인을 구현하여 **Exactly Once Semantics**를 보장합니다. `commerce-api`에서 발생하는 도메인 이벤트를 Transactional Outbox Pattern으로 Kafka에 발행하고, `commerce-streamer`에서 수신하여 상품 메트릭스(좋아요 수, 조회 수, 판매량)를 집계합니다.

**핵심 달성 목표:**
- **Exactly Once Semantics**: At Least Once Producer + At Most Once Consumer = 정확히 1회 처리
- **이벤트 순서 보장**: aggregateId 기반 파티션 키로 같은 엔티티의 이벤트 순서 유지
- **장애 복구**: Dead Letter Queue와 재시도 메커니즘으로 메시지 유실 방지
- **캐시 일관성**: 재고 소진 시 자동 캐시 무효화

**주요 구현 사항:**
- Transactional Outbox Pattern + 스케줄러 폴링으로 At Least Once Producer 보장
- `event_handled` 테이블 기반 멱등 처리로 At Most Once Consumer 구현
- PartitionKey를 `aggregateId`로 설정하여 이벤트 순서 보장
- Dead Letter Queue로 실패 이벤트 처리
- Consumer Group 분리로 장애 격리 (metrics / cache-invalidation)

## 💬 Review Points

### 1. PartitionKey를 aggregateId로 설정

**문제**: Kafka는 파티션 내에서만 순서 보장 → 같은 상품의 이벤트가 다른 파티션으로 가면 순서 뒤바뀜

**해결**: partitionKey = `aggregateId`로 설정하여 같은 상품의 모든 이벤트가 같은 파티션으로 가도록 함

**추가**: Consumer에서 `updatedAt`과 `eventOccurredAt` 비교로 순서 역전 체크

### 2. Exactly Once Semantics를 위한 테이블 분리 전략

**최종 목표**: 메시지를 정확히 한 번만 처리

**공식**: `At Least Once Producer + At Most Once Consumer = Exactly Once`

#### EventOutbox 테이블 (Producer: At Least Once)

**목적**: Kafka 전송 실패해도 재전송할 수 있도록 전송 이력을 DB에 저장

| 항목 | 설명 |
|------|------|
| **역할** | Producer의 전송 보장 |
| **소유** | commerce-api |
| **생명주기** | 전송 후 7일 뒤 삭제 |
| **인덱스** | (processed, created_at) - 미전송 이벤트 조회용 |
| **조회 패턴** | 스케줄러가 `processed=false` 배치 조회 |

#### EventHandled 테이블 (Consumer: At Most Once)

**목적**: 중복 메시지 수신해도 한 번만 처리하도록 처리 이력을 DB에 저장

| 항목 | 설명 |
|------|------|
| **역할** | Consumer의 중복 처리 방지 (멱등성) |
| **소유** | commerce-streamer |
| **생명주기** | 처리 후 30일 뒤 삭제 |
| **인덱스** | event_id (PK) - 중복 체크용 |
| **조회 패턴** | 메시지 수신마다 `event_id` 단건 조회 |

#### 왜 분리했나?

1. **서비스 독립성**: Producer와 Consumer가 다른 DB/서비스에 배포 가능
2. **성능 최적화**: 각자의 조회 패턴에 맞는 인덱스 설계
3. **생명주기 관리**: 전송 로그(7일)와 처리 로그(30일)를 다른 주기로 정리
4. **책임 분리**: Outbox는 "전송", Handled는 "처리" 책임만 가짐

### 3. 스케줄러 폴링 방식으로 Dual Write 문제 해결

**Dual Write 문제란?**
- DB 트랜잭션 커밋과 Kafka 전송이 원자적으로 처리되지 않아 불일치 발생 가능
- BEFORE_COMMIT으로 Kafka를 먼저 보내면 커밋 실패 시 메시지만 전송되는 문제

**해결 방법: 스케줄러 폴링 (현재 구현)**

```
1. 비즈니스 트랜잭션 (원자적)
   - 비즈니스 로직 실행
   - EventOutbox 저장 (같은 트랜잭션)
   - 커밋 ✅

2. 백그라운드 스케줄러 (1초마다)
   - EventOutbox에서 processed=false 조회
   - Kafka 전송 시도
   - 성공 시 processed=true 업데이트
   - 실패 시 재시도 (최대 3회)
```

**장점:**
- ✅ 비즈니스 데이터와 EventOutbox가 하나의 트랜잭션으로 원자성 보장
- ✅ Kafka 장애가 비즈니스 트랜잭션에 영향 없음
- ✅ 자동 재시도로 일시적 장애 복구
- ✅ 모든 이벤트가 EventOutbox에 먼저 기록되어 추적 가능

**트레이드오프:**
- ⏱️ 최대 1초 지연 (실시간성 요구사항에 따라 조정 가능)

### 4. Dead Letter Queue 및 재시도 전략

**목적**: 영구적 실패 이벤트를 별도로 관리하여 메시지 유실 방지

**재시도 전략:**

```
Kafka 전송 실패
  ↓
재시도 1회 (스케줄러)
  ↓ 실패
재시도 2회 (스케줄러)
  ↓ 실패
재시도 3회 (스케줄러)
  ↓ 실패
DeadLetterQueue로 이동
  ↓
수동 재처리 API 제공
```

**DLQ 개선 사항 (코드 리뷰 반영):**
- ✅ aggregateId 필드 추가하여 파티션 키 일관성 유지
- ✅ 재시도 시 aggregateId를 파티션 키로 사용 (이벤트 순서 보장)
- ✅ DLQ 이동 실패 시 예외 처리 추가

**효과**:
- 일시적 장애는 자동 복구 (네트워크 끊김, Kafka 일시 중단 등)
- 지속적 실패는 DLQ로 격리 후 수동 확인
- 이벤트 유실 완전 방지

### 5. Consumer 트랜잭션 경계 최적화 (코드 리뷰 반영)

**문제점**: Consumer 메서드에 @Transactional을 붙이면 ACK 타이밍 문제 발생 가능

```kotlin
// ❌ 잘못된 방식
@Transactional
fun consume(message: String, ack: Acknowledgment) {
    handleEvent(event)  // DB 저장
    ack.acknowledge()   // ACK는 트랜잭션 내부
    // 트랜잭션 커밋 전에 ACK 전송 → 커밋 실패 시 메시지 유실
}
```

**개선 방법**: @Transactional을 Facade로 이동

```kotlin
// ✅ 올바른 방식
// Consumer: @Transactional 없음
fun consume(message: String, ack: Acknowledgment) {
    facade.handleEvent(event)  // Facade가 트랜잭션 관리
    ack.acknowledge()           // 트랜잭션 커밋 후 ACK
}

// Facade: @Transactional 있음
@Transactional
fun handleEvent(event: DomainEvent) {
    // DB 저장 (event_handled + metrics)
    // 커밋
}
```

**효과**: 트랜잭션 커밋 완료 후 ACK 전송으로 메시지 유실 방지

---

### 6. Race Condition 해결 (코드 리뷰 반영)

**문제점**: 중복 체크와 저장 사이에 경쟁 조건 발생 가능

```kotlin
// ❌ 잘못된 방식
if (isAlreadyHandled(event)) return  // 1. 체크
processEvent(event)                   // 2. 처리
markAsHandled(event)                  // 3. 저장
// → 두 스레드가 동시에 1번 통과 → 중복 처리
```

**개선 방법**: DB 유니크 제약 활용

```kotlin
// ✅ 올바른 방식
try {
    markAsHandled(event)  // 1. 먼저 저장 (eventId는 PK)
} catch (DataIntegrityViolationException e) {
    return  // 중복이면 무시
}
processEvent(event)  // 2. 처리
```

**효과**: DB의 유니크 제약으로 동시성 이슈 완전 해결

---

## ✅ Checklist

### Must-Have 요구사항
- [x] 도메인 이벤트 설계 (DomainEvent 인터페이스)
- [x] Producer에서 도메인 이벤트 발행 (catalog-events, order-events)
- [x] Consumer가 Metrics 집계 처리 (ProductMetrics)
- [x] PartitionKey 기반의 이벤트 순서 보장 (aggregateId 사용)
- [x] `event_handled` 테이블을 통한 멱등 처리 구현
- [x] Manual ACK 처리
- [x] 메시지 발행 실패 시 처리 (재시도 및 DLQ)
- [x] Transactional Outbox Pattern 구현 (스케줄러 폴링)
- [x] 재고 소진 시 캐시 무효화 (Consumer Group 분리)

### 코드 리뷰 반영 사항
- [x] 토픽 이름 일관성 수정 (catalog-event → catalog-events)
- [x] DLQ aggregateId 추가 및 파티션 키 수정
- [x] DLQ 이동 실패 시 예외 처리
- [x] Consumer @Transactional 제거 및 Facade로 이동
- [x] Race Condition 해결 (DB 유니크 제약 활용)
- [x] Redis KEYS → SCAN 명령어 변경
- [x] 비대상 이벤트 무한 재시도 방지
- [x] EventHandled에 occurredAt 필드 추가

### 추가 구현
- [x] Dead Letter Queue 구현
- [x] EventOutbox Cleanup 스케줄러 (7일 이상 된 이벤트 삭제)
- [x] 이벤트 순서 보장 테스트
- [x] Consumer Group 분리 (metrics / cache-invalidation)
