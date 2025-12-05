# Coupon 도메인 테스트 가이드

## 📌 개요

이 문서는 **Coupon 도메인**의 테스트 작성 가이드입니다.
- 도메인 단위 테스트
- 통합 테스트 (Facade)
- 테스트 유틸리티

---

## 🧪 테스트 구조

```
apps/commerce-api/src/test/kotlin/com/loopers/
├── domain/
│   └── coupon/
│       ├── CouponTest.kt                    # Coupon 엔티티 테스트
│       ├── MemberCouponTest.kt              # MemberCoupon 엔티티 테스트
│       └── CouponTypeTest.kt                # CouponType Enum 테스트
└── application/
    └── coupon/
        └── CouponFacadeIntegrationTest.kt   # Facade 통합 테스트
```

---

## 📦 도메인 단위 테스트

### 1. CouponTest.kt

Coupon 엔티티의 비즈니스 로직을 테스트합니다.

```kotlin
package com.loopers.domain.coupon

import com.loopers.domain.shared.Money
import com.loopers.support.error.CoreException
import com.loopers.support.error.ErrorType
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertAll
import org.junit.jupiter.api.assertThrows

class CouponTest {

    @DisplayName("정액 쿠폰을 생성할 수 있다")
    @Test
    fun createFixedAmountCoupon() {
        // Given & When
        val coupon = Coupon(
            name = "5000원 할인 쿠폰",
            description = "신규 회원 대상",
            couponType = CouponType.FIXED_AMOUNT,
            discountAmount = 5000L,
            discountRate = null
        )

        // Then
        assertAll(
            { assertThat(coupon.name).isEqualTo("5000원 할인 쿠폰") },
            { assertThat(coupon.couponType).isEqualTo(CouponType.FIXED_AMOUNT) },
            { assertThat(coupon.discountAmount).isEqualTo(5000L) },
            { assertThat(coupon.discountRate).isNull() }
        )
    }

    @DisplayName("정률 쿠폰을 생성할 수 있다")
    @Test
    fun createPercentageCoupon() {
        // Given & When
        val coupon = Coupon(
            name = "10% 할인 쿠폰",
            description = "전 상품 10% 할인",
            couponType = CouponType.PERCENTAGE,
            discountAmount = null,
            discountRate = 10
        )

        // Then
        assertAll(
            { assertThat(coupon.name).isEqualTo("10% 할인 쿠폰") },
            { assertThat(coupon.couponType).isEqualTo(CouponType.PERCENTAGE) },
            { assertThat(coupon.discountAmount).isNull() },
            { assertThat(coupon.discountRate).isEqualTo(10) }
        )
    }

    // 쿠폰 타입별 검증 테스트는 CouponTypeTest에서 진행
    // Coupon 엔티티는 CouponType에 검증을 위임하므로, 검증 로직은 CouponType에서 테스트

    @DisplayName("정액 쿠폰으로 할인 금액을 계산할 수 있다")
    @Test
    fun calculateDiscountWithFixedAmount() {
        // Given
        val coupon = Coupon(
            name = "5000원 할인",
            description = null,
            couponType = CouponType.FIXED_AMOUNT,
            discountAmount = 5000L,
            discountRate = null
        )
        val orderAmount = Money.of(50000L)

        // When
        val discount = coupon.calculateDiscount(orderAmount)

        // Then
        assertThat(discount.amount).isEqualTo(5000L)
    }

    @DisplayName("정액 쿠폰 할인 금액이 주문 금액보다 크면 주문 금액만큼만 할인된다")
    @Test
    fun calculateDiscountWithFixedAmountExceedingOrderAmount() {
        // Given
        val coupon = Coupon(
            name = "10000원 할인",
            description = null,
            couponType = CouponType.FIXED_AMOUNT,
            discountAmount = 10000L,
            discountRate = null
        )
        val orderAmount = Money.of(5000L)

        // When
        val discount = coupon.calculateDiscount(orderAmount)

        // Then
        assertThat(discount.amount).isEqualTo(5000L)
    }

    @DisplayName("정률 쿠폰으로 할인 금액을 계산할 수 있다")
    @Test
    fun calculateDiscountWithPercentage() {
        // Given
        val coupon = Coupon(
            name = "10% 할인",
            description = null,
            couponType = CouponType.PERCENTAGE,
            discountAmount = null,
            discountRate = 10
        )
        val orderAmount = Money.of(50000L)

        // When
        val discount = coupon.calculateDiscount(orderAmount)

        // Then
        assertThat(discount.amount).isEqualTo(5000L) // 50000 * 10% = 5000
    }
}
```

