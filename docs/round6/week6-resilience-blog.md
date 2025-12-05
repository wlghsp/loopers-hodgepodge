# Round 6: PG 연동과 Resilience 설계

> **TL;DR**
> 외부 PG 시스템 연동 시 발생할 수 있는 지연, 실패, 타임아웃 문제를 CircuitBreaker, Fallback, Timeout 전략으로 해결하고,
> 비동기 결제 특성을 고려한 안전한 주문-결제 상태 관리 시스템을 구현합니다.

---

## 📋 이 문서 사용 방법

### 1️⃣ 작업 진행 단계
이 블로그는 **작업 가이드**이자 **최종 제출 문서**입니다.

1. **구현하면서 캡쳐 수집**: 각 섹션의 체크박스를 따라가며 코드 작성 + 캡쳐
2. **TODO 항목 채우기**: 내가 선택한 방식과 이유를 직접 작성
3. **트러블슈팅 기록**: 실제로 겪은 문제를 실시간으로 기록
4. **최종 회고 작성**: 모든 작업이 끝난 후 회고 작성

### 2️⃣ 캡쳐 가이드
각 캡쳐 항목은 다음 형식으로 표시됩니다:

```
- [ ] **캡쳐 X-Y:** [캡쳐 제목]
  - 위치: [파일 경로 또는 URL]
  - 확인할 내용: [스크린샷에 포함되어야 할 핵심 내용]
```

**캡쳐 팁:**
- 코드 스크린샷: IDE에서 중요 부분 하이라이트하거나 화살표 표시
- 로그 스크린샷: 중요한 로그 라인을 형광펜으로 표시
- DB 스크린샷: 변경 전/후를 나란히 배치
- 다이어그램: 손그림도 OK! 중요한 건 흐름 이해

### 3️⃣ 블로그 완성 후
모든 캡쳐와 내용을 채운 후:
1. 이 파일을 그대로 블로그 플랫폼(Notion, Velog, Medium 등)에 복사
2. 또는 이 파일을 기반으로 더 컴팩트한 버전 작성
3. 포트폴리오/이력서에 링크 추가

### 4️⃣ 총 캡쳐 개수 예상
- **코드 및 설정**: 약 20개
- **테스트 시나리오**: 약 39개 (6개 시나리오 × 평균 6.5개)
- **트러블슈팅**: 약 9개 (3개 문제 × 3개)
- **회고**: 약 3개
- **총합: 약 70개 캡쳐**

💡 모든 캡쳐를 다 넣을 필요는 없습니다. 핵심적인 것만 선별하세요!

---

## 📊 핵심 체크리스트 빠른 보기

구현해야 할 핵심 기능들을 한눈에 확인하세요:

### ✅ 필수 구현 항목 (Must-Have)
- [ ] Payment 도메인 설계 및 구현 (Entity, Status, Method)
- [ ] PG Client 구현 (FeignClient)
- [ ] Timeout 설정 (connectTimeout: 1s, readTimeout: 3s)
- [ ] CircuitBreaker 적용 (failure-rate-threshold: 50%)
- [ ] Fallback 전략 구현 (즉시 실패 + 재고 보호)
- [ ] 콜백 처리 API (멱등성 보장)
- [ ] 재고 차감 시점: 콜백 성공 시
- [ ] 스케줄러 기반 복구 로직 (10분 이상 PENDING 주문)

### 🎯 추가 구현 항목 (Nice-to-Have)
- [ ] Retry 정책 (선택사항)
- [ ] 전략 패턴 (PgStrategy)
- [ ] 재고 부족 시 PG 취소 요청
- [ ] Actuator health 엔드포인트

### 📝 문서화 항목
- [ ] 재고 차감 시점 선택 이유
- [ ] Payment 도메인 분리 이유
- [ ] Resilience4j 설정값 선택 근거
- [ ] 트러블슈팅 최소 3개
- [ ] 회고 (잘한 점, 아쉬운 점, 개선 방향)

---

## 시작하기 전에

### 이번 주 핵심 과제
- PG 시뮬레이터와의 연동 (비동기 결제)
- Resilience 패턴 적용 (Timeout, Fallback, CircuitBreaker)
- 결제 실패/지연 시나리오 대응

### PG Simulator 특성 이해

**🎯 작업: PG Simulator 실행 및 특성 확인**

```bash
# pg-simulator 실행
cd apps/pg-simulator
./gradlew bootRun
```

**📸 작업 후 제공할 캡쳐:**
- [ ] **캡쳐 1-1:** PG Simulator 실행 터미널 로그 전체 화면
  - 위치: `apps/pg-simulator`에서 `./gradlew bootRun` 실행
  - 확인할 내용: "Started PgSimulatorApplication" 메시지, 실행 포트 번호
- [ ] **캡쳐 1-2:** `apps/pg-simulator/src/main/resources/application.yml` 파일
  - 확인할 내용: `server.port` 설정값 (기본 8081)
- [ ] **캡쳐 1-3:** PG API 엔드포인트 테스트 (http 파일 또는 Postman)
  - 테스트 URL: `POST http://localhost:8081/api/v1/payments`
  - 응답 예시 스크린샷 (transactionKey 포함)

**확인할 특성:**
```
요청 성공 확률: 60%
요청 지연: 100ms ~ 500ms
처리 지연: 1s ~ 5s
처리 결과:
  - 성공: 70%
  - 한도 초과: 20%
  - 잘못된 카드: 10%
```

**첫 번째 의문: 왜 이렇게 불안정한 시스템과 연동해야 하나?**
→ 실무에서 외부 PG는 항상 불안정합니다. 네트워크 지연, 부하, 장애가 언제든 발생할 수 있습니다.
→ 이런 환경에서도 우리 시스템은 "견고하게" 동작해야 합니다.

---

## 설계 전 고민들

### 재고 차감 시점: 가장 중요한 결정

**멘토님의 핵심 질문:**
> "재고를 언제 차감할 것인가?"

**방식 A: 선차감 (주문 생성 시 재고 점유)**
```kotlin
주문 생성 → 재고 즉시 차감 → PG 결제 요청 → 콜백 대기
```
- 장점: 유저 만족도 높음 ("재고 확보했어요")
- 단점: GMV 감소, 결제 실패 시 재고 원복 로직 복잡

**방식 B: 콜백 시점 차감 (멘토님 추천)**
```kotlin
주문 생성 → 재고 검증만 → PG 결제 요청 → 콜백 성공 시 재고 차감
```
- 장점: GMV 최적화, 시스템 단순, 장애 격리
- 단점: 콜백 타이밍에 재고 부족 가능

**💡 내가 선택한 방식과 이유:**
→ (TODO: 멘토님 코멘트와 수업 내용을 바탕으로 선택한 방식 작성)
→ (TODO: "장애가 전체 시스템에 전파되지 않도록" 관점에서 설명)

**📸 작업 후 제공할 캡쳐:**
- [ ] **캡쳐 2-1:** 재고 차감 시점 비교표 (마크다운 테이블)
  ```markdown
  | 구분 | 선차감 방식 | 콜백 시점 차감 (선택) |
  |------|------------|---------------------|
  | 재고 차감 시점 | 주문 생성 시 | 결제 성공 콜백 시 |
  | GMV 영향 | 감소 | 최적화 |
  | 장애 격리 | 어려움 | 용이 |
  | 구현 복잡도 | 높음 (원복 필요) | 낮음 |
  | 재고 부족 발생 시점 | 주문 생성 시 | 콜백 시 |
  ```
- [ ] **캡쳐 2-2:** 선택한 방식의 플로우 다이어그램 (손그림, draw.io, Excalidraw 등)
  - 필수 포함 요소: 주문 생성 → 재고 검증 → PG 요청 → 콜백 대기 → 재고 차감
  - 실패 케이스도 표시: PG 실패 시, 콜백 타이밍 재고 부족 시

---

### Payment 도메인이 정말 필요한가?

**초기 생각:**
- "주문에 결제 정보만 추가하면 되지 않을까?"
- Order에 `paymentStatus`, `transactionKey` 필드만 추가?

**고민 지점:**
- 주문과 결제는 다른 생명주기를 가진다
  - 주문: 생성 → 결제 대기 → 확정 → 배송
  - 결제: 요청 → 대기 → 성공/실패
- 하나의 주문에 여러 결제 시도가 있을 수 있다
- 결제 실패 시 재시도, 부분 취소 등의 복잡한 로직 필요

**💡 결론:**
→ Payment를 별도 도메인으로 분리
→ Order ↔ Payment는 1:N 관계 (한 주문에 여러 결제 시도 가능)

---

### 비동기 결제를 어떻게 처리할 것인가?

**비동기 결제란?**
- PG에 결제 요청 → 즉시 응답 (요청 접수)
- 실제 결제 처리는 1~5초 후 완료
- 결과는 콜백으로 전달

**시나리오 1: 콜백만 믿는다면?**
```
문제:
- 콜백이 안 올 수도 있다 (네트워크 장애, PG 장애)
- 콜백 URL이 잘못되었을 수도 있다
- 사용자는 "결제 중..." 상태에서 무한 대기
```

