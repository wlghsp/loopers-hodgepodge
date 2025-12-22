# 코드 리뷰 답변

## 1. BEFORE_COMMIT과 Dual Write 문제

### 질문
> BEFORE_COMMIT 선택: 비즈니스 로직과 EventOutbox 저장을 같은 트랜잭션에서 처리하여 일관성 보장. 이 문제를 Dual write 라고 하는데요. 이 부분에 대한 문제점은 없을까요?

### 답변

좋은 지적 감사합니다! **현재 구현은 BEFORE_COMMIT을 사용하지 않습니다.** 대신 **스케줄러 기반 폴링 방식**을 사용하여 Dual Write 문제를 완전히 해결했습니다.

#### BEFORE_COMMIT의 문제점

만약 `@TransactionalEventListener(phase = TransactionPhase.BEFORE_COMMIT)`를 사용했다면 다음과 같은 Dual Write 문제가 발생합니다:

```kotlin
// ❌ 잘못된 방식 (BEFORE_COMMIT)
@TransactionalEventListener(phase = TransactionPhase.BEFORE_COMMIT)
fun publishEvent(event: DomainEvent) {
    // 1. EventOutbox 저장 (DB)
    eventOutboxRepository.save(outbox)

    // 2. Kafka 전송 (외부 시스템)
    kafkaTemplate.send(topic, event)

    // 3. DB 트랜잭션 커밋
}
```

**실패 시나리오:**

| 시나리오 | EventOutbox 저장 | Kafka 전송 | DB 커밋 | 결과 |
|---------|----------------|-----------|---------|------|
| 1 | ✅ | ✅ | ❌ | Kafka에 메시지는 전송되었지만 DB에는 기록 없음 → **추적 불가능** |
| 2 | ✅ | ❌ | - | Kafka 전송 실패 시 트랜잭션 롤백 → **재시도 불가** |

#### 현재 구현: 스케줄러 폴링 방식 (✅ 올바른 방식)

