# Code Quality Improvements - Round 5 리뷰 기반

> 📅 작성일: 2025-12-04
>
> 📋 Round 5 Code Rabbit 리뷰에서 지적된 사항 중 Round 6에 적용 가능한 개선사항 정리

---

## ✅ 즉시 적용 가능한 개선사항

### 1. 🔥 Pattern 성능 개선 (High Priority)

**문제:**
- `Email.kt`에서 `EMAIL_PATTERN`이 인스턴스 필드로 정의됨
- Email 객체 생성할 때마다 Pattern 재컴파일 (비용이 큰 작업)

**현재 코드:**
```kotlin
// Email.kt
@Embeddable
class Email(email: String) {
    @Transient
    private val EMAIL_PATTERN: Pattern = Pattern.compile("^[a-zA-Z0-9_+&*-]+(?:\\.[a-zA-Z0-9_+&*-]+)*@(?:[a-zA-Z0-9-]+\\.)+[a-zA-Z]{2,7}$")
    // ...
}
```

**개선 코드:**
```kotlin
// Email.kt
@Embeddable
class Email(email: String) {

    @Column(name = "email", nullable = false, length = 100, unique = true)
    var email: String = email
        protected set

    init {
        require(EMAIL_PATTERN.matcher(email).matches()) {
            "유효하지 않은 이메일 형식입니다: $email"
        }
    }

    companion object {
        private val EMAIL_PATTERN: Pattern = Pattern.compile(
            "^[a-zA-Z0-9_+&*-]+(?:\\.[a-zA-Z0-9_+&*-]+)*@(?:[a-zA-Z0-9-]+\\.)+[a-zA-Z]{2,7}$"
        )
    }
}
```

**이점:**
- Pattern 객체가 클래스당 1개만 생성됨 (메모리 절약)
- 성능 향상 (매번 컴파일하지 않음)

**적용 위치:**
- `apps/commerce-api/src/main/kotlin/com/loopers/domain/shared/Email.kt`

---

### 2. 🧹 미사용 Import 제거

**Round 6에서 확인 필요:**

#### Payment 관련 파일
```kotlin
// 확인 필요: 미사용 import가 있는지 체크
// PaymentService.kt
// PaymentCallbackService.kt
// SimulatorPgStrategy.kt
```

**검증 방법:**
```bash
# IntelliJ에서 자동 정리
Ctrl+Alt+O (Windows/Linux)
Cmd+Option+O (Mac)

# 또는 코드 인스펙션 실행
```

---

### 3. 🛡️ Null 안전성 개선

**문제:**
- JPA 엔티티 ID는 영속화 전에 null일 수 있음
- `product.id`, `order.id` 등을 직접 사용 시 null 처리 필요

**Round 6에서 적용 예시:**

```kotlin
// PaymentService.kt (현재)
val payment = Payment.createCardPayment(
    orderId = order.id!!,  // ⚠️ 위험: order가 영속화 안 되면 NPE
    amount = order.finalAmount,
    transactionKey = pgResponse.transactionKey,
    cardType = cardType,
    cardNo = cardNo
)
```

**개선 코드:**
```kotlin
// PaymentService.kt (개선)
val payment = Payment.createCardPayment(
    orderId = order.id ?: throw CoreException(
        ErrorType.ORDER_NOT_FOUND,
        "주문 ID가 없습니다. 주문이 저장되지 않았을 수 있습니다."
    ),
    amount = order.finalAmount,
    transactionKey = pgResponse.transactionKey,
    cardType = cardType,
    cardNo = cardNo
)
```

**적용 위치:**
- `PaymentService.kt`
- `PaymentCallbackService.kt`
- `OrderService.kt`의 카드 결제 로직

---

### 4. 📏 길이 검증 추가

**배경:**
- DB 스키마에서만 길이 제한 (`@Column(length = 200)`)
- 애플리케이션 레벨에서도 검증하면 더 명확한 에러 메시지 가능

**Round 6에 적용:**

```kotlin
// Payment.kt (개선 예시)
@Entity
@Table(name = "commerce_payments")
class Payment(
    orderId: Long,
    amount: Money,
    paymentMethod: PaymentMethod = PaymentMethod.POINT,
    transactionKey: String? = null,
    cardType: String? = null,
    cardNo: String? = null,
) : BaseEntity() {

    @Column(name = "transaction_key", length = 100)
    var transactionKey: String? = transactionKey
        .also {
            it?.let { key ->
                require(key.length <= 100) {
                    "거래 키는 100자를 초과할 수 없습니다"
                }
            }
        }
        protected set

    @Column(name = "card_type", length = 20)
    var cardType: String? = cardType
        .also {
            it?.let { type ->
                require(type.length <= 20) {
                    "카드 타입은 20자를 초과할 수 없습니다"
                }
            }
        }
        protected set

    @Column(name = "card_no", length = 20)
    var cardNo: String? = cardNo
        .also {
            it?.let { no ->
                require(no.length <= 20) {
                    "카드 번호는 20자를 초과할 수 없습니다"
                }
            }
        }
        protected set

    @Column(name = "failure_reason", length = 500)
    var failureReason: String? = null
        .also {
            it?.let { reason ->
                require(reason.length <= 500) {
                    "실패 사유는 500자를 초과할 수 없습니다"
                }
            }
        }
        protected set
}
```