---

### 2. MemberCouponTest.kt

MemberCoupon 엔티티의 비즈니스 로직을 테스트합니다.

```kotlin
package com.loopers.domain.coupon

import com.loopers.domain.shared.Money
import com.loopers.support.error.CoreException
import com.loopers.support.error.ErrorType
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertAll
import org.junit.jupiter.api.assertThrows

class MemberCouponTest {

    @DisplayName("회원 쿠폰을 발급할 수 있다")
    @Test
    fun issueMemberCoupon() {
        // Given
        val coupon = Coupon(
            name = "5000원 할인",
            description = null,
            couponType = CouponType.FIXED_AMOUNT,
            discountAmount = 5000L,
            discountRate = null
        )

        // When
        val memberCoupon = MemberCoupon.issue("member123", coupon)

        // Then
        assertAll(
            { assertThat(memberCoupon.memberId).isEqualTo("member123") },
            { assertThat(memberCoupon.coupon).isEqualTo(coupon) },
            { assertThat(memberCoupon.usedAt).isNull() },
            { assertThat(memberCoupon.canUse()).isTrue() }
        )
    }

    @DisplayName("미사용 쿠폰은 사용 가능하다")
    @Test
    fun canUseUnusedCoupon() {
        // Given
        val coupon = Coupon(
            name = "5000원 할인",
            description = null,
            couponType = CouponType.FIXED_AMOUNT,
            discountAmount = 5000L,
            discountRate = null
        )
        val memberCoupon = MemberCoupon.issue("member123", coupon)

        // When
        val canUse = memberCoupon.canUse()

        // Then
        assertThat(canUse).isTrue()
    }

    @DisplayName("쿠폰을 사용할 수 있다")
    @Test
    fun useCoupon() {
        // Given
        val coupon = Coupon(
            name = "5000원 할인",
            description = null,
            couponType = CouponType.FIXED_AMOUNT,
            discountAmount = 5000L,
            discountRate = null
        )
        val memberCoupon = MemberCoupon.issue("member123", coupon)

        // When
        memberCoupon.use()

        // Then
        assertAll(
            { assertThat(memberCoupon.usedAt).isNotNull() },
            { assertThat(memberCoupon.canUse()).isFalse() }
        )
    }

    @DisplayName("이미 사용한 쿠폰은 다시 사용할 수 없다")
    @Test
    fun failToUseAlreadyUsedCoupon() {
        // Given
        val coupon = Coupon(
            name = "5000원 할인",
            description = null,
            couponType = CouponType.FIXED_AMOUNT,
            discountAmount = 5000L,
            discountRate = null
        )
        val memberCoupon = MemberCoupon.issue("member123", coupon)
        memberCoupon.use()

        // When & Then
        val exception = assertThrows<CoreException> {
            memberCoupon.use()
        }

        assertThat(exception.errorType).isEqualTo(ErrorType.COUPON_ALREADY_USED)
        assertThat(exception.customMessage).contains("이미 사용된 쿠폰입니다")
    }

    @DisplayName("회원 쿠폰으로 할인 금액을 계산할 수 있다")
    @Test
    fun calculateDiscount() {
        // Given
        val coupon = Coupon(
            name = "10% 할인",
            description = null,
            couponType = CouponType.PERCENTAGE,
            discountAmount = null,
            discountRate = 10
        )
        val memberCoupon = MemberCoupon.issue("member123", coupon)
        val orderAmount = Money.of(50000L)

        // When
        val discount = memberCoupon.calculateDiscount(orderAmount)

        // Then
        assertThat(discount.amount).isEqualTo(5000L)
    }
}
```

---

### 3. CouponTypeTest.kt

CouponType Enum의 전략 패턴 로직을 테스트합니다.

