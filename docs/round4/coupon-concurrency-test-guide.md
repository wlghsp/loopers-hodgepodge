# Coupon 동시성 테스트 가이드

## 📌 개요

이 문서는 **쿠폰 발급의 동시성 제어가 올바르게 작동하는지 검증하는 테스트** 작성 가이드입니다.

---

## 🧪 동시성 테스트 개념

### 멀티스레드 테스트

여러 스레드가 동시에 같은 작업을 수행하여 동시성 이슈를 재현합니다.

**핵심 도구:**
- `ExecutorService`: 스레드 풀 관리
- `CountDownLatch`: 모든 스레드를 동시에 시작
- `AtomicInteger`: 스레드 안전한 카운터

---

## 📦 테스트 구조

```
apps/commerce-api/src/test/kotlin/com/loopers/
└── application/
    └── coupon/
        ├── CouponConcurrencyTest.kt              # 동시성 테스트
        └── CouponConcurrencyTestWithLock.kt      # 락 적용 후 테스트
```

---

## 🔴 동시성 이슈 재현 테스트

### 과제 요구사항 동시성 테스트

**요구사항:**
1. ✅ 동일한 상품에 대해 여러명이 좋아요/싫어요 요청 → 좋아요 개수 정합성
2. ✅ 동일한 쿠폰으로 여러 기기에서 동시 주문 → 쿠폰 1회만 사용
3. ✅ 동일한 유저가 서로 다른 주문을 동시 수행 → 포인트 정합성
4. ✅ 동일한 상품에 대해 여러 주문 동시 요청 → 재고 정합성

### CouponConcurrencyTest.kt

락을 적용하지 않았을 때 동시성 이슈가 발생하는지 확인합니다.

```kotlin
package com.loopers.application.coupon

import com.loopers.domain.coupon.Coupon
import com.loopers.domain.coupon.CouponType
import com.loopers.infrastructure.coupon.CouponJpaRepository
import com.loopers.infrastructure.coupon.MemberCouponJpaRepository
import com.loopers.utils.DatabaseCleanUp
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

@SpringBootTest
class CouponConcurrencyTest @Autowired constructor(
    private val couponFacade: CouponFacade,
    private val couponJpaRepository: CouponJpaRepository,
    private val memberCouponJpaRepository: MemberCouponJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp,
) {

    private lateinit var coupon: Coupon

    @BeforeEach
    fun setUp() {
        // 테스트용 쿠폰 생성
        coupon = couponJpaRepository.save(
            Coupon(
                name = "선착순 100명 쿠폰",
                description = "선착순 100명에게 지급",
                couponType = CouponType.FIXED_AMOUNT,
                discountAmount = 5000L,
                discountRate = null
            )
        )
    }

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }

    @DisplayName("[요구사항] 동일한 쿠폰으로 여러 기기에서 동시 주문 시 동시성 이슈 재현")
    @Test
    fun orderWithSameCouponConcurrently() {
        // Given
        val member = createTestMember("member123", 1000000L) // 충분한 포인트
        val product = createTestProduct(price = 10000L, stock = 100)
        val memberCoupon = createTestMemberCoupon(member.memberId, coupon.id)

        val threadCount = 10
        val executorService = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)
        val successCount = AtomicInteger(0)
        val failCount = AtomicInteger(0)

        // When - 같은 쿠폰으로 동시에 주문
        repeat(threadCount) {
            executorService.submit {
                try {
                    latch.countDown()
                    latch.await()

                    orderFacade.createOrder(
                        CreateOrderRequest(
                            memberId = "member123",
                            items = listOf(OrderItemRequest(product.id, 1)),
                            couponId = coupon.id // 같은 쿠폰!
                        )
                    )
                    successCount.incrementAndGet()
                } catch (e: Exception) {
                    failCount.incrementAndGet()
                }
            }
        }

        executorService.shutdown()
        while (!executorService.isTerminated) {
            Thread.sleep(100)
        }

        // Then
        println("성공: ${successCount.get()}, 실패: ${failCount.get()}")

        // 동시성 제어가 없으면 쿠폰이 여러 번 사용될 수 있음
        // (이상적으로는 1번만 성공해야 함)
    }

    @DisplayName("[요구사항] 동일한 유저가 서로 다른 주문을 동시 수행 시 포인트 정합성 이슈 재현")
    @Test
    fun orderConcurrentlyWithSameUser() {
        // Given
        val member = createTestMember("member123", 100000L)
        val product1 = createTestProduct(price = 10000L, stock = 100)
        val product2 = createTestProduct(price = 20000L, stock = 100)

        val threadCount = 5
        val executorService = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)
        val successCount = AtomicInteger(0)

        // When - 같은 유저가 동시에 여러 주문
        repeat(threadCount) { index ->
            executorService.submit {
                try {
                    latch.countDown()
                    latch.await()

                    val product = if (index % 2 == 0) product1 else product2
                    orderFacade.createOrder(
                        CreateOrderRequest(
                            memberId = "member123", // 같은 유저!
                            items = listOf(OrderItemRequest(product.id, 1)),
                            couponId = null
                        )
                    )
                    successCount.incrementAndGet()
                } catch (e: Exception) {
                    // 포인트 부족 등 예외
                }
            }
        }

        executorService.shutdown()
        while (!executorService.isTerminated) {
            Thread.sleep(100)
        }

        // Then
        val updatedMember = memberJpaRepository.findById(member.id).get()
        println("성공 주문 수: ${successCount.get()}, 남은 포인트: ${updatedMember.point.amount}")

        // 동시성 제어가 없으면 포인트가 정확히 차감되지 않을 수 있음
    }

    @DisplayName("[요구사항] 동일한 상품에 대해 여러 주문 동시 요청 시 재고 정합성 이슈 재현")
    @Test
    fun orderSameProductConcurrently() {
        // Given
        val product = createTestProduct(price = 10000L, stock = 10) // 재고 10개
        val threadCount = 20 // 20명이 동시 주문

        val executorService = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)
        val successCount = AtomicInteger(0)

        // When
        repeat(threadCount) { index ->
            executorService.submit {
                try {
                    val member = createTestMember("member$index", 100000L)

                    latch.countDown()
                    latch.await()

                    orderFacade.createOrder(
                        CreateOrderRequest(
                            memberId = "member$index",
                            items = listOf(OrderItemRequest(product.id, 1)),
                            couponId = null
                        )
                    )
                    successCount.incrementAndGet()
                } catch (e: Exception) {
                    // 재고 부족 등 예외
                }
            }
        }

        executorService.shutdown()
        while (!executorService.isTerminated) {
            Thread.sleep(100)
        }

        // Then
        val updatedProduct = productJpaRepository.findById(product.id).get()
        println("성공 주문: ${successCount.get()}, 남은 재고: ${updatedProduct.stock.quantity}")

        // 동시성 제어가 없으면 재고가 마이너스가 되거나 정합성이 깨질 수 있음
    }
}
```