**시나리오 2: 폴링으로 상태를 확인한다면?**
```
장점:
- 콜백이 실패해도 복구 가능
- 일정 주기로 PG에서 상태를 직접 조회
단점:
- PG API 호출량 증가
- 적절한 폴링 주기 설정이 어렵다
```

**💡 멘토님 제안: 콜백 + 스케줄러 조합**
```
1. 콜백에서 주문완료 + 재고차감
2. 콜백에서 실패하면 주문 취소 + 포인트 원복
3. 스케줄러로 상태변경 없는 주문들을 확인해서 1,2번에 맞게 변경
```

**💡 내가 선택한 방식:**
→ (TODO: 최종 선택한 방식과 이유)

---

## 구현 과정

### Payment 도메인 설계 및 구현

**🎯 작업: commerce-api에 Payment 엔티티 구현**

**중요한 이해: pg-simulator vs commerce-api**

- **pg-simulator의 Payment**: PG사 입장에서 관리하는 결제 정보
- **commerce-api의 Payment**: 우리 커머스 시스템에서 관리하는 결제 정보

→ **두 시스템은 별개이므로, commerce-api에도 Payment 엔티티가 필요합니다!**

**⚠️ 주의: 테이블명 충돌 방지**

pg-simulator와 같은 DB를 사용한다면 테이블명이 겹칠 수 있습니다.
- pg-simulator: `payments` 테이블
- commerce-api: `commerce_payments` 또는 `order_payments` 테이블로 구분

**💡 설계 결정: Payment 엔티티 분리 (옵션 2 선택)**

**옵션 1: Order에 결제 정보 추가 (간단)**
```kotlin
class Order {
    @Column(name = "transaction_key")
    var transactionKey: String? = null  // PG 거래 번호

    @Enumerated(EnumType.STRING)
    var paymentMethod: PaymentMethod = PaymentMethod.POINT
}
```
- 장점: 간단, Order만으로 추적 가능
- 단점: 여러 결제 시도 추적 불가, 도메인 분리 원칙 위반

**옵션 2: Payment 엔티티 분리 (복잡하지만 확장성 좋음) ✅ 선택**
```kotlin
@Entity
@Table(name = "commerce_payments")  // 충돌 방지
class Payment(
    orderId: Long,
    amount: Money,
    paymentMethod: PaymentMethod = PaymentMethod.POINT,
    transactionKey: String? = null,
    cardType: String? = null,
    cardNo: String? = null
) : BaseEntity() {

    @Column(name = "order_id", nullable = false)
    var orderId: Long = orderId
        protected set

    @Embedded
    @AttributeOverride(name = "amount", column = Column(name = "amount", nullable = false))
    var amount: Money = amount
        protected set

    @Enumerated(EnumType.STRING)
    @Column(name = "payment_method", nullable = false)
    var paymentMethod: PaymentMethod = paymentMethod
        protected set

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    var status: PaymentStatus = PaymentStatus.PENDING
        protected set

    @Column(name = "transaction_key", length = 100)
    var transactionKey: String? = transactionKey
        protected set

    @Column(name = "card_type", length = 20)
    var cardType: String? = cardType
        protected set

    @Column(name = "card_no", length = 20)
    var cardNo: String? = cardNo
        protected set

    @Column(name = "failure_reason", length = 500)
    var failureReason: String? = null
        protected set

    fun markAsSuccess() {
        if (status != PaymentStatus.PENDING) {
            throw CoreException(ErrorType.INVALID_PAYMENT_STATUS)
        }
        status = PaymentStatus.SUCCESS
    }

    fun markAsFailed(reason: String) {
        if (status != PaymentStatus.PENDING) {
            throw CoreException(ErrorType.INVALID_PAYMENT_STATUS)
        }
        status = PaymentStatus.FAILED
        failureReason = reason
    }

    companion object {
        fun createCardPayment(
            orderId: Long,
            amount: Money,
            transactionKey: String,
            cardType: String,
            cardNo: String
        ): Payment {
            return Payment(
                orderId = orderId,
                amount = amount,
                paymentMethod = PaymentMethod.CARD,
                transactionKey = transactionKey,
                cardType = cardType,
                cardNo = cardNo
            )
        }

        fun createFailedPayment(
            orderId: Long,
            amount: Money,
            reason: String
        ): Payment {
            return Payment(
                orderId = orderId,
                amount = amount
            ).apply {
                status = PaymentStatus.FAILED
                failureReason = reason
            }
        }
    }
}
```
- 장점: 결제 이력 추적, 재시도 관리, 도메인 분리, 확장성
- 단점: 추가 구현 필요 (하지만 이점이 더 큼)

**선택 이유:**
1. **도메인 분리**: 주문과 결제는 다른 생명주기
2. **이력 관리**: 한 주문에 여러 결제 시도 가능
3. **확장성**: 향후 부분 취소, 환불 등 복잡한 로직 대응 용이
4. **실무 관점**: 대부분의 커머스 시스템은 Payment를 별도 도메인으로 관리

**내가 선택한 방식:**
→ Payment 엔티티 분리 (commerce_payments 테이블)

**📸 작업 후 제공할 캡쳐:**
- [ ] **캡쳐 3-1:** pg-simulator의 Payment 엔티티 코드
  - 파일 위치: `apps/pg-simulator/src/main/kotlin/.../domain/payment/Payment.kt`
  - 확인할 내용: 필드 구조 (transactionKey, status, amount 등)
- [ ] **캡쳐 3-2:** commerce-api의 Payment 엔티티 전체 코드
  - 파일 위치: `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/Payment.kt`
  - 확인할 내용:
    - `@Table(name = "commerce_payments")` 충돌 방지
    - 주요 필드: orderId, amount, paymentMethod, status, transactionKey
    - 상태 전이 메서드: `markAsSuccess()`, `markAsFailed(reason)`
- [ ] **캡쳐 3-3:** PaymentStatus enum 코드
  - 확인할 내용: PENDING, SUCCESS, FAILED 상태 정의
- [ ] **캡쳐 3-4:** PaymentMethod enum 코드
  - 확인할 내용: POINT, CARD 정의
- [ ] **캡쳐 3-5:** DB 테이블 스키마 확인
  - SQL 파일: `docker/01-schema.sql`에서 `commerce_payments` 테이블 생성 DDL
  - 또는 DBeaver/DataGrip 등에서 테이블 구조 확인 스크린샷

---

### PG Client 구현 (전략 패턴 적용)

**🎯 작업: 전략 패턴으로 확장 가능한 PG Client 설계**

**왜 전략 패턴인가?**
- 현재는 pg-simulator 하나지만, 실무에서는 여러 PG사 연동 (토스, 나이스페이, KG이니시스 등)
- PG사마다 다른 API 스펙, 인증 방식
- 새로운 PG 추가 시 기존 코드 수정 없이 확장 (OCP 원칙)

**전략 패턴 구조:**

```kotlin
// 1. PgStrategy 인터페이스
interface PgStrategy {
    fun supports(paymentMethod: PaymentMethod): Boolean
    fun requestPayment(request: PaymentRequest): PgPaymentResponse
    fun getPaymentStatus(transactionKey: String): PgPaymentStatusResponse
}

// 2. 구체적인 전략 구현
@Component
class SimulatorPgStrategy(
    private val pgSimulatorClient: PgSimulatorClient
) : PgStrategy {

    override fun supports(paymentMethod: PaymentMethod): Boolean {
        return paymentMethod == PaymentMethod.CARD
    }

    override fun requestPayment(request: PaymentRequest): PgPaymentResponse {
        return pgSimulatorClient.requestPayment(
            PgPaymentRequest(
                orderId = request.orderId,
                userId = request.userId,
                cardType = request.cardType,
                cardNo = request.cardNo,
                amount = request.amount,
                callbackUrl = request.callbackUrl
            )
        )
    }

    override fun getPaymentStatus(transactionKey: String): PgPaymentStatusResponse {
        return pgSimulatorClient.getPaymentStatus(transactionKey)
    }
}

// 3. (확장 예시) 다른 PG사 전략
@Component
class TossPgStrategy(
    private val tossClient: TossClient
) : PgStrategy {

    override fun supports(paymentMethod: PaymentMethod): Boolean {
        return paymentMethod == PaymentMethod.CARD
        // 실제로는 더 세밀한 조건 (카드사, 금액 등)
    }

    override fun requestPayment(request: PaymentRequest): PgPaymentResponse {
        // Toss API 호출
        // ...
    }

    override fun getPaymentStatus(transactionKey: String): PgPaymentStatusResponse {
        // Toss API 호출
        // ...
    }
}

// 4. PaymentService에서 전략 사용
@Service
class PaymentService(
    private val pgStrategies: List<PgStrategy>,
    private val paymentRepository: PaymentRepository
) {

    @CircuitBreaker(name = "pgCircuit", fallbackMethod = "paymentFallback")
    @TimeLimiter(name = "pgTimeLimiter")
    fun requestCardPayment(
        order: Order,
        userId: String,
        cardInfo: CardInfo
    ): Payment {
        // 적절한 전략 선택
        val pgStrategy = pgStrategies.firstOrNull {
            it.supports(PaymentMethod.CARD)
        } ?: throw CoreException(ErrorType.PG_NOT_AVAILABLE)

        // 전략 실행
        val pgResponse = pgStrategy.requestPayment(
            PaymentRequest(
                orderId = order.id.toString(),
                userId = userId,
                cardType = cardInfo.cardType,
                cardNo = cardInfo.cardNo,
                amount = order.finalAmount.amount.toString(),
                callbackUrl = "http://localhost:8080/api/v1/payments/callback"
            )
        )

        // Payment 생성
        return Payment.createCardPayment(
            orderId = order.id!!,
            amount = order.finalAmount,
            transactionKey = pgResponse.transactionKey,
            cardType = cardInfo.cardType,
            cardNo = cardInfo.cardNo
        ).let { paymentRepository.save(it) }
    }
}
```

