# Code Quality 개선사항 적용 완료

> 📅 적용일: 2025-12-04
>
> ✅ Round 5 Code Rabbit 리뷰 기반 개선사항 적용 완료

---

## ✅ 적용 완료된 개선사항

### 1. Email Pattern 성능 개선 ✅

**파일:** `apps/commerce-api/src/main/kotlin/com/loopers/domain/shared/Email.kt`

**변경 내용:**
- `@Transient private val EMAIL_PATTERN` → `companion object`로 이동
- 매 Email 객체 생성 시 Pattern 재컴파일 방지
- 클래스당 1개의 Pattern 객체만 생성 (메모리 절약, 성능 향상)

**Before:**
```kotlin
@Embeddable
class Email(email: String) {
    @Transient
    private val EMAIL_PATTERN: Pattern = Pattern.compile("...")
    // ...
}
```

**After:**
```kotlin
@Embeddable
class Email(email: String) {
    init {
        require(EMAIL_PATTERN.matcher(address).matches()) { ... }
    }

    companion object {
        private val EMAIL_PATTERN: Pattern = Pattern.compile("...")
    }
}
```

---

### 2. Null 안전성 개선 ✅

**파일:** `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentService.kt`

**변경 내용:**
- `order.id!!` → `order.id ?: throw CoreException(...)`
- NPE 대신 명확한 비즈니스 예외 발생
- 2곳 수정:
  - `requestCardPayment()` 메서드 (line 51-54)
  - `paymentFallback()` 메서드 (line 78-81)

**Before:**
```kotlin
val payment = Payment.createCardPayment(
    orderId = order.id!!,  // ⚠️ NPE 위험
    ...
)
```

**After:**
```kotlin
val payment = Payment.createCardPayment(
    orderId = order.id ?: throw CoreException(
        ErrorType.ORDER_NOT_FOUND,
        "주문 ID가 없습니다. 주문이 영속화되지 않았을 수 있습니다."
    ),
    ...
)
```

---

### 3. PaymentCallbackDto 검증 로직 추가 ✅

**파일:** `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackDto.kt`

**변경 내용:**
- `init` 블록에 검증 로직 추가
- transactionKey: 필수 & 100자 이하
- status: 필수

**Before:**
```kotlin
data class PaymentCallbackDto(
    val transactionKey: String,
    val status: String,
    val reason: String?
) {
    fun isSuccess(): Boolean = status == "SUCCESS"
}
```

**After:**
```kotlin
data class PaymentCallbackDto(
    val transactionKey: String,
    val status: String,
    val reason: String?
) {
    init {
        require(transactionKey.isNotBlank()) { "거래 키는 필수입니다" }
        require(transactionKey.length <= 100) { "거래 키는 100자를 초과할 수 없습니다" }
        require(status.isNotBlank()) { "결제 상태는 필수입니다" }
    }

    fun isSuccess(): Boolean = status == "SUCCESS"
    fun isFailed(): Boolean = status == "FAILED"
}
```

---

### 4. Brand FK 제약조건 확인 ✅

**파일:** `docker/01-schema.sql`

**상태:** 이미 적용되어 있음 (line 39)

```sql
CREATE TABLE IF NOT EXISTS products (
    ...
    brand_id BIGINT NOT NULL,
    ...
    CONSTRAINT fk_products_brand FOREIGN KEY (brand_id) REFERENCES brands(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

**효과:**
- DB 레벨에서 Brand 무결성 보장
- 존재하지 않는 brandId로 Product 생성 불가

---

### 5. CardNumber Value Object 구현 ✅

**파일:** `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/CardNumber.kt` (신규)

**구현 내용:**
```kotlin
@Embeddable
data class CardNumber private constructor(
    @Column(name = "card_no_masked", length = 20)
    val maskedNumber: String
) {
    companion object {
        fun from(plainCardNo: String): CardNumber {
            // 원본 카드 번호를 마스킹 (예: "1234567890123456" -> "************3456")
            require(plainCardNo.isNotBlank()) { "카드 번호는 필수입니다" }
            require(plainCardNo.length >= 4) { "카드 번호는 최소 4자리 이상이어야 합니다" }

            val masked = if (plainCardNo.length <= 4) {
                "****"
            } else {
                "*".repeat(plainCardNo.length - 4) + plainCardNo.takeLast(4)
            }

            return CardNumber(masked)
        }

        fun fromMasked(maskedNumber: String): CardNumber {
            return CardNumber(maskedNumber)
        }
    }

    override fun toString(): String = maskedNumber
}
```

**효과:**
- 보안 강화: DB에 마스킹된 카드 번호만 저장
- 로그 노출 위험 감소
- 업계 표준 보안 관행 준수

---

### 6. Payment 엔티티에 CardNumber 적용 ✅

**파일:** `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/Payment.kt`

**변경 내용:**

#### 6-1. 필드 변경
**Before:**
```kotlin
@Column(name = "card_no", length = 20)
var cardNo: String? = cardNo
    protected set