```kotlin
package com.loopers.domain.coupon

import com.loopers.domain.shared.Money
import com.loopers.support.error.CoreException
import com.loopers.support.error.ErrorType
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

class CouponTypeTest {

    @DisplayName("정액 쿠폰 타입은 할인 금액이 없으면 예외가 발생한다")
    @Test
    fun validateFixedAmountCoupon_failWhenInvalid() {
        // Given
        val type = CouponType.FIXED_AMOUNT

        // When & Then
        val exception = assertThrows<CoreException> {
            type.validate(discountAmount = null, discountRate = null)
        }
        assertThat(exception.errorType).isEqualTo(ErrorType.INVALID_COUPON_DISCOUNT)
    }

    @DisplayName("정률 쿠폰 타입은 할인율이 범위를 벗어나면 예외가 발생한다")
    @Test
    fun validatePercentageCoupon_failWhenInvalid() {
        // Given
        val type = CouponType.PERCENTAGE

        // When & Then
        val exception = assertThrows<CoreException> {
            type.validate(discountAmount = null, discountRate = 101)
        }
        assertThat(exception.errorType).isEqualTo(ErrorType.INVALID_COUPON_DISCOUNT)
    }

    @DisplayName("정액 쿠폰의 할인 금액이 주문 금액보다 크면 주문 금액을 반환한다")
    @Test
    fun calculateFixedAmountDiscount_cappedByOrderAmount() {
        // Given
        val type = CouponType.FIXED_AMOUNT
        val orderAmount = Money.of(3000L)

        // When
        val discount = type.calculateDiscount(
            discountAmount = 5000L,
            discountRate = null,
            orderAmount = orderAmount
        )

        // Then
        assertThat(discount.amount).isEqualTo(3000L)
    }

    @DisplayName("정률 쿠폰은 주문 금액의 할인율만큼 할인한다")
    @Test
    fun calculatePercentageDiscount() {
        // Given
        val type = CouponType.PERCENTAGE
        val orderAmount = Money.of(50000L)

        // When
        val discount = type.calculateDiscount(
            discountAmount = null,
            discountRate = 10,
            orderAmount = orderAmount
        )

        // Then
        assertThat(discount.amount).isEqualTo(5000L) // 50000 * 10% = 5000
    }
}
```

---

## 🔗 통합 테스트

### CouponFacadeIntegrationTest.kt

전체 레이어를 통합하여 실제 시나리오를 테스트합니다.