**💡 전략 패턴의 장점:**

**1. 확장성**
- 새 PG사 추가 시: 새로운 Strategy 클래스만 추가
- 기존 코드 수정 불필요

**2. 유연성**
- 트래픽 분산: 여러 PG 중 선택 가능
- A/B 테스트: PG사별 성능/수수료 비교

**3. 테스트 용이성**
- Mock Strategy로 쉽게 테스트

**📸 작업 후 제공할 캡쳐:**
- [ ] **캡쳐 4-1:** PgStrategy 인터페이스 전체 코드
  - 파일 위치: `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/strategy/PgStrategy.kt`
  - 확인할 내용: `supports()`, `requestPayment()`, `getPaymentStatus()` 메서드
- [ ] **캡쳐 4-2:** SimulatorPgStrategy 구현체 전체 코드
  - 파일 위치: `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/strategy/SimulatorPgStrategy.kt`
  - 확인할 내용: `@Component` 선언, PgSimulatorClient 의존성, 메서드 구현
- [ ] **캡쳐 4-3:** PaymentService에서 전략 선택 로직
  - 파일 위치: `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentService.kt`
  - 확인할 내용:
    ```kotlin
    private val pgStrategies: List<PgStrategy>
    val pgStrategy = pgStrategies.firstOrNull { it.supports(PaymentMethod.CARD) }
    ```
- [ ] **캡쳐 4-4:** (Optional) 확장 예시 - TossPgStrategy 또는 NicePayPgStrategy 스케치
  - 실제 구현 아니어도 됨, 주석으로 "향후 확장 가능" 표시한 코드

---

### Feign Client 구현

**🎯 작업: Feign Client로 실제 HTTP 통신**

**선택 이유: FeignClient**
- 선언적 HTTP Client로 코드 간결
- Resilience4j 통합 용이
- Spring Cloud 생태계 활용

```kotlin
// 1. build.gradle.kts에 의존성 추가
dependencies {
    implementation("org.springframework.cloud:spring-cloud-starter-openfeign")
    implementation("io.github.resilience4j:resilience4j-spring-boot3")
    implementation("org.springframework.boot:spring-boot-starter-aop")
}

// 2. PgClient 인터페이스
@FeignClient(
    name = "pg-client",
    url = "\${pg.base-url}",
    configuration = [PgClientConfig::class]
)
interface PgClient {

    @PostMapping("/api/v1/payments")
    fun requestPayment(@RequestBody request: PgPaymentRequest): PgPaymentResponse

    @GetMapping("/api/v1/payments/{transactionKey}")
    fun getPaymentStatus(@PathVariable transactionKey: String): PgPaymentStatusResponse

    @GetMapping("/api/v1/payments")
    fun getPaymentsByOrderId(@RequestParam orderId: String): PgOrderPaymentsResponse
}

// 3. DTO 정의
data class PgPaymentRequest(
    val orderId: String,
    val userId: String,
    val cardType: String,
    val cardNo: String,
    val amount: String,
    val callbackUrl: String
)

data class PgPaymentResponse(
    val transactionKey: String,
    val status: String,
    val message: String
)

data class PgPaymentStatusResponse(
    val transactionKey: String,
    val status: String,
    val amount: String,
    val failureReason: String?
)

// 4. Feign 설정
@Configuration
@EnableFeignClients(basePackages = ["com.loopers"])
class FeignConfig

@Configuration
class PgClientConfig {

    @Bean
    fun feignRequestOptions(): Request.Options {
        return Request.Options(
            1000,  // connectTimeout (ms)
            3000   // readTimeout (ms)
        )
    }
}

// 5. application.yml
pg:
  base-url: http://localhost:8081  # PG Simulator 포트
```

**💡 Timeout 설정 고민:**

**시도 1: readTimeout = 2000ms**
- PG 처리 지연이 1~5초인데 2초는 너무 짧음
- 정상 요청도 타임아웃 발생

**최종: readTimeout = 3000ms**
- 이유:
  1. 콜백 방식이므로 즉시 응답 기다릴 필요 없음
  2. 3초 안에 요청 접수 응답 받으면 충분
  3. 실제 결제 완료는 콜백으로 확인
  4. 3초 넘으면 타임아웃 → Fallback

**📸 작업 후 제공할 캡쳐:**
- [ ] **캡쳐 5-1:** build.gradle.kts 의존성 추가 부분
  - 확인할 내용:
    ```kotlin
    implementation("org.springframework.cloud:spring-cloud-starter-openfeign")
    implementation("io.github.resilience4j:resilience4j-spring-boot3")
    ```
- [ ] **캡쳐 5-2:** PgSimulatorClient (FeignClient) 인터페이스 코드
  - 파일 위치: `apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/pg/PgSimulatorClient.kt`
  - 확인할 내용:
    - `@FeignClient(name = "pg-client", url = "\${pg.base-url}")`
    - `@PostMapping("/api/v1/payments")`
    - `@GetMapping("/api/v1/payments/{transactionKey}")`
- [ ] **캡쳐 5-3:** PgClientConfig 설정 클래스
  - 확인할 내용: `Request.Options(1000, 3000)` - connectTimeout, readTimeout
- [ ] **캡쳐 5-4:** FeignConfig 클래스
  - 확인할 내용: `@EnableFeignClients(basePackages = ["com.loopers"])`
- [ ] **캡쳐 5-5:** application.yml pg 설정
  ```yaml
  pg:
    base-url: http://localhost:8081
  ```
- [ ] **캡쳐 5-6:** PG Simulator에 실제 요청 보낸 로그 (애플리케이션 로그)
  - 확인할 내용: "POST http://localhost:8081/api/v1/payments" 호출 로그
- [ ] **캡쳐 5-7:** PG Simulator 응답 받은 로그
  - 확인할 내용: transactionKey 포함된 응답 JSON

---

### Resilience4j 패턴 적용

**🎯 작업: CircuitBreaker, Fallback, TimeLimiter 적용**

**왜 필요한가:**
- PG가 계속 실패하는데 요청을 계속 보내면 시스템 전체 느려짐
- "장애 전파 방지"가 이번 주 핵심

```yaml
# application.yml
resilience4j:
  circuitbreaker:
    instances:
      pgCircuit:
        sliding-window-size: 10              # 최근 10개 호출 기준
        failure-rate-threshold: 50           # 실패율 50% 넘으면 Open
        wait-duration-in-open-state: 10s     # 10초간 차단
        permitted-number-of-calls-in-half-open-state: 2
        slow-call-duration-threshold: 2s     # 2초 넘으면 "느린 호출"
        slow-call-rate-threshold: 50         # 느린 호출 50% 넘어도 Open
        register-health-indicator: true

  timelimiter:
    instances:
      pgTimeLimiter:
        timeout-duration: 3s                 # 전체 실행 시간 제한
```

**💡 설정값 고민:**

**failure-rate-threshold: 50%**
- PG 요청 성공률이 60%임
- 40%는 실패하는 게 정상
- 50% 넘으면 "평소보다 더 안 좋음" → Open
- 테스트: (TODO: 실제로 50%가 적절한지 테스트 결과 작성)

**slow-call-duration-threshold: 2s**
- 요청 지연이 100~500ms
- 2초 넘으면 비정상적으로 느림
- 실패는 아니지만 시스템에 부담

**wait-duration-in-open-state: 10s**
- PG가 복구될 시간 제공
- 너무 짧으면 계속 Open/Close 반복
- 테스트: (TODO: 10초가 적절한지 테스트 결과)