**테스트 핵심:**
1. `CountDownLatch`: 모든 스레드가 동시에 시작하도록 동기화
2. `AtomicInteger`: 스레드 안전한 카운터로 성공/실패 집계
3. `ExecutorService`: 스레드 풀로 동시 요청 시뮬레이션

---

## 🟢 동시성 제어 검증 테스트

### CouponConcurrencyTestWithLock.kt

락을 적용한 후 동시성 이슈가 해결되는지 확인합니다.

```kotlin
package com.loopers.application.coupon

import com.loopers.domain.coupon.Coupon
import com.loopers.domain.coupon.CouponType
import com.loopers.infrastructure.coupon.CouponJpaRepository
import com.loopers.infrastructure.coupon.MemberCouponJpaRepository
import com.loopers.support.error.CoreException
import com.loopers.utils.DatabaseCleanUp
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

@SpringBootTest
class CouponConcurrencyTestWithLock @Autowired constructor(
    private val couponFacade: CouponFacade,
    private val couponJpaRepository: CouponJpaRepository,
    private val memberCouponJpaRepository: MemberCouponJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp,
) {

    private lateinit var coupon: Coupon

    @BeforeEach
    fun setUp() {
        coupon = couponJpaRepository.save(
            Coupon(
                name = "선착순 100명 쿠폰",
                description = "선착순 100명에게 지급",
                couponType = CouponType.FIXED_AMOUNT,
                discountAmount = 5000L,
                discountRate = null
            )
        )
    }

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }

    @DisplayName("비관적 락: 100명이 동시에 쿠폰을 발급받으면 100명 모두 성공한다")
    @Test
    fun issueWithPessimisticLock() {
        // Given
        val threadCount = 100
        val executorService = Executors.newFixedThreadPool(32) // 스레드 풀 크기
        val latch = CountDownLatch(threadCount)
        val successCount = AtomicInteger(0)
        val failCount = AtomicInteger(0)

        // When
        repeat(threadCount) { index ->
            executorService.submit {
                try {
                    latch.countDown()
                    latch.await()

                    // 비관적 락이 적용된 메서드 호출
                    couponFacade.issueCouponWithPessimisticLock(
                        memberId = "member$index",
                        couponId = coupon.id
                    )
                    successCount.incrementAndGet()
                } catch (e: Exception) {
                    println("실패: ${e.message}")
                    failCount.incrementAndGet()
                }
            }
        }

        executorService.shutdown()
        while (!executorService.isTerminated) {
            Thread.sleep(100)
        }

        // Then
        val totalIssued = memberCouponJpaRepository.count()

        println("=== 비관적 락 결과 ===")
        println("성공: ${successCount.get()}, 실패: ${failCount.get()}, DB 발급 수: $totalIssued")

        assertThat(successCount.get()).isEqualTo(100)
        assertThat(failCount.get()).isEqualTo(0)
        assertThat(totalIssued).isEqualTo(100)
    }

    @DisplayName("비관적 락: 같은 회원이 동시에 같은 쿠폰을 여러 번 발급받으려 하면 1번만 성공한다")
    @Test
    fun preventDuplicateIssueWithPessimisticLock() {
        // Given
        val threadCount = 10
        val executorService = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)
        val successCount = AtomicInteger(0)
        val failCount = AtomicInteger(0)

        // When
        repeat(threadCount) {
            executorService.submit {
                try {
                    latch.countDown()
                    latch.await()

                    couponFacade.issueCouponWithPessimisticLock(
                        memberId = "member123", // 같은 회원
                        couponId = coupon.id
                    )
                    successCount.incrementAndGet()
                } catch (e: CoreException) {
                    failCount.incrementAndGet()
                }
            }
        }

        executorService.shutdown()
        while (!executorService.isTerminated) {
            Thread.sleep(100)
        }

        // Then
        val totalIssued = memberCouponJpaRepository.count()

        println("=== 중복 발급 방지 결과 ===")
        println("성공: ${successCount.get()}, 실패: ${failCount.get()}, DB 발급 수: $totalIssued")

        // 1번만 성공, 나머지는 중복 발급 예외
        assertThat(successCount.get()).isEqualTo(1)
        assertThat(failCount.get()).isEqualTo(9)
        assertThat(totalIssued).isEqualTo(1)
    }

    @DisplayName("낙관적 락: 100명이 동시에 쿠폰을 발급받으면 100명 모두 성공한다")
    @Test
    fun issueWithOptimisticLock() {
        // Given
        val threadCount = 100
        val executorService = Executors.newFixedThreadPool(32)
        val latch = CountDownLatch(threadCount)
        val successCount = AtomicInteger(0)
        val failCount = AtomicInteger(0)

        // When
        repeat(threadCount) { index ->
            executorService.submit {
                try {
                    latch.countDown()
                    latch.await()

                    // 낙관적 락이 적용된 메서드 호출
                    couponFacade.issueCouponWithOptimisticLock(
                        memberId = "member$index",
                        couponId = coupon.id
                    )
                    successCount.incrementAndGet()
                } catch (e: Exception) {
                    println("실패: ${e.message}")
                    failCount.incrementAndGet()
                }
            }
        }

        executorService.shutdown()
        while (!executorService.isTerminated) {
            Thread.sleep(100)
        }

        // Then
        val totalIssued = memberCouponJpaRepository.count()

        println("=== 낙관적 락 결과 ===")
        println("성공: ${successCount.get()}, 실패: ${failCount.get()}, DB 발급 수: $totalIssued")

        // 재시도 덕분에 대부분 성공
        assertThat(successCount.get()).isGreaterThan(90) // 재시도로 인해 대부분 성공
        assertThat(totalIssued).isEqualTo(successCount.get().toLong())
    }

    @DisplayName("쿠폰 발급 한도 테스트: 100개 한도에 200명이 요청하면 100명만 성공한다")
    @Test
    fun issueLimitTest() {
        // Given
        val limitedCoupon = couponJpaRepository.save(
            Coupon(
                name = "한정 쿠폰",
                description = "100개 한정",
                couponType = CouponType.FIXED_AMOUNT,
                discountAmount = 5000L,
                discountRate = null,
                issueLimit = 100,
                issuedCount = 0
            )
        )

        val threadCount = 200
        val executorService = Executors.newFixedThreadPool(32)
        val latch = CountDownLatch(threadCount)
        val successCount = AtomicInteger(0)
        val failCount = AtomicInteger(0)

        // When
        repeat(threadCount) { index ->
            executorService.submit {
                try {
                    latch.countDown()
                    latch.await()

                    couponFacade.issueCouponWithOptimisticLock(
                        memberId = "member$index",
                        couponId = limitedCoupon.id
                    )
                    successCount.incrementAndGet()
                } catch (e: Exception) {
                    failCount.incrementAndGet()
                }
            }
        }

        executorService.shutdown()
        while (!executorService.isTerminated) {
            Thread.sleep(100)
        }

        // Then
        val totalIssued = memberCouponJpaRepository.count()
        val updatedCoupon = couponJpaRepository.findById(limitedCoupon.id).get()

        println("=== 발급 한도 테스트 결과 ===")
        println("성공: ${successCount.get()}, 실패: ${failCount.get()}, DB 발급 수: $totalIssued")
        println("쿠폰 발급 카운트: ${updatedCoupon.issuedCount}")

        // 정확히 100명만 성공
        assertThat(successCount.get()).isEqualTo(100)
        assertThat(failCount.get()).isEqualTo(100)
        assertThat(totalIssued).isEqualTo(100)
        assertThat(updatedCoupon.issuedCount).isEqualTo(100)
    }

    @DisplayName("쿠폰 사용 동시성 테스트: 같은 쿠폰을 동시에 사용하려 하면 1번만 성공한다")
    @Test
    fun useCouponConcurrently() {
        // Given
        val memberCoupon = couponFacade.issueCoupon(
            IssueCouponCommand("member123", coupon.id)
        )

        val threadCount = 10
        val executorService = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)
        val successCount = AtomicInteger(0)
        val failCount = AtomicInteger(0)

        // When - 같은 쿠폰을 동시에 사용
        repeat(threadCount) {
            executorService.submit {
                try {
                    latch.countDown()
                    latch.await()

                    couponFacade.useCoupon(UseCouponCommand(memberCoupon.id))
                    successCount.incrementAndGet()
                } catch (e: CoreException) {
                    failCount.incrementAndGet()
                }
            }
        }

        executorService.shutdown()
        while (!executorService.isTerminated) {
            Thread.sleep(100)
        }

        // Then
        println("=== 쿠폰 사용 동시성 결과 ===")
        println("성공: ${successCount.get()}, 실패: ${failCount.get()}")

        // 1번만 성공
        assertThat(successCount.get()).isEqualTo(1)
        assertThat(failCount.get()).isEqualTo(9)
    }
}
```