```kotlin
package com.loopers.application.coupon

import com.loopers.domain.coupon.Coupon
import com.loopers.domain.coupon.CouponType
import com.loopers.infrastructure.coupon.CouponJpaRepository
import com.loopers.infrastructure.coupon.MemberCouponJpaRepository
import com.loopers.support.error.CoreException
import com.loopers.support.error.ErrorType
import com.loopers.utils.DatabaseCleanUp
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertAll
import org.junit.jupiter.api.assertThrows
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest

@SpringBootTest
class CouponFacadeIntegrationTest @Autowired constructor(
    private val couponFacade: CouponFacade,
    private val couponJpaRepository: CouponJpaRepository,
    private val memberCouponJpaRepository: MemberCouponJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp,
) {

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }

    @DisplayName("모든 활성 쿠폰을 조회할 수 있다")
    @Test
    fun getAllActiveCoupons() {
        // Given
        couponJpaRepository.save(
            Coupon("쿠폰1", "설명1", CouponType.FIXED_AMOUNT, 5000L, null)
        )
        couponJpaRepository.save(
            Coupon("쿠폰2", "설명2", CouponType.PERCENTAGE, null, 10)
        )

        // When
        val result = couponFacade.getAllActiveCoupons()

        // Then
        assertThat(result).hasSize(2)
    }

    @DisplayName("쿠폰 ID로 쿠폰을 조회할 수 있다")
    @Test
    fun getCoupon() {
        // Given
        val coupon = couponJpaRepository.save(
            Coupon("5000원 할인", "신규 회원", CouponType.FIXED_AMOUNT, 5000L, null)
        )

        // When
        val result = couponFacade.getCoupon(coupon.id)

        // Then
        assertAll(
            { assertThat(result.id).isEqualTo(coupon.id) },
            { assertThat(result.name).isEqualTo("5000원 할인") },
            { assertThat(result.couponType).isEqualTo(CouponType.FIXED_AMOUNT) },
            { assertThat(result.discountAmount).isEqualTo(5000L) }
        )
    }

    @DisplayName("회원에게 쿠폰을 발급할 수 있다")
    @Test
    fun issueCoupon() {
        // Given
        val coupon = couponJpaRepository.save(
            Coupon("5000원 할인", null, CouponType.FIXED_AMOUNT, 5000L, null)
        )
        val command = IssueCouponCommand(
            memberId = "member123",
            couponId = coupon.id
        )

        // When
        val result = couponFacade.issueCoupon(command)

        // Then
        assertAll(
            { assertThat(result.memberId).isEqualTo("member123") },
            { assertThat(result.coupon.id).isEqualTo(coupon.id) },
            { assertThat(result.isUsed).isFalse() },
            { assertThat(result.usedAt).isNull() }
        )

        // DB 확인
        val savedMemberCoupon = memberCouponJpaRepository.findById(result.id).get()
        assertThat(savedMemberCoupon.memberId).isEqualTo("member123")
    }

    @DisplayName("이미 발급받은 쿠폰은 중복 발급할 수 없다")
    @Test
    fun failToIssueDuplicateCoupon() {
        // Given
        val coupon = couponJpaRepository.save(
            Coupon("5000원 할인", null, CouponType.FIXED_AMOUNT, 5000L, null)
        )
        val command = IssueCouponCommand(
            memberId = "member123",
            couponId = coupon.id
        )

        // 첫 번째 발급 성공
        couponFacade.issueCoupon(command)

        // When & Then - 중복 발급 시도
        val exception = assertThrows<CoreException> {
            couponFacade.issueCoupon(command)
        }

        assertThat(exception.errorType).isEqualTo(ErrorType.COUPON_ALREADY_ISSUED)
    }

    @DisplayName("회원의 모든 쿠폰을 조회할 수 있다")
    @Test
    fun getMemberCoupons() {
        // Given
        val coupon1 = couponJpaRepository.save(
            Coupon("쿠폰1", null, CouponType.FIXED_AMOUNT, 5000L, null)
        )
        val coupon2 = couponJpaRepository.save(
            Coupon("쿠폰2", null, CouponType.PERCENTAGE, null, 10)
        )

        couponFacade.issueCoupon(IssueCouponCommand("member123", coupon1.id))
        couponFacade.issueCoupon(IssueCouponCommand("member123", coupon2.id))

        // When
        val result = couponFacade.getMemberCoupons("member123")

        // Then
        assertThat(result).hasSize(2)
    }

    @DisplayName("회원의 사용 가능한 쿠폰만 조회할 수 있다")
    @Test
    fun getAvailableMemberCoupons() {
        // Given
        val coupon1 = couponJpaRepository.save(
            Coupon("쿠폰1", null, CouponType.FIXED_AMOUNT, 5000L, null)
        )
        val coupon2 = couponJpaRepository.save(
            Coupon("쿠폰2", null, CouponType.PERCENTAGE, null, 10)
        )

        val memberCoupon1 = couponFacade.issueCoupon(
            IssueCouponCommand("member123", coupon1.id)
        )
        couponFacade.issueCoupon(IssueCouponCommand("member123", coupon2.id))

        // 쿠폰1 사용
        couponFacade.useCoupon(UseCouponCommand(memberCoupon1.id))

        // When
        val result = couponFacade.getAvailableMemberCoupons("member123")

        // Then
        assertThat(result).hasSize(1)
        assertThat(result[0].coupon.name).isEqualTo("쿠폰2")
    }

    @DisplayName("쿠폰을 사용할 수 있다")
    @Test
    fun useCoupon() {
        // Given
        val coupon = couponJpaRepository.save(
            Coupon("5000원 할인", null, CouponType.FIXED_AMOUNT, 5000L, null)
        )
        val memberCoupon = couponFacade.issueCoupon(
            IssueCouponCommand("member123", coupon.id)
        )

        // When
        val result = couponFacade.useCoupon(UseCouponCommand(memberCoupon.id))

        // Then
        assertAll(
            { assertThat(result.isUsed).isTrue() },
            { assertThat(result.usedAt).isNotNull() }
        )
    }

    @DisplayName("이미 사용한 쿠폰은 다시 사용할 수 없다")
    @Test
    fun failToUseAlreadyUsedCoupon() {
        // Given
        val coupon = couponJpaRepository.save(
            Coupon("5000원 할인", null, CouponType.FIXED_AMOUNT, 5000L, null)
        )
        val memberCoupon = couponFacade.issueCoupon(
            IssueCouponCommand("member123", coupon.id)
        )

        // 첫 번째 사용 성공
        couponFacade.useCoupon(UseCouponCommand(memberCoupon.id))

        // When & Then - 재사용 시도
        val exception = assertThrows<CoreException> {
            couponFacade.useCoupon(UseCouponCommand(memberCoupon.id))
        }

        assertThat(exception.errorType).isEqualTo(ErrorType.COUPON_ALREADY_USED)
    }

    @DisplayName("쿠폰 할인 금액을 계산할 수 있다")
    @Test
    fun calculateDiscount() {
        // Given
        val coupon = couponJpaRepository.save(
            Coupon("10% 할인", null, CouponType.PERCENTAGE, null, 10)
        )
        val memberCoupon = couponFacade.issueCoupon(
            IssueCouponCommand("member123", coupon.id)
        )

        // When
        val result = couponFacade.calculateDiscount(
            memberCouponId = memberCoupon.id,
            orderAmount = 50000L
        )

        // Then
        assertAll(
            { assertThat(result.orderAmount).isEqualTo(50000L) },
            { assertThat(result.discountAmount).isEqualTo(5000L) },
            { assertThat(result.finalAmount).isEqualTo(45000L) }
        )
    }

    @DisplayName("사용된 쿠폰으로는 할인 금액을 계산할 수 없다")
    @Test
    fun failToCalculateDiscountWithUsedCoupon() {
        // Given
        val coupon = couponJpaRepository.save(
            Coupon("10% 할인", null, CouponType.PERCENTAGE, null, 10)
        )
        val memberCoupon = couponFacade.issueCoupon(
            IssueCouponCommand("member123", coupon.id)
        )

        // 쿠폰 사용
        couponFacade.useCoupon(UseCouponCommand(memberCoupon.id))

        // When & Then
        val exception = assertThrows<CoreException> {
            couponFacade.calculateDiscount(
                memberCouponId = memberCoupon.id,
                orderAmount = 50000L
            )
        }

        assertThat(exception.errorType).isEqualTo(ErrorType.COUPON_NOT_AVAILABLE)
    }
}
```