```kotlin
// PaymentService.kt
@Service
class PaymentService(
    private val pgClient: PgClient,
    private val paymentRepository: PaymentRepository,
    private val orderRepository: OrderRepository
) {

    @CircuitBreaker(name = "pgCircuit", fallbackMethod = "paymentFallback")
    @TimeLimiter(name = "pgTimeLimiter")
    fun requestCardPayment(
        order: Order,
        userId: String,
        cardInfo: CardInfo
    ): Payment {
        // PG 결제 요청
        val pgResponse = pgClient.requestPayment(
            PgPaymentRequest(
                orderId = order.id.toString(),
                userId = userId,
                cardType = cardInfo.cardType,
                cardNo = cardInfo.cardNo,
                amount = order.finalAmount.amount.toString(),
                callbackUrl = "http://localhost:8080/api/v1/payments/callback"
            )
        )

        // Payment 엔티티 생성 (PENDING)
        val payment = Payment.createCardPayment(
            orderId = order.id!!,
            amount = order.finalAmount,
            transactionKey = pgResponse.transactionKey,
            cardType = cardInfo.cardType,
            cardNo = cardInfo.cardNo
        )

        return paymentRepository.save(payment)
    }

    // Fallback: CircuitBreaker Open 또는 Timeout 시
    private fun paymentFallback(
        order: Order,
        userId: String,
        cardInfo: CardInfo,
        ex: Exception
    ): Payment {
        // 재고 차감하지 않음!
        // Payment 실패 기록만 남김
        val payment = Payment.createFailedPayment(
            orderId = order.id!!,
            amount = order.finalAmount,
            reason = "PG 시스템 일시 불가: ${ex.message}"
        )

        paymentRepository.save(payment)

        // Order도 실패 처리
        order.fail()
        orderRepository.save(order)

        throw CoreException(
            ErrorType.PAYMENT_UNAVAILABLE,
            "현재 카드 결제가 불가능합니다. 잠시 후 다시 시도해주세요."
        )
    }
}
```

**💡 Fallback 전략:**

**선택: 즉시 실패 응답 + 재고 차감 안 함**
- 이유:
  1. PG 장애 시 재고 묶이지 않음 (GMV 보호)
  2. 다른 고객에게 구매 기회 제공
  3. 시스템 복잡도 낮음
  4. 사용자에게 명확한 안내 가능

**대안 (큐 방식)은 왜 안 했나:**
- 큐 관리 복잡도 증가
- 언제 재시도할지 정책 필요
- 재고 정합성 이슈

**📸 작업 후 제공할 캡쳐:**
- [ ] **캡쳐 6-1:** application.yml Resilience4j 전체 설정
  - 확인할 내용:
    ```yaml
    resilience4j:
      circuitbreaker:
        instances:
          pgCircuit:
            sliding-window-size: 10
            failure-rate-threshold: 50
            wait-duration-in-open-state: 10s
            slow-call-duration-threshold: 2s
      timelimiter:
        instances:
          pgTimeLimiter:
            timeout-duration: 3s
    ```
- [ ] **캡쳐 6-2:** PaymentService에 @CircuitBreaker, @TimeLimiter 적용 코드
  - 확인할 내용:
    ```kotlin
    @CircuitBreaker(name = "pgCircuit", fallbackMethod = "paymentFallback")
    @TimeLimiter(name = "pgTimeLimiter")
    fun requestCardPayment(...): Payment
    ```
- [ ] **캡쳐 6-3:** Fallback 메서드 전체 구현 코드
  - 메서드명: `paymentFallback`
  - 확인할 내용: Payment.createFailedPayment() 생성, Order.fail() 호출
- [ ] **캡쳐 6-4:** CircuitBreaker Open 발생 로그
  - 시나리오: PG Simulator 종료 후 연속 10회 요청
  - 확인할 내용: "CircuitBreaker 'pgCircuit' is OPEN" 로그
- [ ] **캡쳐 6-5:** Fallback 실행 로그
  - 확인할 내용: "PG 시스템 일시 불가" 메시지 포함된 로그
- [ ] **캡쳐 6-6:** Actuator health 엔드포인트 응답
  - URL: `GET http://localhost:8080/actuator/health`
  - 확인할 내용: `circuitBreakers.pgCircuit.state: "OPEN"` 또는 "CLOSED"
- [ ] **캡쳐 6-7:** (Optional) CircuitBreaker 상태 변화 추적
  - CLOSED → OPEN → HALF_OPEN → CLOSED 전환 로그 시퀀스

---

### Retry 정책 (선택사항)

**💭 고민: 재시도를 해야 하나?**

**하지 않기로 결정:**
- PG 요청 실패는 대부분 일시적 네트워크 오류가 아님
- 카드 정보 오류, 한도 초과 등은 재시도해도 실패
- 콜백 방식이므로 즉시 응답 필요 없음
- CircuitBreaker가 이미 보호 역할 수행

**만약 적용한다면:**
```yaml
resilience4j:
  retry:
    instances:
      pgRetry:
        max-attempts: 2
        wait-duration: 500ms
        retry-exceptions:
          - java.net.ConnectException
          - feign.RetryableException
```

**📸 작업 후 제공할 캡쳐:**
- [ ] (선택) Retry 적용했다면 설정과 테스트 결과

---

## 주문-결제 연동 설계

### 주문 생성 → 결제 요청 플로우

**🎯 작업: 멘토님 방식 적용 - 콜백 시점 재고 차감**

**최종 플로우:**

```kotlin
// OrderService.kt
@Service
class OrderService(
    private val orderRepository: OrderRepository,
    private val productService: ProductService,
    private val paymentService: PaymentService
) {

    @Transactional
    fun createOrderWithCardPayment(
        memberId: String,
        orderItems: List<OrderItemCommand>,
        cardInfo: CardInfo
    ): OrderResponse {
        // 1. 상품 조회 및 재고 검증만 (차감하지 않음!)
        val productMap = productService.getProductsByIds(orderItems.map { it.productId })
        orderItems.forEach { item ->
            val product = productMap[item.productId]
                ?: throw CoreException(ErrorType.PRODUCT_NOT_FOUND)
            product.validateStock(Quantity.of(item.quantity))  // 검증만!
        }

        // 2. 주문 생성 (PENDING)
        val order = Order.create(memberId, orderItems, productMap)
        orderRepository.save(order)

        // 3. PG 결제 요청
        try {
            val payment = paymentService.requestCardPayment(order, memberId, cardInfo)

            // 4. "결제 진행 중" 응답
            return OrderResponse(
                orderId = order.id!!,
                status = "PENDING",
                message = "결제가 진행 중입니다. 잠시만 기다려주세요."
            )
        } catch (e: CoreException) {
            // PG 요청 실패 (Timeout, CircuitBreaker Open)
            order.fail()
            orderRepository.save(order)
            throw e
        }
    }
}
```

**💡 핵심 결정: 재고 검증만, 차감은 콜백에서**

**이유:**

- **장애 격리**: PG 장애 시 재고는 안전
- **GMV 최적화**: 실제 결제 성공한 것만 재고 차감
- **시스템 단순**: 원복 로직 불필요

**케이스별 대응:**

**케이스 1: PG 요청 실패 (Timeout, CircuitBreaker Open)**

```text
→ Fallback 실행
→ Order FAILED
→ 재고 그대로 (다른 고객 구매 가능)
→ 사용자: "카드 결제 불가" 메시지
```

**케이스 2: PG 요청 성공, 콜백 대기**

```text
→ Order PENDING
→ Payment PENDING
→ 재고 그대로 (아직 확정 아님)
→ 콜백 오면 재고 차감
```

**케이스 3: 콜백 타이밍에 재고 부족**

```text
→ PG 취소 요청
→ Order FAILED
→ 사용자: CS 처리 (쿠폰 지급 등)
```

**📸 작업 후 제공할 캡쳐:**
- [ ] **캡쳐 7-1:** OrderService.createOrderWithCardPayment 메서드 전체 코드
  - 파일 위치: `apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderService.kt`
  - 확인할 내용:
    - 재고 검증: `product.validateStock(Quantity.of(item.quantity))`
    - 재고 차감 **안 함**: `product.decreaseStock()` 호출 없음
    - PG 요청: `paymentService.requestCardPayment(order, memberId, cardInfo)`
- [ ] **캡쳐 7-2:** Product.validateStock() 메서드 코드
  - 확인할 내용: 재고 부족 시 예외 발생, 차감하지 않음
- [ ] **캡쳐 7-3:** PG 요청 성공 시 애플리케이션 로그
  - 확인할 내용:
    - "Payment requested successfully" 또는 유사 메시지
    - transactionKey 포함
    - Order status: PENDING
    - Payment status: PENDING
- [ ] **캡쳐 7-4:** PG 요청 실패 시 로그 (Fallback 실행)
  - 시나리오: PG Simulator 종료 상태
  - 확인할 내용:
    - Fallback 메서드 실행 로그
    - Order status: FAILED
    - Payment status: FAILED
    - 사용자에게 반환된 에러 메시지

---

### 콜백 처리 (핵심!)

**🎯 작업: 결제 콜백 API 구현 + 재고 차감**

