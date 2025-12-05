# Coupon 동시성 제어 가이드

## 📌 개요

이 문서는 **쿠폰 발급 시 발생하는 동시성 이슈**와 **해결 방법**을 다룹니다.

---

## 🚨 동시성 이슈 시나리오

### 문제 상황

**시나리오:** 선착순 100명에게 쿠폰을 발급하는 이벤트

```
- 발급 가능 쿠폰 수: 100개
- 동시 발급 요청: 1000명
- 예상 결과: 100명만 성공, 900명 실패
- 실제 결과: 101명 이상 발급 (동시성 이슈!)
```

### Race Condition 발생 원인

```kotlin
// CouponService.issueCoupon()
@Transactional
fun issueCoupon(memberId: String, couponId: Long): MemberCoupon {
    // 1. 쿠폰 조회
    val coupon = couponRepository.findByIdOrThrow(couponId)

    // 2. 발급 여부 확인 (여기서 동시성 이슈!)
    if (memberCouponRepository.existsByMemberIdAndCouponId(memberId, couponId)) {
        throw CoreException(ErrorType.COUPON_ALREADY_ISSUED)
    }

    // 3. 발급
    val memberCoupon = MemberCoupon.issue(memberId, coupon)
    return memberCouponRepository.save(memberCoupon)
}
```

**문제점:**
- Thread A: `existsByMemberIdAndCouponId()` → false (발급 가능)
- Thread B: `existsByMemberIdAndCouponId()` → false (발급 가능) ← 동시에 확인!
- Thread A: `save()` → 성공
- Thread B: `save()` → 성공 (중복 발급!)

---

## 💡 해결 방안 비교

### 방안 1: 비관적 락 (Pessimistic Lock)

**개념:** 데이터를 읽을 때부터 락을 걸어 다른 트랜잭션의 접근을 차단

**장점:**
- ✅ 충돌이 많을 때 효율적
- ✅ 데이터 정합성 보장
- ✅ 구현이 간단

**단점:**
- ❌ 데드락 위험
- ❌ 성능 저하 (락 대기 시간)
- ❌ DB 레벨 락 의존

**사용 시기:**
- 충돌이 빈번한 경우
- 데이터 정합성이 매우 중요한 경우
- 쿠폰 발급, 재고 감소 등

---

### 방안 2: 낙관적 락 (Optimistic Lock)

**개념:** 데이터를 읽을 때는 락을 걸지 않고, 업데이트 시 버전을 확인하여 충돌 감지

**장점:**
- ✅ 충돌이 적을 때 효율적
- ✅ 성능 우수 (락 대기 없음)
- ✅ 데드락 없음

**단점:**
- ❌ 충돌 시 재시도 로직 필요
- ❌ 충돌이 많으면 비효율적
- ❌ 버전 관리 필요

**사용 시기:**
- 충돌이 드문 경우
- 읽기 작업이 많은 경우
- 일반적인 업데이트 작업

---

### 방안 3: 분산 락 (Distributed Lock - Redisson)

**개념:** Redis 등 외부 저장소를 이용한 분산 락

**장점:**
- ✅ 다중 서버 환경에서 동작
- ✅ 유연한 락 제어
- ✅ DB 부하 감소

**단점:**
- ❌ 외부 의존성 (Redis 등)
- ❌ 구현 복잡도 증가
- ❌ 네트워크 비용

**사용 시기:**
- 다중 서버 환경
- DB 락을 피하고 싶은 경우
- 분산 시스템

---

## 🔧 구현 예시

### 방안 1: 비관적 락 구현

#### 1-1. Repository에 락 적용