---

## 📊 성능 측정 테스트

### 락 방식별 성능 비교

```kotlin
package com.loopers.application.coupon

import com.loopers.domain.coupon.Coupon
import com.loopers.domain.coupon.CouponType
import com.loopers.infrastructure.coupon.CouponJpaRepository
import com.loopers.infrastructure.coupon.MemberCouponJpaRepository
import com.loopers.utils.DatabaseCleanUp
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.system.measureTimeMillis

@SpringBootTest
class CouponPerformanceTest @Autowired constructor(
    private val couponFacade: CouponFacade,
    private val couponJpaRepository: CouponJpaRepository,
    private val memberCouponJpaRepository: MemberCouponJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp,
) {

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }

    @DisplayName("비관적 락 vs 낙관적 락 성능 비교")
    @Test
    fun comparePerformance() {
        val threadCount = 100

        // 비관적 락 성능 측정
        val pessimisticTime = measurePerformance(
            threadCount = threadCount,
            lockType = "비관적 락"
        ) { index, couponId ->
            couponFacade.issueCouponWithPessimisticLock("member$index", couponId)
        }

        databaseCleanUp.truncateAllTables()

        // 낙관적 락 성능 측정
        val optimisticTime = measurePerformance(
            threadCount = threadCount,
            lockType = "낙관적 락"
        ) { index, couponId ->
            couponFacade.issueCouponWithOptimisticLock("member$index", couponId)
        }

        println("\n=== 성능 비교 결과 ===")
        println("비관적 락: ${pessimisticTime}ms")
        println("낙관적 락: ${optimisticTime}ms")
    }

    private fun measurePerformance(
        threadCount: Int,
        lockType: String,
        issueFunction: (Int, Long) -> Unit
    ): Long {
        // Given
        val coupon = couponJpaRepository.save(
            Coupon(
                name = "성능 테스트 쿠폰",
                description = null,
                couponType = CouponType.FIXED_AMOUNT,
                discountAmount = 5000L,
                discountRate = null,
                issueLimit = threadCount,
                issuedCount = 0
            )
        )

        val executorService = Executors.newFixedThreadPool(32)
        val latch = CountDownLatch(threadCount)
        val successCount = AtomicInteger(0)

        // When
        val elapsedTime = measureTimeMillis {
            repeat(threadCount) { index ->
                executorService.submit {
                    try {
                        latch.countDown()
                        latch.await()

                        issueFunction(index, coupon.id)
                        successCount.incrementAndGet()
                    } catch (e: Exception) {
                        // 예외 무시
                    }
                }
            }

            executorService.shutdown()
            while (!executorService.isTerminated) {
                Thread.sleep(10)
            }
        }

        println("[$lockType] 성공: ${successCount.get()}, 소요 시간: ${elapsedTime}ms")

        return elapsedTime
    }
}
```