```kotlin
// PaymentCallbackController.kt
@RestController
@RequestMapping("/api/v1/payments")
class PaymentCallbackController(
    private val paymentCallbackService: PaymentCallbackService
) {

    @PostMapping("/callback")
    fun handleCallback(@RequestBody callback: PgPaymentCallbackDto): ApiResponse<Unit> {
        paymentCallbackService.handlePaymentCallback(callback)
        return ApiResponse.success()
    }
}

// PaymentCallbackService.kt
@Service
class PaymentCallbackService(
    private val paymentRepository: PaymentRepository,
    private val orderRepository: OrderRepository,
    private val productService: ProductService,
    private val pgClient: PgClient
) {

    @Transactional
    fun handlePaymentCallback(callback: PgPaymentCallbackDto) {
        // 1. Payment 조회
        val payment = paymentRepository.findByTransactionKey(callback.transactionKey)
            ?: throw CoreException(ErrorType.PAYMENT_NOT_FOUND)

        // 멱등성: 이미 처리된 콜백이면 무시
        if (payment.status != PaymentStatus.PENDING) {
            logger.warn("Already processed payment: ${payment.id}")
            return
        }

        // 2. Order 조회
        val order = orderRepository.findById(payment.orderId)
            ?: throw CoreException(ErrorType.ORDER_NOT_FOUND)

        if (callback.isSuccess()) {
            // 3-1. 결제 성공 → 재고 차감 시도
            try {
                productService.decreaseStock(order.items)

                payment.markAsSuccess()
                order.complete()

                logger.info("Payment success: orderId=${order.id}, transactionKey=${callback.transactionKey}")
            } catch (e: OutOfStockException) {
                // 재고 부족 → PG 취소 요청
                pgClient.cancelPayment(callback.transactionKey)

                payment.markAsFailed("재고 부족")
                order.fail()

                logger.error("Out of stock after payment success: orderId=${order.id}")
                // TODO: CS 팀 알림
            }
        } else {
            // 3-2. 결제 실패
            payment.markAsFailed(callback.failureReason ?: "알 수 없는 오류")
            order.fail()

            logger.warn("Payment failed: orderId=${order.id}, reason=${callback.failureReason}")
        }
    }
}

// DTO
data class PgPaymentCallbackDto(
    val transactionKey: String,
    val status: String,
    val failureReason: String?
) {
    fun isSuccess(): Boolean = status == "SUCCESS"
}
```

**💡 멱등성 처리:**

- Payment 상태가 PENDING이 아니면 무시
- 중복 콜백 방지

**💡 보안 고민:**

**현재 구현: 보안 검증 없음 (시뮬레이터이므로)**

**실무라면:**

- PG 서명 검증
- IP 화이트리스트
- 타임스탬프 검증

**📸 작업 후 제공할 캡쳐:**
- [ ] **캡쳐 8-1:** PaymentCallbackController 전체 코드
  - 파일 위치: `apps/commerce-api/src/main/kotlin/com/loopers/api/v1/PaymentCallbackController.kt`
  - 확인할 내용: `@PostMapping("/callback")` 엔드포인트
- [ ] **캡쳐 8-2:** PaymentCallbackService.handlePaymentCallback 메서드 전체 코드
  - 파일 위치: `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackService.kt`
  - 확인할 내용:
    - 멱등성 체크: `if (payment.status != PaymentStatus.PENDING) return`
    - 성공 시: `productService.decreaseStock()` + `payment.markAsSuccess()` + `order.complete()`
    - 실패 시: `payment.markAsFailed()` + `order.fail()`
    - 재고 부족 시: `pgClient.cancelPayment()` + 실패 처리
- [ ] **캡쳐 8-3:** PgPaymentCallbackDto 정의
  - 확인할 내용: transactionKey, status, failureReason 필드
- [ ] **캡쳐 8-4:** 콜백 성공 시 애플리케이션 로그
  - 확인할 내용:
    - "Payment success" 메시지
    - 재고 차감 로그
    - Order status: COMPLETED
    - Payment status: SUCCESS
- [ ] **캡쳐 8-5:** DB 상태 변화 확인 (콜백 전후)
  - 테이블: orders, commerce_payments, products
  - 비교 스크린샷:
    - 콜백 전: Order(PENDING), Payment(PENDING), Product(stock=10)
    - 콜백 후: Order(COMPLETED), Payment(SUCCESS), Product(stock=9)
- [ ] **캡쳐 8-6:** 콜백 실패 시 로그
  - 시나리오: PG에서 "한도 초과" 응답
  - 확인할 내용: "Payment failed: reason=한도 초과" 로그
- [ ] **캡쳐 8-7:** 재고 부족 시 로그 및 PG 취소 요청
  - 시나리오: 콜백 성공 시점에 재고 0
  - 확인할 내용:
    - "Out of stock after payment success" 로그
    - PG 취소 API 호출 로그
    - Payment status: FAILED (reason="재고 부족")
- [ ] **캡쳐 8-8:** 멱등성 테스트 - 중복 콜백 무시 로그
  - 시나리오: 동일 transactionKey로 콜백 2회 호출
  - 확인할 내용: "Already processed payment" 로그

---

### 스케줄러 기반 주문 대사 (복구 로직)

**🎯 작업: 콜백 누락 케이스 복구**

```kotlin
// PaymentReconciliationScheduler.kt
@Component
class PaymentReconciliationScheduler(
    private val orderRepository: OrderRepository,
    private val paymentRepository: PaymentRepository,
    private val productService: ProductService,
    private val pgClient: PgClient
) {

    private val logger = LoggerFactory.getLogger(javaClass)

    @Scheduled(fixedDelay = 60000) // 1분마다
    fun reconcileStaleOrders() {
        val cutoffTime = LocalDateTime.now().minusMinutes(10)

        // PENDING 상태가 10분 이상인 주문들
        val staleOrders = orderRepository.findByStatusAndCreatedAtBefore(
            OrderStatus.PENDING,
            cutoffTime
        )

        logger.info("Found ${staleOrders.size} stale orders")

        staleOrders.forEach { order ->
            try {
                reconcileOrder(order)
            } catch (e: Exception) {
                logger.error("Failed to reconcile order: ${order.id}", e)
            }
        }
    }

    @Transactional
    fun reconcileOrder(order: Order) {
        val payments = paymentRepository.findByOrderId(order.id!!)
        val pendingPayment = payments.firstOrNull { it.status == PaymentStatus.PENDING }
            ?: run {
                // Payment가 없거나 모두 실패 → Order도 실패 처리
                order.fail()
                logger.info("No pending payment found. Order marked as FAILED: ${order.id}")
                return
            }

        if (pendingPayment.transactionKey == null) {
            // PG 요청 자체가 실패한 케이스
            pendingPayment.markAsFailed("PG 요청 실패")
            order.fail()
            logger.info("Payment request failed. Order marked as FAILED: ${order.id}")
            return
        }

        // PG에 실제 상태 확인
        try {
            val pgStatus = pgClient.getPaymentStatus(pendingPayment.transactionKey!!)

            when (pgStatus.status) {
                "SUCCESS" -> {
                    // 콜백 누락 케이스 → 수동 처리
                    try {
                        productService.decreaseStock(order.items)
                        pendingPayment.markAsSuccess()
                        order.complete()
                        logger.info("Recovered payment: orderId=${order.id}, transactionKey=${pendingPayment.transactionKey}")
                    } catch (e: OutOfStockException) {
                        pgClient.cancelPayment(pendingPayment.transactionKey!!)
                        pendingPayment.markAsFailed("재고 부족")
                        order.fail()
                        logger.error("Out of stock during reconciliation: orderId=${order.id}")
                    }
                }
                "FAILED" -> {
                    pendingPayment.markAsFailed(pgStatus.failureReason ?: "알 수 없는 오류")
                    order.fail()
                    logger.info("Payment failed during reconciliation: orderId=${order.id}")
                }
                else -> {
                    // 아직 PENDING → 계속 대기
                    logger.debug("Payment still pending: orderId=${order.id}")
                }
            }
        } catch (e: Exception) {
            // PG 조회도 실패 → 다음 주기에 재시도
            logger.warn("Failed to query PG status: orderId=${order.id}", e)
        }
    }
}

// OrderRepository에 추가
interface OrderRepository : JpaRepository<Order, Long> {
    fun findByStatusAndCreatedAtBefore(status: OrderStatus, time: LocalDateTime): List<Order>
}
```

**💡 스케줄러 전략:**

- 1분마다 실행
- 10분 이상 PENDING인 주문 확인
- PG 상태 직접 조회
- 콜백 누락 케이스 복구

**📸 작업 후 제공할 캡쳐:**
- [ ] **캡쳐 9-1:** PaymentReconciliationScheduler 전체 코드
  - 파일 위치: `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentReconciliationScheduler.kt`
  - 확인할 내용:
    - `@Scheduled(fixedDelay = 60000)` - 1분마다 실행
    - `findByStatusAndCreatedAtBefore()` - 10분 이상 PENDING 주문 조회
    - PG 상태 조회: `pgClient.getPaymentStatus()`
    - 상태별 처리: SUCCESS → 재고 차감, FAILED → 실패 처리
