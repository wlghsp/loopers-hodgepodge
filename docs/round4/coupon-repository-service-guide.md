# Coupon Repository & Service 가이드

## 📌 개요

이 문서는 **Coupon 도메인**의 Repository와 Service 계층 구현 가이드입니다.

---

## 🗂️ Repository 계층

이 프로젝트는 **3-Layer Repository 패턴**을 사용합니다:
1. **Domain Layer**: Repository 인터페이스 정의 (`domain/`)
2. **Infrastructure Layer**: JpaRepository 인터페이스 (`infrastructure/`)
3. **Infrastructure Layer**: Repository 구현체 (`infrastructure/`)

### 1. CouponRepository (Domain Layer)

과제에서 필요한 메서드만 정의합니다.

```kotlin
package com.loopers.domain.coupon

interface CouponRepository {
    fun findById(id: Long): Coupon?
    fun findByIdOrThrow(id: Long): Coupon
}
```

**필요한 메서드:**
- `findById()`: 쿠폰 조회 (nullable)
- `findByIdOrThrow()`: 쿠폰 조회 (없으면 예외) - **주문 시 쿠폰 검증용**

### 2. CouponJpaRepository (Infrastructure Layer)

기본 JpaRepository 메서드만 사용합니다.

```kotlin
package com.loopers.infrastructure.coupon

import com.loopers.domain.coupon.Coupon
import org.springframework.data.jpa.repository.JpaRepository

interface CouponJpaRepository : JpaRepository<Coupon, Long> {
    // 기본 메서드(findById, save 등)만 사용
}
```

### 3. CouponRepositoryImpl (Infrastructure Layer)

도메인 Repository 인터페이스의 구현체입니다.

```kotlin
package com.loopers.infrastructure.coupon

import com.loopers.domain.coupon.Coupon
import com.loopers.domain.coupon.CouponRepository
import com.loopers.support.error.CoreException
import com.loopers.support.error.ErrorType
import org.springframework.stereotype.Component

@Component
class CouponRepositoryImpl(
    private val couponJpaRepository: CouponJpaRepository,
) : CouponRepository {

    override fun findById(id: Long): Coupon? {
        return couponJpaRepository.findById(id).orElse(null)
    }

    override fun findByIdOrThrow(id: Long): Coupon {
        return findById(id)
            ?: throw CoreException(
                ErrorType.COUPON_NOT_FOUND,
                "쿠폰을 찾을 수 없습니다. ID: $id"
            )
    }
}
```

---

### 4. MemberCouponRepository (Domain Layer)

주문 시 필요한 메서드만 정의합니다.

```kotlin
package com.loopers.domain.coupon

interface MemberCouponRepository {
    fun findByMemberIdAndCouponId(memberId: String, couponId: Long): MemberCoupon?
}
```

**필요한 메서드:**
- `findByMemberIdAndCouponId()`: **주문 시 회원이 해당 쿠폰을 보유했는지 확인**

### 5. MemberCouponJpaRepository (Infrastructure Layer)

주문 시 필요한 쿼리만 정의합니다.

```kotlin
package com.loopers.infrastructure.coupon

import com.loopers.domain.coupon.MemberCoupon
import jakarta.persistence.LockModeType
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Lock
import org.springframework.data.jpa.repository.Query

interface MemberCouponJpaRepository : JpaRepository<MemberCoupon, Long> {

    /**
     * 회원의 특정 쿠폰 조회 (비관적 락)
     * 주문 시 쿠폰 중복 사용 방지를 위해 락 사용
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
        SELECT mc FROM MemberCoupon mc
        JOIN FETCH mc.coupon c
        WHERE mc.memberId = :memberId
        AND mc.coupon.id = :couponId
        AND mc.deletedAt IS NULL
        AND c.deletedAt IS NULL
    """)
    fun findByMemberIdAndCouponIdWithLock(memberId: String, couponId: Long): MemberCoupon?
}
```

**핵심:**
- ✅ **비관적 락** 적용으로 동시성 제어
- ✅ `JOIN FETCH`로 N+1 방지
- ✅ 삭제되지 않은 쿠폰만 조회

### 6. MemberCouponRepositoryImpl (Infrastructure Layer)

도메인 Repository 인터페이스의 구현체입니다.

```kotlin
package com.loopers.infrastructure.coupon

import com.loopers.domain.coupon.MemberCoupon
import com.loopers.domain.coupon.MemberCouponRepository
import org.springframework.stereotype.Component

@Component
class MemberCouponRepositoryImpl(
    private val memberCouponJpaRepository: MemberCouponJpaRepository,
) : MemberCouponRepository {

    override fun findByMemberIdAndCouponId(memberId: String, couponId: Long): MemberCoupon? {
        return memberCouponJpaRepository.findByMemberIdAndCouponIdWithLock(memberId, couponId)
    }
}
```