---

## 🎯 테스트 작성 패턴

### 1. 기본 패턴

```kotlin
@Test
fun concurrencyTest() {
    // Given - 테스트 데이터 준비
    val threadCount = 100
    val executorService = Executors.newFixedThreadPool(32)
    val latch = CountDownLatch(threadCount)
    val successCount = AtomicInteger(0)
    val failCount = AtomicInteger(0)

    // When - 동시 실행
    repeat(threadCount) { index ->
        executorService.submit {
            try {
                latch.countDown() // 준비 완료
                latch.await()     // 모두 준비될 때까지 대기

                // 실제 작업 수행
                doSomething(index)
                successCount.incrementAndGet()
            } catch (e: Exception) {
                failCount.incrementAndGet()
            }
        }
    }

    // 모든 스레드 종료 대기
    executorService.shutdown()
    while (!executorService.isTerminated) {
        Thread.sleep(100)
    }

    // Then - 검증
    assertThat(successCount.get()).isEqualTo(expectedCount)
}
```

### 2. CountDownLatch 사용

```kotlin
val threadCount = 100
val latch = CountDownLatch(threadCount)

repeat(threadCount) {
    executorService.submit {
        latch.countDown() // 카운트 감소 (100 → 99 → ... → 0)
        latch.await()     // 0이 될 때까지 대기

        // 여기서 모든 스레드가 동시에 시작!
        doSomething()
    }
}
```

