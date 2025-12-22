# PaymentCallbackService 전략 패턴 리팩토링 제안

## 현재 방식 vs 전략 패턴

### ❌ 현재 방식 (FIX_GUIDE)
```kotlin
@Transactional
fun handlePaymentCallback(callback: PaymentCallback) {
    val payment = paymentRepository.findByIdOrThrow(callback.orderId)

    when (callback.status) {
        "success" -> {
            payment.markAsSuccess()
            val order = orderRepository.findByIdOrThrow(callback.orderId)
            eventPublisher.publishEvent(PaymentCompletedEvent(...))
        }
        else -> {
            payment.markAsFailed(callback.message ?: "결제 실패")
            eventPublisher.publishEvent(PaymentFailedEvent(...))
        }
    }

    paymentRepository.save(payment)
}
```

**문제점**:
- 성공/실패 로직이 한 메서드에 혼재
- 새로운 상태 추가 시 when 분기 증가
- 각 분기 로직이 길어지면 메서드 비대화
- 단위 테스트 복잡도 증가

---

## ✅ 전략 패턴 방식 (제안)

### 1. 전략 인터페이스 정의

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/callback/PaymentCallbackStrategy.kt`

```kotlin
package com.loopers.domain.payment.callback

import com.loopers.domain.payment.Payment
import com.loopers.domain.payment.PaymentCallback

interface PaymentCallbackStrategy {
    fun supports(status: String): Boolean
    fun handle(payment: Payment, callback: PaymentCallback)
}
```

---

### 2. 성공 전략 구현

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/callback/PaymentSuccessStrategy.kt`

```kotlin
package com.loopers.domain.payment.callback

import com.loopers.domain.order.OrderRepository
import com.loopers.domain.payment.Payment
import com.loopers.domain.payment.PaymentCallback
import com.loopers.domain.payment.event.PaymentCompletedEvent
import org.springframework.context.ApplicationEventPublisher
import org.springframework.stereotype.Component
import java.time.Instant

@Component
class PaymentSuccessStrategy(
    private val orderRepository: OrderRepository,
    private val eventPublisher: ApplicationEventPublisher,
) : PaymentCallbackStrategy {

    override fun supports(status: String): Boolean = status == "success"

    override fun handle(payment: Payment, callback: PaymentCallback) {
        payment.markAsSuccess()

        val order = orderRepository.findByIdOrThrow(callback.orderId)

        eventPublisher.publishEvent(
            PaymentCompletedEvent(
                paymentId = requireNotNull(payment.id) { "Payment ID는 null일 수 없습니다" },
                orderId = callback.orderId,
                memberId = order.memberId,
                amount = payment.amount.amount,
                completedAt = Instant.now()
            )
        )
    }
}
```

---

### 3. 실패 전략 구현

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/callback/PaymentFailureStrategy.kt`

```kotlin
package com.loopers.domain.payment.callback

import com.loopers.domain.payment.Payment
import com.loopers.domain.payment.PaymentCallback
import com.loopers.domain.payment.event.PaymentFailedEvent
import org.springframework.context.ApplicationEventPublisher
import org.springframework.stereotype.Component
import java.time.Instant

@Component
class PaymentFailureStrategy(
    private val eventPublisher: ApplicationEventPublisher,
) : PaymentCallbackStrategy {

    override fun supports(status: String): Boolean =
        status in listOf("failed", "error", "canceled")

    override fun handle(payment: Payment, callback: PaymentCallback) {
        payment.markAsFailed(callback.message ?: "결제 실패")

        eventPublisher.publishEvent(
            PaymentFailedEvent(
                orderId = callback.orderId,
                reason = callback.message ?: "결제 실패",
                failedAt = Instant.now()
            )
        )
    }
}
```

---

### 4. PaymentCallbackService 리팩토링

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackService.kt`