**핵심:**
- ✅ 비관적 락이 적용된 메서드 호출
- ✅ 주문 시 쿠폰 중복 사용 방지

---

## 🔧 Service 계층

### CouponService

주문 시 쿠폰 적용을 위한 서비스입니다.

```kotlin
package com.loopers.domain.coupon

import com.loopers.domain.shared.Money
import com.loopers.support.error.CoreException
import com.loopers.support.error.ErrorType
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
@Transactional(readOnly = true)
class CouponService(
    private val couponRepository: CouponRepository,
    private val memberCouponRepository: MemberCouponRepository,
) {

    /**
     * 회원의 특정 쿠폰 조회 (주문 시 사용)
     * 비관적 락 적용으로 동시성 제어
     */
    fun getMemberCoupon(memberId: String, couponId: Long): MemberCoupon {
        // 쿠폰 존재 여부 확인
        couponRepository.findByIdOrThrow(couponId)

        // 회원의 쿠폰 조회 (비관적 락)
        return memberCouponRepository.findByMemberIdAndCouponId(memberId, couponId)
            ?: throw CoreException(
                ErrorType.COUPON_NOT_FOUND,
                "회원이 해당 쿠폰을 보유하고 있지 않습니다. 회원: $memberId, 쿠폰: $couponId"
            )
    }

    /**
     * 쿠폰 할인 금액 계산
     */
    fun calculateDiscount(memberCoupon: MemberCoupon, orderAmount: Money): Money {
        // 사용 가능한지 확인
        if (!memberCoupon.canUse()) {
            throw CoreException(
                ErrorType.COUPON_NOT_AVAILABLE,
                "사용할 수 없는 쿠폰입니다."
            )
        }

        return memberCoupon.calculateDiscount(orderAmount)
    }

    /**
     * 쿠폰 사용 처리 (주문 완료 시 호출)
     */
    @Transactional
    fun useCoupon(memberCoupon: MemberCoupon) {
        // 도메인 메서드를 통해 사용 처리 (검증 포함)
        memberCoupon.use()
    }
}
```

**주요 메서드:**
1. `getMemberCoupon()`: 회원의 쿠폰 조회 (비관적 락)
2. `calculateDiscount()`: 할인 금액 계산
3. `useCoupon()`: 쿠폰 사용 처리

**동작 방식:**
```kotlin
// OrderFacade에서 호출
val memberCoupon = couponService.getMemberCoupon(memberId, couponId) // 락 획득
val discount = couponService.calculateDiscount(memberCoupon, orderAmount)
// ... 주문 처리 ...
couponService.useCoupon(memberCoupon) // 사용 처리
```

---

## 📋 Service 설계 원칙

### 1. 트랜잭션 관리
```kotlin
@Service
@Transactional(readOnly = true)  // ✅ 기본은 읽기 전용
class CouponService {

    @Transactional  // ✅ 쓰기 작업만 명시적으로 표시
    fun useCoupon(memberCouponId: Long): MemberCoupon {
        // ...
    }
}
```

### 2. 도메인 로직은 엔티티에
```kotlin
// ❌ Service에서 비즈니스 로직 처리
@Transactional
fun useCoupon(memberCouponId: Long): MemberCoupon {
    val memberCoupon = findMemberCoupon(memberCouponId)

    // ❌ Service에서 검증
    if (memberCoupon.usedAt != null) {
        throw CoreException(ErrorType.COUPON_ALREADY_USED)
    }

    // ❌ Service에서 상태 변경
    memberCoupon.usedAt = ZonedDateTime.now()
    return memberCoupon
}

// ✅ 도메인 메서드 호출
@Transactional
fun useCoupon(memberCouponId: Long): MemberCoupon {
    val memberCoupon = findMemberCoupon(memberCouponId)

    // ✅ 도메인 메서드가 검증과 상태 변경을 모두 처리
    memberCoupon.use()

    return memberCoupon
}
```

### 3. 예외 처리
```kotlin
fun getCoupon(couponId: Long): Coupon {
    return couponRepository.findActiveById(couponId)
        ?: throw CoreException(  // ✅ 명확한 예외와 메시지
            ErrorType.COUPON_NOT_FOUND,
            "쿠폰을 찾을 수 없습니다. ID: $couponId"
        )
}
```

### 4. N+1 문제 방지
```kotlin
// Repository에서 JOIN FETCH 사용
@Query("""
    SELECT mc FROM MemberCoupon mc
    JOIN FETCH mc.coupon c  // ✅ 쿠폰 정보를 함께 조회
    WHERE mc.memberId = :memberId
""")
fun findAllByMemberId(memberId: String): List<MemberCoupon>
```