```kotlin
package com.loopers.infrastructure.coupon

import com.loopers.domain.coupon.MemberCoupon
import jakarta.persistence.LockModeType
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Lock
import org.springframework.data.jpa.repository.Query

interface MemberCouponJpaRepository : JpaRepository<MemberCoupon, Long> {

    /**
     * 비관적 락으로 회원의 특정 쿠폰 보유 여부 확인
     *
     * PESSIMISTIC_WRITE: 다른 트랜잭션이 읽기/쓰기 모두 차단
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
        SELECT mc FROM MemberCoupon mc
        WHERE mc.memberId = :memberId
        AND mc.coupon.id = :couponId
        AND mc.deletedAt IS NULL
    """)
    fun findByMemberIdAndCouponIdWithLock(
        memberId: String,
        couponId: Long
    ): MemberCoupon?

    /**
     * 일반 조회 (락 없음)
     */
    @Query("""
        SELECT COUNT(mc) > 0 FROM MemberCoupon mc
        WHERE mc.memberId = :memberId
        AND mc.coupon.id = :couponId
        AND mc.deletedAt IS NULL
    """)
    fun existsByMemberIdAndCouponId(memberId: String, couponId: Long): Boolean

    // ... 기존 메서드들
}
```

#### 1-2. RepositoryImpl 수정

```kotlin
package com.loopers.infrastructure.coupon

import com.loopers.domain.coupon.MemberCoupon
import com.loopers.domain.coupon.MemberCouponRepository
import com.loopers.support.error.CoreException
import com.loopers.support.error.ErrorType
import org.springframework.stereotype.Component

@Component
class MemberCouponRepositoryImpl(
    private val memberCouponJpaRepository: MemberCouponJpaRepository,
) : MemberCouponRepository {

    // ... 기존 메서드들

    override fun existsByMemberIdAndCouponId(memberId: String, couponId: Long): Boolean {
        return memberCouponJpaRepository.existsByMemberIdAndCouponId(memberId, couponId)
    }

    /**
     * 비관적 락을 사용한 조회
     */
    fun findByMemberIdAndCouponIdWithLock(memberId: String, couponId: Long): MemberCoupon? {
        return memberCouponJpaRepository.findByMemberIdAndCouponIdWithLock(memberId, couponId)
    }
}
```

#### 1-3. Service에서 비관적 락 사용

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

    // ... 기존 메서드들

    /**
     * 쿠폰 발급 (비관적 락 적용)
     */
    @Transactional
    fun issueCouponWithPessimisticLock(memberId: String, couponId: Long): MemberCoupon {
        // 1. 쿠폰 존재 여부 확인
        val coupon = couponRepository.findByIdOrThrow(couponId)

        // 2. 비관적 락으로 중복 발급 확인 (여기서 락 획득!)
        val existingCoupon = (memberCouponRepository as?
            com.loopers.infrastructure.coupon.MemberCouponRepositoryImpl)
            ?.findByMemberIdAndCouponIdWithLock(memberId, couponId)

        if (existingCoupon != null) {
            throw CoreException(
                ErrorType.COUPON_ALREADY_ISSUED,
                "이미 발급받은 쿠폰입니다. 쿠폰 ID: $couponId"
            )
        }

        // 3. 쿠폰 발급
        val memberCoupon = MemberCoupon.issue(memberId, coupon)
        return memberCouponRepository.save(memberCoupon)
    }
}
```

**동작 방식:**
1. `findByMemberIdAndCouponIdWithLock()` 호출 시 DB 락 획득
2. 다른 트랜잭션은 락이 해제될 때까지 대기
3. 트랜잭션 커밋 시 락 자동 해제

**SQL 예시:**
```sql
SELECT * FROM member_coupons
WHERE member_id = 'member123' AND coupon_id = 1
FOR UPDATE; -- 비관적 락!
```

---

### 방안 2: 낙관적 락 구현

#### 2-1. Coupon 엔티티에 버전 추가

```kotlin
package com.loopers.domain.coupon

import com.loopers.domain.BaseEntity
import com.loopers.domain.shared.Money
import com.loopers.support.error.CoreException
import com.loopers.support.error.ErrorType
import jakarta.persistence.*