```

**After:**
```kotlin
@Embedded
var cardNumber: CardNumber? = cardNumber
    protected set
```

#### 6-2. 생성자 파라미터 변경
**Before:**
```kotlin
class Payment(
    ...
    cardNo: String? = null,
)
```

**After:**
```kotlin
class Payment(
    ...
    cardNumber: CardNumber? = null,
)
```

#### 6-3. createCardPayment() 메서드 수정
**Before:**
```kotlin
fun createCardPayment(..., cardNo: String): Payment {
    return Payment(
        ...
        cardNo = cardNo,
    )
}
```

**After:**
```kotlin
fun createCardPayment(..., cardNo: String): Payment {
    return Payment(
        ...
        cardNumber = CardNumber.from(cardNo),  // 자동 마스킹
    )
}
```

**효과:**
- PG API 호출 시: 원본 카드 번호 사용 (pgRequest에 cardNo 전달)
- DB 저장 시: 자동으로 마스킹된 번호만 저장
- PaymentService는 변경 없음 (cardNo 파라미터 그대로 사용)

---

### 7. DB 스키마 업데이트 ✅

**파일:** `docker/01-schema.sql`

**변경 내용:**
```sql
CREATE TABLE IF NOT EXISTS commerce_payments (
    ...
    card_no_masked VARCHAR(20) NULL COMMENT '마스킹된 카드 번호 (보안)',
    ...
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

**변경:**
- `card_no` → `card_no_masked`
- 컬럼명으로 마스킹 데이터임을 명시

---

## 📊 변경된 파일 요약

### 수정된 파일 (6개)
1. ✅ `apps/commerce-api/src/main/kotlin/com/loopers/domain/shared/Email.kt`
2. ✅ `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentService.kt`
3. ✅ `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackDto.kt`
4. ✅ `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/Payment.kt`
5. ✅ `docker/01-schema.sql`

### 신규 파일 (1개)
6. ✅ `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/CardNumber.kt`

---

## 🧪 테스트 필요 사항

### 1. CardNumber 마스킹 동작 확인
```kotlin
// 테스트 예시
val cardNumber = CardNumber.from("1234567890123456")
assertEquals("************3456", cardNumber.maskedNumber)
```

### 2. Payment 생성 시 자동 마스킹 확인
```kotlin
val payment = Payment.createCardPayment(
    orderId = 1L,
    amount = Money.of(10000),
    transactionKey = "TXN123",
    cardType = "SAMSUNG",
    cardNo = "1234567890123456"  // 원본
)

// DB에 저장된 값 확인
assertEquals("************3456", payment.cardNumber?.maskedNumber)
```

### 3. DB 스키마 변경 확인
```bash
# Docker 컨테이너 재시작
docker-compose down
docker-compose up -d

# DB 접속하여 테이블 확인
mysql -u root -p
USE loopers;
DESC commerce_payments;
# card_no_masked 컬럼 확인
```

### 4. Null 안전성 확인
```kotlin
// order.id가 null일 때 명확한 예외 발생 확인
val order = Order(...) // 영속화 안 된 상태
assertThrows<CoreException> {
    paymentService.requestCardPayment(order, ...)
}
```

---

## ⚠️ 주의사항

### 1. DB 마이그레이션
- 기존 데이터가 있다면 컬럼명 변경 시 주의 필요
- 로컬 개발: DB 재생성 권장 (`docker-compose down -v`)
- 프로덕션: ALTER TABLE로 컬럼명 변경 + 데이터 마이그레이션

### 2. PG API 호출
- PG API에는 **원본 카드 번호** 전송 (마스킹 안 함)
- `PaymentService.requestCardPayment()`에서 `cardNo` 파라미터 그대로 사용
- DB 저장 시에만 마스킹

### 3. 로그 출력
- `payment.cardNumber.toString()` → 자동으로 마스킹된 번호 출력
- 원본 카드 번호는 로그에 출력하지 않도록 주의

---

## 📈 개선 효과

### 성능
- ✅ Email Pattern 재컴파일 방지 → 객체 생성 성능 향상

### 안전성
- ✅ Null 안전성 개선 → NPE 대신 명확한 비즈니스 예외
- ✅ DTO 검증 강화 → 잘못된 데이터 조기 차단

### 보안
- ✅ 카드 번호 마스킹 → DB/로그 노출 위험 감소
- ✅ 업계 표준 보안 관행 준수

### 무결성
- ✅ Brand FK 제약조건 → DB 레벨 무결성 보장

---

## 🎯 다음 단계

### 즉시 확인 (필수)
1. [ ] DB 재시작 및 스키마 확인
2. [ ] 애플리케이션 빌드 성공 확인
3. [ ] 기본 결제 플로우 테스트

### 추후 작업 (선택)
4. [ ] CardNumber 단위 테스트 작성
5. [ ] Payment 통합 테스트 업데이트
6. [ ] 카드 번호 마스킹 E2E 테스트

---

**적용 완료 일시:** 2025-12-04
**적용자:** Claude Code
**검토 필요:** DB 스키마 변경 확인