---

## 🎯 테스트 작성 원칙

### 1. Given-When-Then 패턴

```kotlin
@Test
fun testMethod() {
    // Given - 테스트 준비
    val input = createTestData()

    // When - 테스트 실행
    val result = service.doSomething(input)

    // Then - 검증
    assertThat(result).isEqualTo(expected)
}
```

### 2. DisplayName 작성

```kotlin
@DisplayName("한글로 명확하게 테스트 목적을 설명한다")
@Test
fun testMethod() {
    // ...
}
```

### 3. AssertAll 사용

여러 검증을 한 번에 수행:

```kotlin
assertAll(
    { assertThat(result.field1).isEqualTo(expected1) },
    { assertThat(result.field2).isEqualTo(expected2) },
    { assertThat(result.field3).isNotNull() }
)
```

### 4. 예외 검증

```kotlin
val exception = assertThrows<CoreException> {
    service.doInvalidOperation()
}

assertThat(exception.errorType).isEqualTo(ErrorType.EXPECTED_ERROR)
assertThat(exception.customMessage).contains("예상 메시지")
```

### 5. 테스트 격리

```kotlin
@AfterEach
fun tearDown() {
    databaseCleanUp.truncateAllTables()
}
```

---

## ✅ 테스트 체크리스트

### 도메인 단위 테스트
- [ ] 엔티티 생성 테스트 (정상 케이스)
- [ ] 엔티티 생성 테스트 (예외 케이스)
- [ ] 비즈니스 메서드 테스트 (정상 케이스)
- [ ] 비즈니스 메서드 테스트 (예외 케이스)
- [ ] Enum 전략 패턴 테스트
- [ ] VO(Value Object) 테스트

### 통합 테스트
- [ ] `@SpringBootTest` 사용
- [ ] 전체 시나리오 테스트
- [ ] DB 상태 변경 검증
- [ ] 예외 케이스 검증
- [ ] `@AfterEach`에서 DB 클린업
- [ ] Given-When-Then 패턴 사용

### 일반
- [ ] `@DisplayName`으로 테스트 설명
- [ ] AssertJ 사용
- [ ] 테스트 메서드명은 영어로 명확하게
- [ ] 하나의 테스트는 하나의 케이스만 검증
- [ ] 테스트 격리 (서로 영향 없음)

---

## 💡 핵심 요약

1. **도메인 테스트** - DB 없이 순수 로직만 테스트
2. **통합 테스트** - 전체 레이어 통합, 실제 DB 사용
3. **Given-When-Then** - 일관된 테스트 구조
4. **예외 케이스 필수** - 정상 케이스만큼 중요
5. **테스트 격리** - DatabaseCleanUp 활용
6. **명확한 설명** - DisplayName 활용
7. **AssertAll** - 여러 검증을 한 번에

---

이 가이드를 따라 테스트를 작성하면 **신뢰할 수 있는 쿠폰 도메인**을 만들 수 있습니다! 🚀