**구현 위치:**
- [OutboxEventPublisher.kt:30-55](apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/OutboxEventPublisher.kt#L30-L55)

**동작 흐름:**

```kotlin
// ✅ 올바른 방식 (스케줄러 폴링)

// Step 1: 비즈니스 로직 트랜잭션 (원자적)
@Transactional
fun createLike() {
    // 1. 비즈니스 로직
    likeRepository.save(like)

    // 2. EventOutbox 저장 (같은 트랜잭션)
    eventOutboxRepository.save(outbox)

    // 3. 커밋 (비즈니스 데이터 + EventOutbox 함께 저장)
}

// Step 2: 백그라운드 스케줄러 (1초마다)
@Scheduled(fixedDelay = 1000)
fun publishPendingEvents() {
    // 1. 미처리 이벤트 조회
    val pending = eventOutboxRepository.findByProcessedFalse()

    // 2. Kafka 전송
    pending.forEach { outbox ->
        try {
            kafkaTemplate.send(topic, outbox.payload)
            outbox.processed = true  // 전송 성공 표시
        } catch (e: Exception) {
            outbox.retryCount++  // 재시도 카운트 증가
        }
    }
}
```

**장점:**

1. **원자성 보장**: 비즈니스 로직과 EventOutbox 저장이 하나의 트랜잭션
2. **재시도 가능**: Kafka 전송 실패 시 스케줄러가 자동 재시도 (최대 3회)
3. **추적 가능**: 모든 이벤트가 EventOutbox에 먼저 저장됨
4. **DLQ 처리**: 3회 재시도 실패 시 DeadLetterQueue로 이동

**트레이드오프:**

- ⏱️ **지연 시간**: 최대 1초의 지연 발생 (실시간성 요구사항에 따라 조정 가능)
- 🔄 **폴링 오버헤드**: 1초마다 DB 조회 (하지만 `processed=false` 인덱스로 최적화됨)

---

## 2. ProducerFactory 하드코딩 및 Profile 분리

### 질문
> producerFactory 에서 하드코딩된 부분이 있는데요. Profile 로 분리를 하기 위해서는 어떻게 해야할까요?

### 답변

현재 `localhost:9092`가 하드코딩되어 있어 환경별 설정이 불가능합니다. **Spring Profile과 application.yml을 활용한 개선 방안**을 제시합니다.

#### 현재 문제점

**파일 위치:** [KafkaProducerConfig.kt:18](apps/commerce-api/src/main/kotlin/com/loopers/config/KafkaProducerConfig.kt#L18)

```kotlin
// ❌ 하드코딩
ProducerConfig.BOOTSTRAP_SERVERS_CONFIG to "localhost:9092"
```

#### 개선 방안 1: @Value를 사용한 외부화

```kotlin
@Configuration
class KafkaProducerConfig {

    @Value("\${spring.kafka.bootstrap-servers}")
    private lateinit var bootstrapServers: String

    @Bean
    fun producerFactory(): ProducerFactory<String, String> {
        val configProps = mapOf(
            ProducerConfig.BOOTSTRAP_SERVERS_CONFIG to bootstrapServers,
            ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG to StringSerializer::class.java,
            ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG to StringSerializer::class.java,
            ProducerConfig.ACKS_CONFIG to "all",
            ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG to true,
            ProducerConfig.RETRIES_CONFIG to 3
        )
        return DefaultKafkaProducerFactory(configProps)
    }
}
```

**application.yml 설정:**

```yaml
# application-local.yml
spring:
  kafka:
    bootstrap-servers: localhost:9092

---
# application-dev.yml
spring:
  kafka:
    bootstrap-servers: dev-kafka.example.com:9092

---
# application-prod.yml
spring:
  kafka:
    bootstrap-servers: prod-kafka-1.example.com:9092,prod-kafka-2.example.com:9092,prod-kafka-3.example.com:9092
```

#### 개선 방안 2: Spring Boot Auto-configuration 활용 (권장)

Spring Boot의 Kafka Auto-configuration을 활용하면 더 간단합니다:

**1. KafkaProducerConfig.kt 삭제 또는 최소화**

```kotlin
@Configuration
class KafkaProducerConfig {

    @Bean
    fun kafkaTemplate(producerFactory: ProducerFactory<String, String>): KafkaTemplate<String, String> {
        return KafkaTemplate(producerFactory)
    }
}
```

**2. application.yml로 모든 설정 관리**

```yaml
# application-local.yml
spring:
  kafka:
    bootstrap-servers: localhost:9092
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.apache.kafka.common.serialization.StringSerializer
      acks: all
      retries: 3
      properties:
        enable.idempotence: true

---
# application-dev.yml
spring:
  kafka:
    bootstrap-servers: dev-kafka.example.com:9092
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.apache.kafka.common.serialization.StringSerializer
      acks: all
      retries: 3
      properties:
        enable.idempotence: true
        max.in.flight.requests.per.connection: 5

---
# application-prod.yml
spring:
  kafka:
    bootstrap-servers:
      - prod-kafka-1.example.com:9092
      - prod-kafka-2.example.com:9092
      - prod-kafka-3.example.com:9092
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.apache.kafka.common.serialization.StringSerializer
      acks: all
      retries: 3
      properties:
        enable.idempotence: true
        max.in.flight.requests.per.connection: 5
        compression.type: lz4
        batch.size: 32768
        linger.ms: 100
```

**3. 실행 시 Profile 지정**

```bash
# Local 환경
java -jar app.jar --spring.profiles.active=local

# Dev 환경
java -jar app.jar --spring.profiles.active=dev

# Prod 환경
java -jar app.jar --spring.profiles.active=prod
```

#### 추천 방식

**개선 방안 2 (Auto-configuration)**를 추천합니다:

- ✅ 코드 중복 제거
- ✅ Spring Boot 표준 방식
- ✅ 환경별 설정 명확히 분리
- ✅ YAML에서 모든 설정 관리 가능
- ✅ Profile별 다른 튜닝 파라미터 적용 가능

---

## 3. 테이블 분리 목적 명확화

### 질문
> 왜 이벤트 핸들링 테이블과 로그 테이블을 분리했을까? 제목만 들으면 이 두가지가 무엇을 하는지 자체를 이해하지 못할 것 같아요. 최종목적은 단 한번만 메세지를 전달하게 하고 싶었던거 아니였을까요? 보는 이를 배려해 목적을 먼저 설명해주는게 좋지 않을까 싶어요.

### 답변

훌륭한 피드백 감사합니다! **"단 한 번만 메시지 전달"이라는 최종 목적을 먼저 설명하지 못한 점**을 개선하겠습니다.

#### 개선된 설명: 목적 중심

---

### 최종 목표: Exactly Once Semantics 보장

**핵심 질문**: *"어떻게 메시지를 정확히 한 번만 처리할 수 있을까?"*

**공식:**
```
At Least Once Producer (최소 1회 전송)
+
At Most Once Consumer (최대 1회 처리)
=
Exactly Once Semantics (정확히 1회)
```

---

### 구현 전략

#### 1️⃣ Producer: "최소 1회 전송 보장" → EventOutbox 테이블

**목적**: Kafka 전송 실패해도 재전송할 수 있도록 **전송 이력을 DB에 저장**

**테이블 역할:**
```sql
CREATE TABLE event_outbox (
    event_id VARCHAR(36) PRIMARY KEY,  -- 중복 전송 방지
    processed BOOLEAN,                  -- 전송 완료 여부
    retry_count INT,                    -- 재시도 횟수
    -- ... 기타 필드
);
```

**동작:**
1. 비즈니스 로직과 **함께** EventOutbox에 저장 (트랜잭션)
2. 스케줄러가 `processed=false` 이벤트를 조회
3. Kafka 전송 성공 시 `processed=true` 업데이트
4. 실패 시 재시도 (최대 3회)

**결과**: 네트워크 장애, Kafka 다운 등의 상황에서도 메시지 유실 없이 **최소 1회 전송 보장**

---

#### 2️⃣ Consumer: "최대 1회 처리 보장" → EventHandled 테이블

**목적**: 중복 메시지 수신해도 **한 번만 처리**하도록 **처리 이력을 DB에 저장**

**테이블 역할:**
```sql
CREATE TABLE event_handled (
    event_id VARCHAR(36) PRIMARY KEY,  -- 중복 처리 방지
    handled_at TIMESTAMP,               -- 처리 시각
    occurred_at TIMESTAMP,              -- 이벤트 발생 시각
    -- ... 기타 필드
);
```

**동작:**
1. 메시지 수신 시 `event_id`로 처리 여부 확인
2. 이미 처리된 이벤트면 **무시** (멱등성)
3. 처리 후 EventHandled에 저장
4. Kafka Manual ACK

**결과**: Producer가 중복 전송해도 비즈니스 로직은 **최대 1회만 실행**

---

#### 3️⃣ 왜 두 테이블을 분리했나?

**같은 테이블을 쓰면 안될까?** ❌

| 측면 | EventOutbox | EventHandled |
|-----|-------------|--------------|
| **목적** | Producer의 전송 보장 | Consumer의 중복 방지 |
| **소유** | commerce-api (Producer) | commerce-streamer (Consumer) |
| **생명주기** | 전송 완료 후 7일 뒤 삭제 | 처리 완료 후 30일 뒤 삭제 |
| **조회 패턴** | `processed=false` 조회 (스케줄러) | `event_id` 조회 (멱등성 체크) |
| **인덱스** | `(processed, created_at)` | `event_id` (PK) |
| **데이터 크기** | payload 포함 (평균 1KB) | 메타데이터만 (평균 100B) |

**분리의 장점:**

1. **서비스 독립성**: Producer와 Consumer가 다른 DB/서비스에 배포 가능
2. **성능 최적화**: 각자의 조회 패턴에 맞는 인덱스 설계
3. **생명주기 관리**: 전송 로그와 처리 로그를 다른 주기로 정리
4. **책임 분리**: Outbox는 "전송", Handled는 "처리" 책임만 가짐

---

### 전체 흐름 요약

```
[Producer: commerce-api]
1. 좋아요 클릭
2. Like 저장 + EventOutbox 저장 (같은 트랜잭션)
3. 스케줄러가 EventOutbox 조회
4. Kafka 전송 (재시도 포함)
5. 성공 시 processed=true

↓ Kafka Topic ↓

[Consumer: commerce-streamer]
1. 메시지 수신
2. EventHandled 조회 (처리 여부 확인)
3. 미처리 이벤트만 처리
4. EventHandled 저장 (처리 완료 표시)
5. Manual ACK

= Exactly Once Semantics ✅
```

---

### 문서 개선 제안

현재 ROUND8_OVERVIEW.md에 다음 섹션을 추가하겠습니다:

```markdown
## 🎯 핵심 목표: Exactly Once Semantics

### 문제 상황
- Producer는 네트워크 장애로 **중복 전송**할 수 있음
- Consumer는 **중복 메시지**를 받을 수 있음
- 비즈니스 로직은 **정확히 한 번만** 실행되어야 함

### 해결 전략
**공식**: At Least Once Producer + At Most Once Consumer = Exactly Once

### 구현
1. **EventOutbox**: Producer가 최소 1회 전송 보장
2. **EventHandled**: Consumer가 최대 1회 처리 보장
3. **결과**: 정확히 1회 처리
```

이렇게 **목적 → 문제 → 해결책 → 구현**의 순서로 설명하면 이해하기 쉬울 것 같습니다!

---

## 정리

1. **Dual Write**: 현재 구현은 스케줄러 폴링 방식으로 이미 해결됨 ✅
2. **Profile 분리**: Spring Boot Auto-configuration + application-{profile}.yml 사용 권장 ✅
3. **테이블 분리 설명**: 목적(Exactly Once) 중심으로 문서 개선 필요 ✅

추가 질문이나 수정 사항이 있으시면 말씀해주세요!