**또는 더 간단하게:**
```kotlin
@Column(name = "failure_reason", length = 500)
var failureReason: String? = null
    set(value) {
        require(value == null || value.length <= 500) {
            "실패 사유는 500자를 초과할 수 없습니다"
        }
        field = value
    }
```

---

## 🚨 중요: 적용 시 주의사항

### 1. Redis KEYS 명령어 성능 이슈 (🔥 Critical)

**문제:**
- Round 5에서 `ProductCacheStore`가 `redisTemplate.keys(pattern)` 사용
- O(N) 시간 복잡도로 프로덕션에서 Redis 블로킹 가능

**Round 6에서 동일한 패턴 사용하지 않도록 주의!**

**나쁜 예시:**
```kotlin
// ❌ 사용하지 말 것
fun evictPaymentCache() {
    val pattern = "payment:*"
    val keys = redisTemplate.keys(pattern)  // 위험!
    if (keys.isNotEmpty()) {
        redisTemplate.delete(keys)
    }
}
```

**좋은 예시:**
```kotlin
// ✅ SCAN 사용
fun evictPaymentCache() {
    val pattern = "payment:*"
    val cursor = redisTemplate.scan(
        ScanOptions.scanOptions()
            .match(pattern)
            .count(100)
            .build()
    )
    cursor.use { scan ->
        val keys = scan.asSequence().toList()
        if (keys.isNotEmpty()) {
            redisTemplate.delete(keys)
        }
    }
}
```

**Import 필요:**
```kotlin
import org.springframework.data.redis.core.ScanOptions
```

---

### 2. 캐시 키에 pageSize 누락 이슈

**Round 5 문제:**
- 캐시 키에 `pageNumber`만 있고 `pageSize` 누락
- 같은 페이지 번호, 다른 사이즈 요청 시 잘못된 데이터 반환

**Round 6에서 캐시 사용 시 주의:**
```kotlin
// ❌ 나쁜 예시
fun buildCacheKey(orderId: Long, page: Int): String {
    return "orders:$orderId:page:$page"  // pageSize 누락!
}

// ✅ 좋은 예시
fun buildCacheKey(orderId: Long, page: Int, size: Int): String {
    return "orders:$orderId:page:$page:size:$size"
}
```

---

## 🔍 Round 6에서 추가로 검토할 사항

### 1. PG 관련 검증 로직

**추가 검증이 필요한 부분:**

```kotlin
// PaymentCallbackDto.kt
data class PaymentCallbackDto(
    val transactionKey: String,
    val status: String,
    val reason: String?
) {
    init {
        // 검증 추가 고려
        require(transactionKey.isNotBlank()) {
            "거래 키는 필수입니다"
        }
        require(transactionKey.length <= 100) {
            "거래 키는 100자를 초과할 수 없습니다"
        }
        require(status.isNotBlank()) {
            "상태는 필수입니다"
        }
    }

    fun isSuccess(): Boolean = status == "SUCCESS"
}
```

---

### 2. Product.id null 처리 패턴

**Round 5에서 지적된 패턴을 Round 6에도 적용:**

```kotlin
// OrderService.kt - createOrderWithCardPayment()
val productMap = productRepository.findAllByIdIn(
    orderItems.map { it.productId }
).associateBy {
    it.id ?: throw CoreException(
        ErrorType.PRODUCT_NOT_FOUND,
        "상품 ID가 없습니다"
    )
}
```

---

## 📋 적용 체크리스트

### 즉시 적용 (이번 커밋)
- [ ] Email.kt의 Pattern을 companion object로 이동
- [ ] Payment.kt 필드 길이 검증 추가
- [ ] PaymentService.kt의 order.id null 처리
- [ ] PaymentCallbackDto.kt 검증 로직 추가
- [ ] 미사용 import 정리 (전체 프로젝트)

### 검토 후 적용 (다음 커밋)
- [ ] Redis 캐시 사용 시 SCAN 패턴 적용
- [ ] ProductService.decreaseStockByOrder() null 안전성 검증
- [ ] PgDto 검증 로직 추가
- [ ] ErrorType 메시지 일관성 검토

### 테스트 후 적용
- [ ] Brand 연관관계 검증 (현재는 brandId만 저장)
- [ ] FK 제약조건 확인 (Flyway 스크립트 검토)

---

## 💬 논의가 필요한 부분

### 1. Brand 연관관계 검증 전략

**현재 상황:**
- Product가 `brandId: Long`만 저장 (FK 참조 없음)
- 존재하지 않는 brandId로 Product 생성 가능

