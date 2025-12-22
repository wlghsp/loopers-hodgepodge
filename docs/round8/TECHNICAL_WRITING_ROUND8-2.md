# 메시지를 정확히 한 번만 처리하려면?

**TL;DR**: 좋아요 1번 눌렀으면 좋아요 수는 정확히 +1이 되어야 한다. 네트워크 장애로 메시지가 2번 전송되어도, Kafka가 다운되어 메시지가 유실되어도 말이다. 이를 위해 "전송 보장용 테이블"과 "중복 방지용 테이블" 두 개를 분리했다.

---

## 문제 상황: 메시지가 유실되거나 중복 처리될 수 있다

Kafka 이벤트 파이프라인을 만들면서 가장 먼저 마주친 문제는 이것이었다:

**"사용자가 좋아요를 눌렀는데, 좋아요 수가 증가하지 않으면 어떡하지?"**
**"네트워크 장애로 메시지가 2번 전송되면, 좋아요 수가 2 증가할 수도 있지 않을까?"**

이런 일이 생기면 안 된다. **좋아요 1번 = 좋아요 수 +1**이어야 한다. 정확히 1번만 처리되어야 한다.

## 목표: Exactly Once Semantics

**최종 목표**: 메시지를 정확히 한 번만 처리한다.

하지만 분산 시스템에서 "정확히 1번"은 어렵다. 네트워크는 끊길 수 있고, Kafka는 다운될 수 있고, 애플리케이션은 재시작될 수 있다.

그래서 다른 방식으로 접근했다:

```
At Least Once Producer (최소 1회 전송)
+
At Most Once Consumer (최대 1회 처리)
=
Exactly Once Semantics (정확히 1회)
```

**Producer가 메시지를 잃어버리지 않고**, **Consumer가 중복 처리하지 않으면**, 결과적으로 정확히 1번 처리된다.

## 해결 방법 1: Producer는 EventOutbox로 "최소 1회 전송" 보장

**질문**: Kafka 전송이 실패하면 어떻게 하지?

**답**: 실패해도 재전송할 수 있도록 **DB에 먼저 저장**한다.

```kotlin
// 1. 비즈니스 로직과 함께 EventOutbox 저장 (같은 트랜잭션)
@Transactional
fun createLike() {
    likeRepository.save(like)
    eventOutboxRepository.save(outbox)  // 같이 커밋됨
}

// 2. 스케줄러가 미전송 이벤트를 조회해서 Kafka로 전송
@Scheduled(fixedDelay = 1000)
fun publishPendingEvents() {
    val pending = eventOutboxRepository.findByProcessedFalse()
    pending.forEach { outbox ->
        kafkaTemplate.send(topic, outbox.payload)
        outbox.processed = true  // 전송 성공 표시
    }
}
```

**효과**: Kafka가 다운되어도 EventOutbox에 저장되어 있으므로 나중에 재전송할 수 있다. **메시지 유실 방지**.

## 해결 방법 2: Consumer는 EventHandled로 "최대 1회 처리" 보장

**질문**: 같은 메시지가 2번 들어오면 어떻게 하지?

**답**: 이미 처리했는지 **DB에 기록**한다.

```kotlin
@KafkaListener(topics = ["catalog-events"])
fun consume(message: String) {
    val event = parseEvent(message)

    // 1. 이미 처리했는지 확인
    if (eventHandledRepository.existsByEventId(event.eventId)) {
        return  // 이미 처리함 → 무시
    }

    // 2. 비즈니스 로직 처리
    productMetricsService.incrementLikes(event.productId)

    // 3. 처리 완료 기록
    eventHandledRepository.save(EventHandled(event.eventId))
}
```

**효과**: Producer가 메시지를 2번 보내도 Consumer는 1번만 처리한다. **중복 처리 방지**.

## 그런데 왜 테이블을 두 개로 나눴을까?

처음엔 하나의 테이블에 다 저장하면 되지 않을까 생각했다. Producer에서 이벤트를 저장하고, Consumer에서도 같은 테이블을 조회해서 멱등성 체크를 하면 되니까.

하지만 구현을 진행하면서 문제가 생겼다.

## 문제 1: 생명주기가 달랐다

Producer 쪽에서는 이벤트를 Kafka로 발행한 후 더 이상 필요 없다. 발행 완료된 이벤트는 7일 후 삭제하는 정책을 세웠다.

```kotlin
// EventOutboxCleanupScheduler.kt
@Scheduled(cron = "0 0 3 * * ?")
fun cleanupProcessedEvents() {
    val cutoffDate = Instant.now().minus(7, ChronoUnit.DAYS)
    eventOutboxRepository.deleteByProcessedTrueAndCreatedAtBefore(cutoffDate)
}
```