- [ ] **캡쳐 9-2:** @EnableScheduling 설정
  - 파일 위치: Application 메인 클래스 또는 별도 Config 클래스
  - 확인할 내용: `@EnableScheduling` 어노테이션
- [ ] **캡쳐 9-3:** OrderRepository에 추가된 메서드
  ```kotlin
  fun findByStatusAndCreatedAtBefore(status: OrderStatus, time: LocalDateTime): List<Order>
  ```
- [ ] **캡쳐 9-4:** 스케줄러 실행 로그 (정상 케이스)
  - 확인할 내용:
    - "Found X stale orders" 로그
    - "No pending payment found" 또는 "Payment still pending" 로그
- [ ] **캡쳐 9-5:** 콜백 누락 시나리오 테스트
  - **시나리오 설정:**
    1. 주문 생성 + PG 요청 성공 (Order: PENDING, Payment: PENDING)
    2. PG Simulator에서 콜백을 의도적으로 안 보냄
    3. 10분 대기 (또는 테스트용으로 스케줄러 주기 짧게 설정)
    4. 스케줄러 자동 실행
  - **캡쳐할 로그:**
    - "Found 1 stale orders" 로그
    - PG 상태 조회 로그: "GET /api/v1/payments/{transactionKey}"
    - PG 응답: "SUCCESS"
    - "Recovered payment: orderId=X, transactionKey=Y" 로그
- [ ] **캡쳐 9-6:** 복구 후 DB 상태 확인
  - 테이블: orders, commerce_payments
  - 확인할 내용:
    - Order status: PENDING → COMPLETED
    - Payment status: PENDING → SUCCESS
    - Product stock: 차감됨
- [ ] **캡쳐 9-7:** 스케줄러에서 PG 조회 실패 시 로그
  - 시나리오: PG Simulator 종료 상태에서 스케줄러 실행
  - 확인할 내용: "Failed to query PG status" 로그 (다음 주기에 재시도)

---

## 테스트 전략

### 통합 테스트 시나리오

**🎯 작업: 각 시나리오별 테스트 실행 및 결과 확인**

**시나리오 1: 정상 결제 플로우**

```text
1. 주문 생성 (재고 검증만)
2. PG 결제 요청 성공
3. Payment PENDING, Order PENDING
4. 콜백 수신 (SUCCESS)
5. 재고 차감
6. Payment SUCCESS, Order COMPLETED
```

**📸 제공할 캡쳐:**
- [ ] **캡쳐 T1-1:** 주문 생성 API 요청 (HTTP 파일 또는 Postman)
  ```http
  POST http://localhost:8080/api/v1/orders
  X-USER-ID: test-user-123
  Content-Type: application/json

  {
    "items": [{"productId": 1, "quantity": 1}],
    "cardInfo": {
      "cardType": "SAMSUNG",
      "cardNo": "1234-5678-9814-1451"
    }
  }
  ```
- [ ] **캡쳐 T1-2:** 주문 생성 API 응답
  - 확인할 내용: orderId, status: "PENDING", message: "결제가 진행 중입니다"
- [ ] **캡쳐 T1-3:** PG 요청 성공 로그 (commerce-api)
  - 확인할 내용: "POST http://localhost:8081/api/v1/payments" 호출 성공
- [ ] **캡쳐 T1-4:** PG Simulator가 콜백 전송하는 로그 (pg-simulator)
  - 확인할 내용: "POST http://localhost:8080/api/v1/payments/callback" 호출
- [ ] **캡쳐 T1-5:** 콜백 수신 로그 (commerce-api)
  - 확인할 내용: "Payment success" 메시지, transactionKey
- [ ] **캡쳐 T1-6:** 재고 차감 로그
  - 확인할 내용: "Product stock decreased: productId=1, before=10, after=9"
- [ ] **캡쳐 T1-7:** DB 최종 상태 (DBeaver/DataGrip)
  - 테이블 3개 조회:
    - `orders`: status=COMPLETED
    - `commerce_payments`: status=SUCCESS, transactionKey 있음
    - `products`: stock 1 감소

**시나리오 2: PG 타임아웃 발생**

```text
1. 주문 생성
2. PG 요청 → 3초 타임아웃
3. Fallback 실행
4. Payment FAILED, Order FAILED
5. 재고는 그대로 (차감 안 됨)
```

**📸 제공할 캡쳐:**
- [ ] **캡쳐 T2-1:** 타임아웃 시나리오 설정
  - 방법: PG Simulator에서 응답 지연 강제 (Thread.sleep 추가) 또는 PG Simulator 종료
- [ ] **캡쳐 T2-2:** 타임아웃 발생 로그
  - 확인할 내용:
    - "java.net.SocketTimeoutException: Read timed out" 또는
    - "TimeoutException" 또는
    - "CircuitBreaker is OPEN"
- [ ] **캡쳐 T2-3:** Fallback 메서드 실행 로그
  - 확인할 내용: "paymentFallback executed" 또는 "PG 시스템 일시 불가"
- [ ] **캡쳐 T2-4:** 사용자에게 반환된 에러 응답
  ```json
  {
    "success": false,
    "errorCode": "PAYMENT_UNAVAILABLE",
    "message": "현재 카드 결제가 불가능합니다. 잠시 후 다시 시도해주세요."
  }
  ```
- [ ] **캡쳐 T2-5:** DB 상태 확인 - 재고 차감 안 됨
  - 테이블 3개 조회:
    - `orders`: status=FAILED
    - `commerce_payments`: status=FAILED, failureReason="PG 시스템 일시 불가"
    - `products`: stock 변화 없음 (그대로 10)

**시나리오 3: CircuitBreaker 동작 확인**

```text
1. 연속 10번 요청 → 6번 이상 실패
2. CircuitBreaker Open
3. 이후 요청은 즉시 Fallback
4. 10초 후 Half-Open
5. 테스트 요청 2개 성공 시 Closed
```

**📸 제공할 캡쳐:**
- [ ] **캡쳐 T3-1:** 테스트 시나리오 준비
  - PG Simulator 종료
  - 연속 10회 주문 요청 스크립트 또는 반복 호출 도구 사용
- [ ] **캡쳐 T3-2:** 연속 실패 로그 (1~6회차)
  - 확인할 내용:
    - 각 요청마다 "Connection refused" 또는 "Timeout" 에러
    - Fallback 실행
    - 누적 실패율 증가
- [ ] **캡쳐 T3-3:** CircuitBreaker Open 로그 (6~7회차 이후)
  - 확인할 내용:
    - "CircuitBreaker 'pgCircuit' is OPEN and does not permit further calls"
    - "Failure rate threshold exceeded"
- [ ] **캡쳐 T3-4:** Actuator health 엔드포인트 응답 (Open 상태)
  ```http
  GET http://localhost:8080/actuator/health
  ```
  - 확인할 내용:
    ```json
    {
      "circuitBreakers": {
        "pgCircuit": {
          "state": "OPEN",
          "failureRate": "60.0%",
          "bufferedCalls": 10,
          "failedCalls": 6
        }
      }
    }
    ```
- [ ] **캡쳐 T3-5:** Circuit Open 상태에서 즉시 Fallback 실행 로그
  - 확인할 내용:
    - PG 호출 없이 바로 Fallback 실행
    - 응답 시간 매우 빠름 (1ms 이하)
- [ ] **캡쳐 T3-6:** 10초 대기 후 Half-Open 전환 로그
  - 확인할 내용: "CircuitBreaker 'pgCircuit' changed state from OPEN to HALF_OPEN"
- [ ] **캡쳐 T3-7:** Half-Open에서 테스트 호출 (PG Simulator 재시작 후)
  - 2회 연속 성공 시: "CircuitBreaker 'pgCircuit' changed state from HALF_OPEN to CLOSED"
  - 실패 시: "CircuitBreaker 'pgCircuit' changed state from HALF_OPEN to OPEN"
- [ ] **캡쳐 T3-8:** Actuator health 엔드포인트 응답 (Closed 상태)
  - 확인할 내용: `"state": "CLOSED"`

**시나리오 4: 콜백 누락 시 스케줄러로 복구**

```text
1. 주문 생성 → PG 요청 성공
2. 콜백을 의도적으로 안 보냄
3. 10분 대기
4. 스케줄러 실행 → PG 상태 조회
5. 결제 성공 확인 → 재고 차감
6. Payment SUCCESS, Order COMPLETED
```

**📸 제공할 캡쳐:**
- [ ] **캡쳐 T4-1:** 콜백 누락 시나리오 설정
  - PG Simulator의 콜백 전송 코드 주석 처리 또는
  - commerce-api의 콜백 URL을 잘못된 주소로 설정 (`callbackUrl: "http://invalid"`)
- [ ] **캡쳐 T4-2:** 주문 생성 후 DB 상태 (PENDING)
  - 테이블 확인:
    - `orders`: status=PENDING, created_at 확인
    - `commerce_payments`: status=PENDING, transactionKey 있음