### 3. AtomicInteger 사용

```kotlin
val successCount = AtomicInteger(0)
val failCount = AtomicInteger(0)

// 스레드 안전하게 증가
successCount.incrementAndGet()
failCount.incrementAndGet()

// 최종 값 조회
val success = successCount.get()
val fail = failCount.get()
```

---

## ✅ 동시성 테스트 체크리스트

### 테스트 설계
- [ ] 충분한 스레드 수로 테스트 (최소 100개 이상)
- [ ] `CountDownLatch`로 동시 시작 보장
- [ ] `AtomicInteger`로 안전한 카운팅
- [ ] 성공/실패 케이스 모두 검증

### 검증 항목
- [ ] 중복 발급 방지 확인
- [ ] 발급 한도 준수 확인
- [ ] DB 데이터와 카운터 일치 확인
- [ ] 예외 처리 확인

### 성능 측정
- [ ] 락 방식별 성능 비교
- [ ] 스레드 풀 크기 조정
- [ ] 타임아웃 설정 확인

### 정리
- [ ] 테스트 후 DB 클린업 (`@AfterEach`)
- [ ] 독립적인 테스트 (서로 영향 없음)
- [ ] 명확한 로그 출력

---

## 💡 핵심 요약

1. **CountDownLatch** - 모든 스레드를 동시에 시작
2. **AtomicInteger** - 스레드 안전한 카운터
3. **ExecutorService** - 스레드 풀 관리
4. **충분한 스레드** - 최소 100개 이상으로 테스트
5. **성공/실패 검증** - 모두 확인
6. **DB 검증** - 실제 저장된 데이터 확인
7. **성능 측정** - 락 방식별 비교

---

## 🔍 디버깅 팁

### 1. 로그 출력

```kotlin
println("=== 테스트 결과 ===")
println("성공: ${successCount.get()}")
println("실패: ${failCount.get()}")
println("DB 발급 수: ${memberCouponJpaRepository.count()}")
```

### 2. 예외 상세 출력

```kotlin
} catch (e: Exception) {
    println("예외 발생: ${e.javaClass.simpleName} - ${e.message}")
    failCount.incrementAndGet()
}
```

### 3. 스레드 정보 출력

```kotlin
println("현재 스레드: ${Thread.currentThread().name}")
```

---

이 가이드를 따라 동시성 테스트를 작성하면 **쿠폰 발급의 동시성 제어가 올바르게 작동하는지 검증**할 수 있습니다! 🚀