@Entity
@Table(name = "coupons")
class Coupon(
    name: String,
    description: String?,
    couponType: CouponType,
    discountAmount: Long?,
    discountRate: Int?,
    var issueLimit: Int = 100,      // 발급 제한 수
    var issuedCount: Int = 0,       // 현재 발급된 수
) : BaseEntity() {

    @Column(name = "name", nullable = false, length = 100)
    var name: String = name
        protected set

    @Column(name = "description", columnDefinition = "TEXT")
    var description: String? = description
        protected set

    @Enumerated(EnumType.STRING)
    @Column(name = "type", nullable = false, length = 20)
    var couponType: CouponType = couponType
        protected set

    @Column(name = "discount_amount")
    var discountAmount: Long? = discountAmount
        protected set

    @Column(name = "discount_rate")
    var discountRate: Int? = discountRate
        protected set

    @Column(name = "issue_limit", nullable = false)
    var issueLimit: Int = issueLimit
        protected set

    @Column(name = "issued_count", nullable = false)
    var issuedCount: Int = issuedCount
        protected set

    /**
     * 낙관적 락을 위한 버전 필드
     */
    @Version
    @Column(name = "version")
    var version: Long = 0

    init {
        validateCouponFields()
    }

    private fun validateCouponFields() {
        couponType.validate(discountAmount, discountRate)
    }

    fun calculateDiscount(orderAmount: Money): Money {
        return couponType.calculateDiscount(discountAmount, discountRate, orderAmount)
    }

    /**
     * 발급 가능 여부 확인
     */
    fun canIssue(): Boolean {
        return issuedCount < issueLimit
    }

    /**
     * 발급 수 증가 (낙관적 락 적용)
     */
    fun increaseIssuedCount() {
        if (!canIssue()) {
            throw CoreException(
                ErrorType.COUPON_ISSUE_LIMIT_EXCEEDED,
                "쿠폰 발급 한도를 초과했습니다. (한도: $issueLimit, 현재: $issuedCount)"
            )
        }
        issuedCount++
    }
}
```

#### 2-2. Service에서 낙관적 락 사용

```kotlin
package com.loopers.domain.coupon

import com.loopers.support.error.CoreException
import com.loopers.support.error.ErrorType
import org.springframework.orm.ObjectOptimisticLockingFailureException
import org.springframework.retry.annotation.Backoff
import org.springframework.retry.annotation.Retryable
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
@Transactional(readOnly = true)
class CouponService(
    private val couponRepository: CouponRepository,
    private val memberCouponRepository: MemberCouponRepository,
) {

    // ... 기존 메서드들

    /**
     * 쿠폰 발급 (낙관적 락 + 재시도)
     *
     * @Retryable: 낙관적 락 충돌 시 자동 재시도
     * - maxAttempts: 최대 재시도 횟수
     * - backoff: 재시도 간격 (100ms 대기)
     */
    @Transactional
    @Retryable(
        value = [ObjectOptimisticLockingFailureException::class],
        maxAttempts = 3,
        backoff = Backoff(delay = 100)
    )
    fun issueCouponWithOptimisticLock(memberId: String, couponId: Long): MemberCoupon {
        // 1. 쿠폰 조회
        val coupon = couponRepository.findByIdOrThrow(couponId)

        // 2. 중복 발급 확인
        if (memberCouponRepository.existsByMemberIdAndCouponId(memberId, couponId)) {
            throw CoreException(
                ErrorType.COUPON_ALREADY_ISSUED,
                "이미 발급받은 쿠폰입니다. 쿠폰 ID: $couponId"
            )
        }

        // 3. 발급 가능 여부 확인 및 카운트 증가 (여기서 낙관적 락 적용!)
        coupon.increaseIssuedCount()

        // 4. 쿠폰 발급
        val memberCoupon = MemberCoupon.issue(memberId, coupon)

        // 5. 저장 (트랜잭션 커밋 시 version 체크)
        couponRepository.save(coupon) // version이 다르면 예외 발생!
        return memberCouponRepository.save(memberCoupon)
    }
}
```

**동작 방식:**
1. 쿠폰 조회 시 현재 `version` 값 읽기 (예: version=1)
2. `issuedCount` 증가
3. 저장 시 `UPDATE coupons SET issued_count=?, version=2 WHERE id=? AND version=1`
4. 만약 다른 트랜잭션이 먼저 업데이트했다면 `version`이 달라서 업데이트 실패
5. `ObjectOptimisticLockingFailureException` 발생 → `@Retryable`로 재시도

**재시도 설정 (build.gradle.kts):**
```kotlin
dependencies {
    implementation("org.springframework.retry:spring-retry")
    implementation("org.springframework:spring-aspects")
}
```

**Application 클래스에 `@EnableRetry` 추가:**
```kotlin
@SpringBootApplication
@EnableRetry
class CommerceApiApplication