- [ ] **캡쳐 T4-3:** 10분 경과 (테스트용으로 스케줄러 주기를 10초로 설정 권장)
  - application.yml에서 테스트 설정:
    ```yaml
    # @Scheduled(fixedDelay = 10000) 로 변경
    ```
- [ ] **캡쳐 T4-4:** 스케줄러 실행 로그
  - 확인할 내용: "Found 1 stale orders" (10분 이상 PENDING인 주문 발견)
- [ ] **캡쳐 T4-5:** PG 상태 조회 로그
  - 확인할 내용:
    - "GET http://localhost:8081/api/v1/payments/{transactionKey}"
    - PG 응답: `{"status": "SUCCESS", "amount": "10000"}`
- [ ] **캡쳐 T4-6:** 복구 처리 로그
  - 확인할 내용:
    - "Recovered payment: orderId=X, transactionKey=Y"
    - 재고 차감 로그
    - Payment SUCCESS, Order COMPLETED 로그
- [ ] **캡쳐 T4-7:** DB 최종 상태 (복구 후)
  - 테이블 3개 조회:
    - `orders`: status=PENDING → COMPLETED, updated_at 변경
    - `commerce_payments`: status=PENDING → SUCCESS
    - `products`: stock 차감됨

**시나리오 5: 결제 실패 (한도 초과, 잘못된 카드)**

```text
1. 주문 생성 → PG 요청
2. 콜백 수신 (FAILED - 한도 초과)
3. Payment FAILED, Order FAILED
4. 재고는 차감 안 됨
```

**📸 제공할 캡쳐:**
- [ ] **캡쳐 T5-1:** PG Simulator의 실패 응답 설정 확인
  - PG Simulator 코드에서 실패 케이스 확인:
    - 성공: 70%, 한도 초과: 20%, 잘못된 카드: 10%
- [ ] **캡쳐 T5-2:** 주문 생성 후 콜백 수신 (FAILED)
  - 콜백 요청 body:
    ```json
    {
      "transactionKey": "20250816:TR:xxx",
      "status": "FAILED",
      "failureReason": "한도 초과"
    }
    ```
- [ ] **캡쳐 T5-3:** 콜백 처리 로그 (실패 케이스)
  - 확인할 내용:
    - "Payment failed: orderId=X, reason=한도 초과"
    - Payment.markAsFailed() 실행
    - Order.fail() 실행
- [ ] **캡쳐 T5-4:** DB 최종 상태
  - 테이블 3개 조회:
    - `orders`: status=FAILED
    - `commerce_payments`: status=FAILED, failureReason="한도 초과"
    - `products`: stock 변화 없음 (재고 차감 안 됨)
- [ ] **캡쳐 T5-5:** (Optional) 다른 실패 케이스 - "잘못된 카드"
  - 동일한 방식으로 failureReason="잘못된 카드" 테스트

**시나리오 6: 콜백 타이밍에 재고 부족**

```text
1. 주문 A, B가 동시에 마지막 1개 상품 주문
2. A 콜백 먼저 도착 → 재고 차감 성공
3. B 콜백 도착 → 재고 부족!
4. PG 취소 요청
5. B Payment FAILED, Order FAILED
```

**📸 제공할 캡쳐:**
- [ ] **캡쳐 T6-1:** 시나리오 설정 - 마지막 재고 1개 상태
  - DB에서 특정 상품의 stock을 1로 설정
  ```sql
  UPDATE products SET stock = 1 WHERE id = 1;
  ```
- [ ] **캡쳐 T6-2:** 동시 주문 요청 2개 (거의 동시에 실행)
  - 방법 1: 병렬 HTTP 요청 도구 사용 (JMeter, k6 등)
  - 방법 2: 2개의 터미널에서 동시에 curl 실행
  ```bash
  # 터미널 1
  curl -X POST http://localhost:8080/api/v1/orders ...

  # 터미널 2 (동시 실행)
  curl -X POST http://localhost:8080/api/v1/orders ...
  ```
- [ ] **캡쳐 T6-3:** 첫 번째 주문 콜백 성공 로그
  - 확인할 내용:
    - "Payment success: orderId=1"
    - "Product stock decreased: productId=1, before=1, after=0"
    - Order COMPLETED, Payment SUCCESS
- [ ] **캡쳐 T6-4:** 두 번째 주문 콜백 시 재고 부족 로그
  - 확인할 내용:
    - "Out of stock after payment success: orderId=2"
    - OutOfStockException 발생
- [ ] **캡쳐 T6-5:** PG 취소 요청 로그
  - 확인할 내용:
    - "POST http://localhost:8081/api/v1/payments/{transactionKey}/cancel" 호출
    - PG 취소 응답 성공
- [ ] **캡쳐 T6-6:** 두 번째 주문 최종 상태
  - 테이블 확인:
    - `orders`: orderId=2, status=FAILED
    - `commerce_payments`: status=FAILED, failureReason="재고 부족"
- [ ] **캡쳐 T6-7:** (Optional) CS 알림 로그
  - 확인할 내용: "TODO: CS 팀 알림" 주석 또는 실제 알림 전송 로그

---

## 트러블슈팅

### 실제 구현하며 겪은 문제들

**💡 작성 가이드:**
각 문제마다 아래 형식으로 작성하세요.

```markdown
### 문제: [간단한 제목]

**상황:**
- 무엇을 하려고 했는가
- 어떤 에러가 발생했는가

**원인:**
- 왜 이 문제가 발생했는가
- 어떤 부분을 놓쳤는가

**해결:**
- 어떻게 해결했는가
- 어떤 코드를 수정했는가

**배운 점:**
- 이 경험에서 무엇을 배웠는가
```

**📸 제공할 캡쳐 및 내용:**

각 문제마다 **실제 에러 로그 스크린샷**과 **해결 후 코드**를 함께 첨부하세요.

- [ ] **문제 1: [실제 겪은 문제의 제목]**
  - 📸 에러 발생 시 로그 스크린샷
  - 📸 문제가 되었던 코드 (before)
  - 📸 해결한 코드 (after)
  - 설명: 상황, 원인, 해결, 배운 점

- [ ] **문제 2: [실제 겪은 문제의 제목]**
  - 📸 에러 발생 시 로그 스크린샷
  - 📸 문제가 되었던 코드 (before)
  - 📸 해결한 코드 (after)
  - 설명: 상황, 원인, 해결, 배운 점

- [ ] **문제 3: [실제 겪은 문제의 제목]**
  - 📸 에러 발생 시 로그 스크린샷
  - 📸 문제가 되었던 코드 (before)
  - 📸 해결한 코드 (after)
  - 설명: 상황, 원인, 해결, 배운 점

**예시 (참고용):**

### 문제: FeignClient에서 Fallback이 실행되지 않음

**상황:**
- CircuitBreaker가 Open 상태인데도 Fallback 메서드가 호출되지 않음
- 대신 500 에러가 사용자에게 그대로 반환됨

**원인:**
- @CircuitBreaker 어노테이션의 fallbackMethod 이름을 잘못 입력
- 메서드 시그니처(파라미터)가 일치하지 않음

**해결:**
```kotlin
// Before - 잘못된 fallbackMethod 이름
@CircuitBreaker(name = "pgCircuit", fallbackMethod = "fallback")
fun requestCardPayment(...): Payment

private fun paymentFallback(...): Payment  // 이름 불일치!

// After - 정확한 이름으로 수정
@CircuitBreaker(name = "pgCircuit", fallbackMethod = "paymentFallback")
fun requestCardPayment(order: Order, userId: String, cardInfo: CardInfo): Payment

private fun paymentFallback(order: Order, userId: String, cardInfo: CardInfo, ex: Exception): Payment
// 파라미터 + Exception 추가
```

**배운 점:**
- Fallback 메서드는 원본 메서드와 동일한 파라미터 + Throwable/Exception을 받아야 함
- 이름이나 시그니처가 틀리면 컴파일 에러 없이 런타임에 무시됨

---

## 최종 회고

### 이번 주에 잘한 점

**💡 작성 가이드:**

- 기술적으로 잘 적용한 부분
- 설계 결정이 적절했던 부분
- 예상보다 잘 동작한 부분

**📸 제공할 캡쳐:**
- [ ] **캡쳐 R1:** 가장 뿌듯했던 테스트 결과 스크린샷
  - 예: 콜백 누락 → 스케줄러 복구 성공 시나리오
  - 예: CircuitBreaker Open → Half-Open → Closed 전환 성공
  - 로그와 DB 상태 변화를 함께 보여주는 캡쳐
- [ ] **캡쳐 R2:** (Optional) CircuitBreaker 상태 모니터링
  - Actuator metrics 또는 Prometheus/Grafana 대시보드
  - Circuit 상태 변화 그래프
- [ ] **캡쳐 R3:** 전체 시스템 플로우 다이어그램
  - 정상 플로우: 주문 생성 → PG 요청 → 콜백 → 재고 차감 → 주문 완료
  - 실패 플로우: Timeout → Fallback → 재고 보호
  - 복구 플로우: 콜백 누락 → 스케줄러 → PG 조회 → 복구
  - 도구: draw.io, Excalidraw, 손그림, Mermaid 다이어그램 등