반면 Consumer 쪽에서는 멱등성 보장을 위해 처리한 이벤트를 영구 보관해야 한다. 같은 이벤트가 다시 들어와도 이미 처리했다는 것을 증명해야 하니까.

만약 하나의 테이블을 썼다면? Producer는 발행 완료 후 삭제하고 싶은데, Consumer는 영구 보관해야 한다. 정책이 충돌한다.

## 문제 2: 서비스가 분리되어 있었다

`commerce-api`(Producer)와 `commerce-streamer`(Consumer)는 완전히 다른 서비스다. 각각 다른 DB를 사용하고, 독립적으로 스케일링된다.

```kotlin
// commerce-api의 EventOutbox
@Entity
@Table(name = "event_outbox")
class EventOutbox(...) // commerce_api DB에 저장

// commerce-streamer의 EventHandled  
@Entity
@Table(name = "event_handled")
class EventHandled(...) // commerce_streamer DB에 저장
```

하나의 테이블을 공유하려면 두 서비스가 같은 DB에 접근해야 한다. 이건 마이크로서비스 아키텍처 원칙에 맞지 않는다. 서비스 간 결합도가 높아지고, 한쪽 DB 장애가 다른 쪽에 전파된다.

## 문제 3: 인덱스 전략이 달랐다

EventOutbox는 `processed, created_at` 인덱스가 필요하다. 스케줄러가 미처리 이벤트를 조회할 때 사용한다.

```kotlin
@Table(
    indexes = [
        Index(name = "idx_event_outbox_processed", columnList = "processed, created_at")
    ]
)
```

EventHandled는 `eventId`만 인덱스로 충분하다. 멱등성 체크는 `eventId`로만 조회하면 되니까.

```kotlin
@Table(
    indexes = [
        Index(name = "idx_event_handled_event_id", columnList = "eventId", unique = true)
    ]
)
```

하나의 테이블에 두 인덱스를 모두 만들면? 불필요한 인덱스가 생기고, 쓰기 성능이 떨어진다.

## 문제 4: 동시 접근 이슈

Producer는 1초마다 스케줄러가 `processed=false`인 이벤트를 조회하고 업데이트한다. Consumer는 메시지를 받을 때마다 `eventId`로 조회하고 삽입한다.

같은 테이블을 두 서비스가 동시에 접근하면? 락 경합이 발생할 수 있다. 특히 Producer가 대량의 이벤트를 `processed=true`로 업데이트할 때 Consumer의 조회가 느려질 수 있다.

## 그래서 분리했다

결국 EventOutbox와 EventHandled를 완전히 분리했다.

| 구분 | EventOutbox | EventHandled |
|------|-------------|--------------|
| **소유 서비스** | commerce-api | commerce-streamer |
| **목적** | 발행 보장 (At Least Once) | 멱등성 보장 (At Most Once) |
| **생명주기** | 발행 후 7일 삭제 | 영구 보관 |
| **인덱스** | processed, created_at | eventId (PK) |
| **조회 패턴** | 스케줄러가 배치 조회 | 메시지마다 개별 조회 |

## 분리 후 얻은 것들

**독립적인 스케일링**: commerce-api와 commerce-streamer가 각자의 DB를 사용하므로 독립적으로 스케일링할 수 있다.

**명확한 책임 분리**: EventOutbox는 "발행했는가?", EventHandled는 "처리했는가?"라는 단일 책임만 가진다.

**성능 최적화**: 각 테이블의 사용 패턴에 맞는 인덱스만 생성할 수 있다.

**장애 격리**: 한쪽 DB 장애가 다른 쪽에 영향을 주지 않는다.

## 아직 고민 중인 부분

EventHandled를 영구 보관하는 게 맞는지 아직 확신이 서지 않는다. 시간이 지나면서 테이블이 커질 텐데, 멱등성 체크는 최근 이벤트만 확인해도 충분할 수도 있다. 

다만 지금은 안전하게 영구 보관으로 가고 있다. 나중에 데이터가 쌓이면 TTL을 두거나 아카이빙 전략을 고민해야 할 것 같다.

## 마무리

처음엔 단순하게 하나의 테이블로 해결하려고 했지만, 실제 구현하면서 생명주기와 책임이 다르다는 걸 깨달았다. 분리하니 각자의 목적에 맞게 최적화할 수 있게 되었고, 서비스 간 결합도도 낮아졌다.

이벤트 파이프라인을 설계할 때는 "어디서 사용하는가", "언제까지 보관하는가"를 먼저 생각해보는 게 중요하다는 걸 배웠다.