---

## 🎯 ErrorType 정의

`ErrorType.kt`에 쿠폰 관련 에러 타입을 추가합니다.

```kotlin
// 쿠폰 관련 에러
COUPON_NOT_FOUND(HttpStatus.NOT_FOUND, "COUPON_001", "쿠폰을 찾을 수 없습니다."),
COUPON_ALREADY_USED(HttpStatus.BAD_REQUEST, "COUPON_002", "이미 사용된 쿠폰입니다."),
COUPON_NOT_AVAILABLE(HttpStatus.BAD_REQUEST, "COUPON_003", "사용할 수 없는 쿠폰입니다."),
COUPON_ALREADY_ISSUED(HttpStatus.BAD_REQUEST, "COUPON_004", "이미 발급받은 쿠폰입니다."),
INVALID_COUPON_DISCOUNT(HttpStatus.BAD_REQUEST, "COUPON_005", "잘못된 쿠폰 할인 정보입니다."),
```

---

## 📝 주문 시 쿠폰 적용 예시

OrderFacade에서 CouponService를 사용하는 방법입니다.

```kotlin
@Transactional
fun createOrder(request: CreateOrderRequest): OrderInfo {
    // 1. 쿠폰 검증 (있는 경우)
    var memberCoupon: MemberCoupon? = null
    var discountAmount = Money.zero()

    if (request.couponId != null) {
        // 비관적 락으로 쿠폰 조회
        memberCoupon = couponService.getMemberCoupon(
            memberId = request.memberId,
            couponId = request.couponId
        )

        // 할인 금액 계산
        discountAmount = couponService.calculateDiscount(memberCoupon, orderAmount)
    }

    // 2. 포인트 차감 (할인 적용 후)
    val finalAmount = orderAmount.minus(discountAmount)
    member.pay(finalAmount)

    // 3. 재고 차감
    // ...

    // 4. 쿠폰 사용 처리
    if (memberCoupon != null) {
        couponService.useCoupon(memberCoupon)
    }

    // 5. 주문 생성
    return orderService.createOrder(...)
}
```

**핵심:**
- ✅ `getMemberCoupon()`에서 비관적 락 획득
- ✅ 락은 트랜잭션 종료 시 자동 해제
- ✅ 동일 쿠폰 중복 사용 방지

---

## ✅ 체크리스트

### Repository
- [ ] **Domain Layer**: Repository 인터페이스를 `domain/` 패키지에 정의했는가?
- [ ] **Infrastructure Layer**: JpaRepository를 `infrastructure/` 패키지에 정의했는가?
- [ ] **Infrastructure Layer**: RepositoryImpl을 `infrastructure/` 패키지에 정의했는가?
- [ ] `findByIdOrThrow()` 메서드를 구현했는가?
- [ ] 커스텀 쿼리에 `@Query` 어노테이션을 사용했는가?
- [ ] N+1 문제를 방지하기 위해 `JOIN FETCH`를 사용했는가?
- [ ] 삭제된 데이터를 제외하는 조건(`deletedAt IS NULL`)을 포함했는가?
- [ ] 메서드명이 명확하고 일관성 있는가?

### Service
- [ ] `@Service` 어노테이션을 사용했는가?
- [ ] 클래스 레벨에 `@Transactional(readOnly = true)`를 적용했는가?
- [ ] 쓰기 작업에만 `@Transactional`을 명시적으로 표시했는가?
- [ ] 비즈니스 로직은 도메인 엔티티에 위임했는가?
- [ ] 예외 처리가 적절하고 명확한가?
- [ ] 의존성은 생성자 주입을 사용했는가?

---

## 💡 핵심 요약

1. **최소한의 메서드만** - 과제에 필요한 기능만 구현
2. **비관적 락** - 쿠폰 중복 사용 방지
3. **도메인 로직은 엔티티에** - Service는 조율만
4. **N+1 방지** - JOIN FETCH 사용
5. **트랜잭션은 OrderFacade에서** - Service는 조회/검증만
6. **명확한 예외 처리** - CoreException 사용

**과제 요구사항에 맞는 구현:**
- ✅ 쿠폰 발급 API 불필요 (테스트 픽스처로 생성)
- ✅ 쿠폰 조회 API 불필요 (주문 시에만 사용)
- ✅ 주문 시 쿠폰 검증 → 할인 계산 → 사용 처리

---

이 가이드를 따라 구현하면 **확장 가능하고 유지보수하기 좋은** Repository & Service 계층을 만들 수 있습니다! 🚀