```kotlin
package com.loopers.domain.payment

import com.loopers.domain.payment.callback.PaymentCallbackStrategy
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
class PaymentCallbackService(
    private val paymentRepository: PaymentRepository,
    private val strategies: List<PaymentCallbackStrategy>, // Spring이 자동 주입
) {

    @Transactional
    fun handlePaymentCallback(callback: PaymentCallback) {
        val payment = paymentRepository.findByIdOrThrow(callback.orderId)

        val strategy = strategies.firstOrNull { it.supports(callback.status) }
            ?: throw IllegalArgumentException("지원하지 않는 결제 상태입니다: ${callback.status}")

        strategy.handle(payment, callback)

        paymentRepository.save(payment)
    }
}
```

---

## 📊 비교

| | 기존 when 방식 | 전략 패턴 |
|---|---|---|
| **책임 분리** | ❌ 한 메서드에 모든 로직 | ✅ 각 전략이 독립적 |
| **확장성** | ❌ when 분기 추가 필요 | ✅ 새 전략 클래스만 추가 |
| **테스트** | ❌ 한 테스트에서 모든 분기 | ✅ 각 전략을 독립 테스트 |
| **의존성** | ❌ 모든 의존성 주입 | ✅ 필요한 의존성만 |
| **코드 길이** | ❌ 메서드가 길어짐 | ✅ 각 클래스가 짧음 |
| **가독성** | ⚠️ 보통 | ✅ 각 전략의 목적 명확 |

---

## 🎯 장점

### 1. **단일 책임 원칙 (SRP)**
각 전략 클래스가 하나의 상태만 처리

### 2. **개방-폐쇄 원칙 (OCP)**
새로운 상태 추가 시 기존 코드 수정 불필요
```kotlin
// 새로운 전략 추가 시
@Component
class PaymentPendingStrategy(...) : PaymentCallbackStrategy {
    override fun supports(status: String) = status == "pending"
    override fun handle(payment: Payment, callback: PaymentCallback) {
        // pending 처리 로직
    }
}
// PaymentCallbackService는 수정 불필요! (자동으로 strategies에 추가됨)
```

### 3. **의존성 최소화**
각 전략이 필요한 의존성만 주입받음
- Success: `orderRepository` + `eventPublisher`
- Failure: `eventPublisher`만

### 4. **테스트 용이성**
```kotlin
// 각 전략을 독립적으로 테스트
class PaymentSuccessStrategyTest {
    @Test
    fun `success 상태를 지원한다`() {
        assertThat(strategy.supports("success")).isTrue()
    }

    @Test
    fun `결제를 성공 처리하고 이벤트를 발행한다`() {
        // 성공 케이스만 집중 테스트
    }
}
```

### 5. **확장 가능성**
```kotlin
// 미래에 추가될 수 있는 전략들
@Component
class PaymentRefundStrategy(...) : PaymentCallbackStrategy
@Component
class PaymentPartialSuccessStrategy(...) : PaymentCallbackStrategy
@Component
class PaymentCanceledStrategy(...) : PaymentCallbackStrategy
```

---

## 🚀 마이그레이션 가이드

### Step 1: 인터페이스 및 전략 클래스 생성
1. `PaymentCallbackStrategy.kt`
2. `PaymentSuccessStrategy.kt`
3. `PaymentFailureStrategy.kt`

### Step 2: PaymentCallbackService 리팩토링
- 기존 when 로직을 전략 패턴으로 교체

### Step 3: 테스트 작성
- 각 전략별 단위 테스트
- PaymentCallbackService 통합 테스트

### Step 4: 기존 테스트 확인
- 기존 테스트가 여전히 통과하는지 확인

---

## 💡 추천

**전략 패턴 사용을 강력히 추천합니다!**

이유:
1. ✅ **확장성**: 새로운 결제 상태 추가가 매우 쉬움
2. ✅ **유지보수성**: 각 로직이 독립적이라 변경 영향 최소화
3. ✅ **테스트**: 각 전략을 독립적으로 테스트 가능
4. ✅ **가독성**: 각 전략의 목적이 명확
5. ✅ **의존성**: 필요한 의존성만 주입

단, **단순한 2-3개 분기**라면 when도 괜찮지만,
**4개 이상의 상태**나 **각 분기 로직이 복잡**하면 전략 패턴이 훨씬 낫습니다.

현재 코드는 향후 `pending`, `canceled`, `refund` 등의 상태가 추가될 가능성이 있으므로
**전략 패턴이 더 적합**합니다!