fun main(args: Array<String>) {
    runApplication<CommerceApiApplication>(*args)
}
```

---

### 방안 3: 분산 락 구현 (Redisson)

#### 3-1. 의존성 추가

```kotlin
// build.gradle.kts
dependencies {
    implementation("org.redisson:redisson-spring-boot-starter:3.24.3")
}
```

#### 3-2. Redis 설정

```yaml
# application.yml
spring:
  data:
    redis:
      host: localhost
      port: 6379
```

#### 3-3. 분산 락 유틸리티

```kotlin
package com.loopers.support.lock

import org.redisson.api.RedissonClient
import org.springframework.stereotype.Component
import java.util.concurrent.TimeUnit

@Component
class DistributedLockExecutor(
    private val redissonClient: RedissonClient
) {

    /**
     * 분산 락을 획득하고 작업 수행
     *
     * @param lockKey 락 키
     * @param waitTime 락 획득 대기 시간 (초)
     * @param leaseTime 락 유지 시간 (초)
     * @param task 수행할 작업
     */
    fun <T> executeWithLock(
        lockKey: String,
        waitTime: Long = 5,
        leaseTime: Long = 3,
        task: () -> T
    ): T {
        val lock = redissonClient.getLock(lockKey)

        try {
            // 락 획득 시도
            val acquired = lock.tryLock(waitTime, leaseTime, TimeUnit.SECONDS)

            if (!acquired) {
                throw RuntimeException("락 획득 실패: $lockKey")
            }

            // 작업 수행
            return task()
        } finally {
            // 락 해제 (현재 스레드가 락을 보유한 경우에만)
            if (lock.isHeldByCurrentThread) {
                lock.unlock()
            }
        }
    }
}
```

#### 3-4. Service에서 분산 락 사용

```kotlin
package com.loopers.domain.coupon