**선택지:**

#### 옵션 A: Service 레이어에서 검증 (추천)
```kotlin
// ProductService.kt
fun createProduct(command: CreateProductCommand): Product {
    // Brand 존재 여부 검증
    if (!brandRepository.existsById(command.brandId)) {
        throw CoreException(ErrorType.BRAND_NOT_FOUND)
    }

    val product = Product(
        name = command.name,
        // ...
        brandId = command.brandId
    )
    return productRepository.save(product)
}
```

**장점:**
- 도메인 로직에서 검증
- 명확한 에러 메시지

**단점:**
- 추가 DB 쿼리 (존재 확인)

#### 옵션 B: DB FK 제약조건 유지
```sql
-- docker/01-schema.sql
ALTER TABLE products
ADD CONSTRAINT fk_products_brand
FOREIGN KEY (brand_id) REFERENCES brands(id);
```

**장점:**
- DB 레벨 무결성 보장
- 애플리케이션 로직 불필요

**단점:**
- FK 제약조건 관리 필요
- 에러 메시지가 DB 에러

#### 옵션 C: 둘 다 적용 (가장 안전)
- Service 레이어에서 먼저 검증 (명확한 에러)
- DB FK로 최종 방어선

**🤔 질문: 어떤 방식을 선호하시나요?**

---

### 2. Payment 도메인 검증 레벨

**현재:**
- 기본적인 검증만 존재 (상태 전이)

**추가 검증 고려사항:**

```kotlin
// Payment.kt
companion object {
    fun createCardPayment(
        orderId: Long,
        amount: Money,
        transactionKey: String,
        cardType: String,
        cardNo: String,
    ): Payment {
        // 검증 추가 고려
        require(orderId > 0) { "주문 ID는 0보다 커야 합니다" }
        require(amount.amount > 0L) { "결제 금액은 0보다 커야 합니다" }
        require(transactionKey.isNotBlank()) { "거래 키는 필수입니다" }
        require(cardType.isNotBlank()) { "카드 타입은 필수입니다" }
        require(cardNo.isNotBlank()) { "카드 번호는 필수입니다" }

        return Payment(
            orderId = orderId,
            amount = amount,
            paymentMethod = PaymentMethod.CARD,
            transactionKey = transactionKey,
            cardType = cardType,
            cardNo = cardNo,
        )
    }
}
```

**🤔 질문: 이 정도 검증이 필요할까요, 아니면 과도한가요?**

---

### 3. 카드 번호 마스킹

**보안 고려사항:**
- 현재 카드 번호를 그대로 저장
- 로그에 노출될 위험

**개선안:**
```kotlin
@Column(name = "card_no", length = 20)
var cardNo: String? = cardNo
    ?.let { maskCardNumber(it) }  // 마스킹 처리
    protected set

private fun maskCardNumber(cardNo: String): String {
    // 마지막 4자리만 남기고 마스킹
    if (cardNo.length <= 4) return "****"
    return "*".repeat(cardNo.length - 4) + cardNo.takeLast(4)
}
```

**또는:**
```kotlin
// 별도 VO 생성
@Embeddable
data class CardNumber(
    @Column(name = "card_no_masked", length = 20)
    val masked: String,  // 마스킹된 번호만 저장
) {
    companion object {
        fun from(plainCardNo: String): CardNumber {
            val masked = "*".repeat(plainCardNo.length - 4) + plainCardNo.takeLast(4)
            return CardNumber(masked)
        }
    }
}
```

**🤔 질문: PG Simulator 연동이므로 실제 카드 번호는 아니지만, 마스킹을 적용해볼까요?**

---

## 🎯 우선순위

### High Priority (즉시 적용)
1. ✅ Email Pattern companion object 이동
2. ✅ Null 안전성 개선 (order.id, product.id)
3. ✅ PaymentCallbackDto 검증

### Medium Priority (이번 주 내)
4. ✅ Payment 필드 길이 검증
5. ✅ 미사용 import 정리
6. 🤔 Brand 연관관계 검증 전략 결정

### Low Priority (선택)
7. 🤔 카드 번호 마스킹
8. 🤔 Payment 도메인 상세 검증

---

## 📝 다음 액션

### 1. 즉시 적용할 파일 목록
```
apps/commerce-api/src/main/kotlin/com/loopers/
├── domain/
│   ├── shared/Email.kt                      # Pattern companion object
│   ├── payment/Payment.kt                   # 길이 검증, null 처리
│   ├── payment/PaymentService.kt            # null 안전성
│   ├── payment/PaymentCallbackDto.kt        # 검증 로직
│   └── payment/PaymentCallbackService.kt    # null 안전성
```

### 2. 검토 후 결정
- Brand 존재 여부 검증 전략
- Payment 검증 레벨
- 카드 번호 마스킹 필요성

---

**작성일:** 2025-12-04
**기반:** Round 5 Code Rabbit Review
**적용 대상:** Round 6 PG 연동 프로젝트