---

### 아쉬운 점과 개선 방향

**💡 작성 가이드:**

- 시간 부족으로 못 한 것
- 더 잘할 수 있었던 부분
- 다음에 개선하고 싶은 부분

**예시:**

- 재고 점유 기능 (Redis TTL)은 구현 못 함
- 보안 검증 (PG 서명)은 생략
- 모니터링/알림 부족

---

### 다음에 시도해보고 싶은 것

**💡 학습 주제:**

- Saga 패턴으로 분산 트랜잭션 관리
- 보상 트랜잭션 (Compensating Transaction)
- 이벤트 소싱 (Event Sourcing)
- CQRS 패턴
- 결제 이력 조회 최적화 (Read Model)

---

## 참고 자료

- [Resilience4j 공식 문서](https://resilience4j.readme.io/)
- [Spring Cloud OpenFeign](https://docs.spring.io/spring-cloud-openfeign/reference/)
- [Circuit Breaker Pattern - Martin Fowler](https://martinfowler.com/bliki/CircuitBreaker.html)
- [Failure-Ready Systems - 수업 자료](.codeguide/round6/Failure-Ready%20Systems.md)
- [멘토님 코멘트](.codeguide/round6/mentor_comment.md)

---

## 📖 빠른 참조 가이드

### 주요 파일 위치 맵

```
apps/commerce-api/src/main/kotlin/com/loopers/
├── domain/
│   ├── payment/
│   │   ├── Payment.kt                        # 캡쳐 3-2
│   │   ├── PaymentStatus.kt                  # 캡쳐 3-3
│   │   ├── PaymentMethod.kt                  # 캡쳐 3-4
│   │   ├── PaymentService.kt                 # 캡쳐 6-2, 6-3
│   │   ├── PaymentCallbackService.kt         # 캡쳐 8-2
│   │   ├── PaymentReconciliationScheduler.kt # 캡쳐 9-1
│   │   └── strategy/
│   │       ├── PgStrategy.kt                 # 캡쳐 4-1
│   │       └── SimulatorPgStrategy.kt        # 캡쳐 4-2
│   └── order/
│       └── OrderService.kt                   # 캡쳐 7-1
├── infrastructure/
│   └── pg/
│       └── PgSimulatorClient.kt              # 캡쳐 5-2
├── api/v1/
│   └── PaymentCallbackController.kt          # 캡쳐 8-1
└── config/
    ├── FeignConfig.kt                        # 캡쳐 5-4
    └── PgClientConfig.kt                     # 캡쳐 5-3

apps/commerce-api/src/main/resources/
└── application.yml                           # 캡쳐 5-5, 6-1

docker/
└── 01-schema.sql                             # 캡쳐 3-5

build.gradle.kts                              # 캡쳐 5-1
```

### 주요 API 엔드포인트

| 엔드포인트 | 메서드 | 용도 | 관련 캡쳐 |
|-----------|--------|-----|----------|
| `/api/v1/orders` | POST | 주문 생성 (카드 결제) | T1-1 |
| `/api/v1/payments/callback` | POST | PG 결제 콜백 수신 | 8-1 |
| `/actuator/health` | GET | CircuitBreaker 상태 확인 | 6-6, T3-4 |
| `http://localhost:8081/api/v1/payments` | POST | PG 결제 요청 (Simulator) | 1-3, 5-6 |
| `http://localhost:8081/api/v1/payments/{key}` | GET | PG 결제 상태 조회 | T4-5 |

### Resilience4j 주요 설정값

| 설정 | 권장값 | 이유 | 관련 섹션 |
|------|--------|-----|----------|
| `failure-rate-threshold` | 50% | PG 성공률 60%, 50% 초과 시 비정상 | 6-1 |
| `slow-call-duration-threshold` | 2s | 정상 지연 100~500ms, 2초 초과 시 느림 | 6-1 |
| `wait-duration-in-open-state` | 10s | PG 복구 대기 시간 | 6-1 |
| `readTimeout` | 3s | 콜백 방식이므로 3초 내 응답 충분 | 5-3 |
| `connectTimeout` | 1s | 연결만 빠르게 | 5-3 |

### 테스트 시나리오별 시간 예상

| 시나리오 | 예상 시간 | 난이도 | 우선순위 |
|---------|----------|--------|---------|
| 1. 정상 결제 | 10분 | ⭐ | 최우선 |
| 2. PG 타임아웃 | 5분 | ⭐ | 최우선 |
| 3. CircuitBreaker | 15분 | ⭐⭐ | 필수 |
| 4. 콜백 누락 복구 | 20분 | ⭐⭐⭐ | 필수 |
| 5. 결제 실패 | 5분 | ⭐ | 필수 |
| 6. 재고 부족 | 10분 | ⭐⭐ | 선택 |

---

## 체크리스트 최종 확인

### PG 연동 대응

- [ ] PG 연동 API는 RestTemplate 혹은 FeignClient로 외부 시스템을 호출한다.
- [ ] 응답 지연에 대해 타임아웃을 설정하고, 실패 시 적절한 예외 처리 로직을 구현한다.
- [ ] 결제 요청에 대한 실패 응답에 대해 적절한 시스템 연동을 진행한다.
- [ ] 콜백 방식 + 결제 상태 확인 API를 활용해 적절하게 시스템과 결제정보를 연동한다.

### Resilience 설계

- [ ] 서킷 브레이커 혹은 재시도 정책을 적용하여 장애 확산을 방지한다.
- [ ] 외부 시스템 장애 시에도 내부 시스템은 정상적으로 응답하도록 보호한다.
- [ ] 콜백이 오지 않더라도, 일정 주기 혹은 수동 API 호출로 상태를 복구할 수 있다.
- [ ] PG에 대한 요청이 타임아웃에 의해 실패되더라도 해당 결제건에 대한 정보를 확인하여 정상적으로 시스템에 반영한다.

### 재고 차감 전략

- [ ] 콜백 시점에 재고 차감 (멘토님 방식)
- [ ] PG 장애 시 재고 묶이지 않음 (GMV 보호)
- [ ] 재고 부족 시 PG 취소 요청

---

## 완성도 체크

**📸 최종 제출 전 확인:**

### 코드 관련
- [ ] 모든 도메인 엔티티 코드 캡쳐 완료 (Payment, PaymentStatus, PaymentMethod)
- [ ] 모든 서비스 레이어 코드 캡쳐 완료 (PaymentService, PaymentCallbackService, OrderService)
- [ ] 모든 인프라 코드 캡쳐 완료 (PgSimulatorClient, FeignConfig)
- [ ] 전략 패턴 코드 캡쳐 완료 (PgStrategy, SimulatorPgStrategy)
- [ ] 스케줄러 코드 캡쳐 완료 (PaymentReconciliationScheduler)

### 설정 파일
- [ ] application.yml (Resilience4j 설정) 캡쳐 완료
- [ ] application.yml (PG 설정) 캡쳐 완료
- [ ] build.gradle.kts (의존성 추가) 캡쳐 완료
- [ ] DB 스키마 (01-schema.sql) 캡쳐 완료

### 테스트 시나리오 (총 6개)
- [ ] **시나리오 1:** 정상 결제 플로우 (7개 캡쳐)
- [ ] **시나리오 2:** PG 타임아웃 (5개 캡쳐)
- [ ] **시나리오 3:** CircuitBreaker 동작 (8개 캡쳐)
- [ ] **시나리오 4:** 콜백 누락 복구 (7개 캡쳐)
- [ ] **시나리오 5:** 결제 실패 (5개 캡쳐)
- [ ] **시나리오 6:** 재고 부족 (7개 캡쳐)

### 로그 및 모니터링
- [ ] PG Simulator 실행 로그
- [ ] commerce-api 애플리케이션 로그 (주요 시나리오별)
- [ ] Actuator health 엔드포인트 응답
- [ ] DB 상태 변화 (before/after 비교)

### 문서화
- [ ] 트러블슈팅 최소 3개 작성 (에러 로그 + Before/After 코드)
- [ ] 설계 결정 이유 작성 (재고 차감 시점, Payment 도메인 분리 등)
- [ ] Resilience4j 설정값 선택 이유 작성
- [ ] 회고 작성 (잘한 점, 아쉬운 점, 다음 개선 방향)

### 다이어그램
- [ ] 재고 차감 시점 비교 플로우 다이어그램
- [ ] 전체 시스템 플로우 다이어그램 (정상/실패/복구)

### 마무리
- [ ] 모든 TODO 항목 채움 (내가 선택한 방식과 이유)
- [ ] 블로그 읽으며 흐름이 자연스러운지 확인
- [ ] 코드 스크린샷에 중요 부분 하이라이트 또는 화살표 표시
- [ ] 각 캡쳐에 간단한 설명 추가
- [ ] 전체 분량이 너무 길지 않은지 확인 (필요시 핵심만 남기고 요약)