import com.loopers.support.lock.DistributedLockExecutor
import com.loopers.support.error.CoreException
import com.loopers.support.error.ErrorType
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
@Transactional(readOnly = true)
class CouponService(
    private val couponRepository: CouponRepository,
    private val memberCouponRepository: MemberCouponRepository,
    private val distributedLockExecutor: DistributedLockExecutor,
) {

    // ... 기존 메서드들

    /**
     * 쿠폰 발급 (분산 락 적용)
     */
    @Transactional
    fun issueCouponWithDistributedLock(memberId: String, couponId: Long): MemberCoupon {
        val lockKey = "coupon:issue:$couponId:$memberId"

        return distributedLockExecutor.executeWithLock(lockKey) {
            // 1. 쿠폰 존재 여부 확인
            val coupon = couponRepository.findByIdOrThrow(couponId)

            // 2. 중복 발급 확인
            if (memberCouponRepository.existsByMemberIdAndCouponId(memberId, couponId)) {
                throw CoreException(
                    ErrorType.COUPON_ALREADY_ISSUED,
                    "이미 발급받은 쿠폰입니다. 쿠폰 ID: $couponId"
                )
            }

            // 3. 쿠폰 발급
            val memberCoupon = MemberCoupon.issue(memberId, coupon)
            memberCouponRepository.save(memberCoupon)
        }
    }
}
```

---

## 📊 방안 비교표

| 구분 | 비관적 락 | 낙관적 락 | 분산 락 |
|------|----------|----------|---------|
| **구현 난이도** | ⭐⭐ 쉬움 | ⭐⭐⭐ 보통 | ⭐⭐⭐⭐ 어려움 |
| **성능** | ⭐⭐ 보통 | ⭐⭐⭐⭐ 좋음 | ⭐⭐⭐ 보통 |
| **충돌이 많을 때** | ⭐⭐⭐⭐ 좋음 | ⭐⭐ 나쁨 | ⭐⭐⭐ 보통 |
| **충돌이 적을 때** | ⭐⭐ 보통 | ⭐⭐⭐⭐ 좋음 | ⭐⭐⭐ 보통 |
| **다중 서버** | ⭐⭐⭐ 가능 | ⭐⭐⭐ 가능 | ⭐⭐⭐⭐ 최적 |
| **데드락 위험** | ⚠️ 있음 | ✅ 없음 | ⚠️ 있음 |
| **외부 의존성** | ✅ 없음 | ✅ 없음 | ❌ Redis 필요 |

---

## 🎯 추천 방안

### 쿠폰 발급 시나리오 (이커머스 과제)

**추천:** 비관적 락 (Pessimistic Lock)

**이유:**
1. ✅ 선착순 이벤트는 **충돌이 매우 빈번**함
2. ✅ **데이터 정합성이 최우선** (중복 발급 절대 불가)
3. ✅ 구현이 간단하고 안정적
4. ✅ 단일 서버 환경에서 충분

**대안:** 발급 수량 제한이 있다면 Coupon 엔티티에 `issuedCount` 추가 + 낙관적 락

---

## ⚙️ 성능 최적화 팁

### 1. 락 범위 최소화

```kotlin
// ❌ 나쁜 예: 전체 로직에 락
@Lock(LockModeType.PESSIMISTIC_WRITE)
fun doEverything() {
    // 긴 작업...
}

// ✅ 좋은 예: 필요한 부분만 락
fun doSomething() {
    val data = readDataWithLock() // 락 획득
    // 락 해제

    processData(data) // 락 없이 처리
}
```

### 2. 타임아웃 설정

```kotlin
@Lock(LockModeType.PESSIMISTIC_WRITE)
@QueryHints(QueryHint(name = "javax.persistence.lock.timeout", value = "3000"))
fun findWithLock(id: Long): Entity?
```

### 3. 인덱스 활용

```kotlin
@Table(
    name = "member_coupons",
    indexes = [
        Index(name = "idx_member_coupon", columnList = "member_id, coupon_id"),
        Index(name = "idx_member_used", columnList = "member_id, used_at")
    ]
)
```

---

## ✅ 체크리스트

- [ ] 동시성 이슈가 발생할 수 있는 부분을 식별했는가?
- [ ] 충돌 빈도를 고려하여 적절한 락 방식을 선택했는가?
- [ ] 비관적 락 사용 시 데드락 방지 전략이 있는가?
- [ ] 낙관적 락 사용 시 재시도 로직을 구현했는가?
- [ ] 락 범위를 최소화했는가?
- [ ] 타임아웃을 설정했는가?
- [ ] 인덱스를 적절히 설정했는가?
- [ ] 동시성 테스트를 작성했는가?

---

## 💡 핵심 요약

1. **비관적 락** - 충돌이 많을 때, 데이터 정합성이 중요할 때
2. **낙관적 락** - 충돌이 적을 때, 성능이 중요할 때
3. **분산 락** - 다중 서버 환경, DB 부하를 피하고 싶을 때
4. **쿠폰 발급** - 비관적 락 권장 (선착순, 충돌 빈번)
5. **락 범위** - 최소화하여 성능 향상
6. **타임아웃** - 데드락 방지
7. **테스트** - 동시성 테스트 필수

---

이 가이드를 따라 구현하면 **안전하고 효율적인 동시성 제어**를 할 수 있습니다! 🚀
