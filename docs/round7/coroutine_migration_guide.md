# 코루틴 마이그레이션 가이드

Spring의 `@Async`를 코루틴으로 전환하는 단계별 가이드입니다.

---

## 🎯 목표

`@Async` + `ThreadPoolTaskExecutor` → 코루틴 + `CoroutineScope`

**기대 효과:**
- 스레드 사용량 감소 (50개 → 10~20개)
- 메모리 효율 증가
- 더 많은 동시 작업 처리 가능

---

## 📋 체크리스트

### Phase 1: 의존성 추가
- [ ] `build.gradle.kts`에 코루틴 의존성 추가

### Phase 2: 코루틴 설정
- [ ] `CoroutineConfig` 클래스 생성
- [ ] 이벤트 처리용 `CoroutineScope` Bean 등록

### Phase 3: 이벤트 핸들러 전환
- [ ] `ProductLikeEventHandler` 전환
- [ ] `OrderEventHandler` 전환
- [ ] `CouponEventHandler` 전환
- [ ] `DataPlatformEventHandler` 전환
- [ ] `UserActionEventHandler` 전환

### Phase 4: AsyncConfig 제거
- [ ] `@EnableAsync` 제거
- [ ] `AsyncConfig` 클래스 삭제

### Phase 5: 테스트 및 검증
- [ ] 동시성 테스트 실행
- [ ] 이벤트 발행/처리 검증

---

## Step 1: 의존성 추가

### 📝 할 일
`build.gradle.kts` 파일을 열어서 코루틴 의존성을 추가하세요.

### 📍 파일 위치
```
apps/commerce-api/build.gradle.kts
```

### ✅ 추가할 코드
```kotlin
dependencies {
    // 기존 의존성들...

    // 코루틴 추가
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-reactor:1.7.3")

    // 테스트용
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
}
```

### 💡 설명
- `kotlinx-coroutines-core`: 코루틴 핵심 기능
- `kotlinx-coroutines-reactor`: Spring WebFlux와의 통합 (선택사항)
- `kotlinx-coroutines-test`: 코루틴 테스트 유틸리티

---

## Step 2: 코루틴 설정 추가

### 📝 할 일
`CoroutineConfig` 클래스를 생성하여 코루틴 스코프를 설정하세요.

### 📍 파일 위치
```
apps/commerce-api/src/main/kotlin/com/loopers/config/CoroutineConfig.kt
```

### ✅ 작성할 코드
```kotlin
package com.loopers.config

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.slf4j.LoggerFactory
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import kotlin.coroutines.CoroutineContext

@Configuration
class CoroutineConfig {

    private val logger = LoggerFactory.getLogger(javaClass)

    /**
     * 이벤트 처리용 코루틴 디스패처
     * Dispatchers.IO: I/O 작업에 최적화 (DB 쿼리, HTTP 호출 등)
     */
    @Bean("eventDispatcher")
    fun eventDispatcher(): CoroutineDispatcher {
        // TODO: Dispatchers.IO를 50개 병렬로 제한
        // 힌트: limitedParallelism(50) 사용
        return TODO("Dispatchers.IO.limitedParallelism(??)")
    }

    /**
     * 코루틴 예외 핸들러
     * 하나의 코루틴 실패가 전체 스코프를 중단시키지 않도록
     */
    @Bean("eventExceptionHandler")
    fun eventExceptionHandler(): CoroutineExceptionHandler {
        return CoroutineExceptionHandler { _, throwable ->
            // TODO: 에러 로그 출력
            // 힌트: logger.error("코루틴 실행 중 예외 발생", throwable)
            TODO("에러 로깅 구현")
        }
    }

    /**
     * 이벤트 처리용 코루틴 스코프
     * SupervisorJob: 자식 코루틴 실패가 형제/부모에 영향 안 줌
     */
    @Bean("eventCoroutineScope")
    fun eventCoroutineScope(
        eventDispatcher: CoroutineDispatcher,
        eventExceptionHandler: CoroutineExceptionHandler
    ): CoroutineScope {
        // TODO: CoroutineScope 생성
        // 힌트: CoroutineScope(eventDispatcher + SupervisorJob() + eventExceptionHandler)
        return TODO("CoroutineScope 생성")
    }
}
```

### 💡 학습 포인트
- **Dispatchers.IO**: I/O 작업용 디스패처 (기본 64개 스레드)
- **limitedParallelism(N)**: 최대 N개까지만 병렬 실행
- **SupervisorJob**: 한 코루틴 실패가 다른 코루틴에 영향 안 줌
- **CoroutineExceptionHandler**: 예외 처리 핸들러

### 🔍 정답 확인
<details>
<summary>정답 보기 (클릭)</summary>

```kotlin
@Bean("eventDispatcher")
fun eventDispatcher(): CoroutineDispatcher {
    return Dispatchers.IO.limitedParallelism(50)
}

@Bean("eventExceptionHandler")
fun eventExceptionHandler(): CoroutineExceptionHandler {
    return CoroutineExceptionHandler { _, throwable ->
        logger.error("코루틴 실행 중 예외 발생", throwable)
    }
}

@Bean("eventCoroutineScope")
fun eventCoroutineScope(
    eventDispatcher: CoroutineDispatcher,
    eventExceptionHandler: CoroutineExceptionHandler
): CoroutineScope {
    return CoroutineScope(
        eventDispatcher + SupervisorJob() + eventExceptionHandler
    )
}
```
</details>

---

## Step 3-1: ProductLikeEventHandler 전환

### 📝 할 일
`ProductLikeEventHandler`를 코루틴 방식으로 전환하세요.

### 📍 파일 위치
```
apps/commerce-api/src/main/kotlin/com/loopers/domain/like/event/ProductLikeEventHandler.kt
```

### ✅ 수정할 코드

**Before (현재):**
```kotlin
@Component
class ProductLikeEventHandler(
    private val productRepository: ProductRepository
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    // ⚠️ @Async가 없음 → 동기적으로 실행됨 (사용자 요청 스레드에서 직접 실행)
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handleProductLiked(event: ProductLikedEvent) {
        try {
            logger.info("좋아요 집계 시작: productId=${event.productId}")

            val product = productRepository.findByIdWithLockOrThrow(event.productId)
            product.increaseLikesCount()

            logger.info("좋아요 집계 완료: productId=${event.productId}")
        } catch (e: Exception) {
            logger.error("좋아요 집계 실패: productId=${event.productId}, error=${e.message}", e)
        }
    }
}
```

**After (TODO):**
```kotlin
@Component
class ProductLikeEventHandler(
    private val productRepository: ProductRepository,
    // TODO: eventCoroutineScope 주입
    // 힌트: @Qualifier("eventCoroutineScope") private val coroutineScope: CoroutineScope
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    // TODO: @Transactional(propagation = REQUIRES_NEW) 제거 (코루틴 내부에서는 동작 안 함)
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handleProductLiked(event: ProductLikedEvent) {
        // TODO: coroutineScope.launch { } 로 감싸기
        // TODO: withContext(Dispatchers.IO) { } 로 DB 작업 감싸기
        // TODO: product.increaseLikesCount() 후 productRepository.save(product) 호출
        //       (코루틴에서는 변경감지가 동작하지 않으므로 명시적 save 필요!)
        // 힌트:
        // coroutineScope.launch {
        //     try {
        //         withContext(Dispatchers.IO) {
        //             val product = productRepository.findByIdWithLockOrThrow(event.productId)
        //             product.increaseLikesCount()
        //             productRepository.save(product) // ⚠️ 중요: 명시적 save
        //         }
        //     } catch (e: Exception) {
        //         logger.error(...)
        //     }
        // }
    }
}
```

### 💡 학습 포인트
- **현재 문제**: `@Async`가 없어서 동기적으로 실행됨 → 사용자가 집계 완료까지 대기
- **코루틴 전환 효과**: 사용자는 즉시 응답받고, 집계는 백그라운드에서 비동기 처리
- `coroutineScope.launch { }`: 코루틴 시작 (Fire and forget)
- `withContext(Dispatchers.IO) { }`: 블로킹 I/O 작업 명시
- JPA 쿼리는 여전히 블로킹이므로 `withContext` 필수
- **⚠️ 중요**: `@Transactional`은 ThreadLocal 기반이라 코루틴에서 동작 안 함
  - 코루틴은 스레드를 전환할 수 있어서 트랜잭션 컨텍스트가 유지되지 않음
  - **해결**: 엔티티 변경 후 `productRepository.save(product)` 명시적 호출
  - 변경감지 대신 명시적 저장으로 변경

### 🔍 정답 확인
<details>
<summary>정답 보기 (클릭)</summary>

```kotlin
@Component
class ProductLikeEventHandler(
    private val productRepository: ProductRepository,
    @Qualifier("eventCoroutineScope")
    private val coroutineScope: CoroutineScope
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handleProductLiked(event: ProductLikedEvent) {
        coroutineScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val product = productRepository.findByIdWithLockOrThrow(event.productId)
                    product.increaseLikesCount()
                    productRepository.save(product) // ⚠️ 명시적 save 필수!
                }
            } catch (e: Exception) {
                logger.error("좋아요 집계 실패: productId=${event.productId}", e)
            }
        }
    }
}
```

**왜 `save()`가 필요한가?**
- `@Transactional`은 ThreadLocal을 사용해 트랜잭션 컨텍스트를 관리
- 코루틴은 `withContext`로 스레드를 전환할 수 있음
- 스레드가 바뀌면 ThreadLocal 컨텍스트가 유실됨
- 따라서 JPA 변경감지(Dirty Checking)가 동작하지 않음
- **해결책**: 엔티티 변경 후 명시적으로 `save()` 호출

</details>

---

## Step 3-2: OrderEventHandler 전환

### 📝 할 일
`OrderEventHandler`의 두 이벤트 핸들러를 모두 전환하세요.

### 📍 파일 위치
```
apps/commerce-api/src/main/kotlin/com/loopers/application/order/OrderEventHandler.kt
```

### ✅ 수정할 코드

**Before (현재):**
```kotlin
@Component
class OrderEventHandler(
    private val orderService: OrderService,
    @Qualifier("eventCoroutineScope")
    private val coroutineScope: CoroutineScope  // ⚠️ 주입은 받았지만 사용 안 함
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    // 동기 이벤트 - 코루틴 불필요
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handlePaymentCompleted(event: PaymentCompletedEvent) {
        try {   
            logger.info("결제 완료 처리 시작: orderId=${event.orderId}")
            orderService.completeOrderWithPayment(event.orderId)
            logger.info("결제 완료 처리 완료: orderId=${event.orderId}")
        } catch (e: Exception) {
            logger.error("결제 완료 처리 실패: orderId=${event.orderId}, error=${e.message}", e)
            throw e
        }
    }

    // ⚠️ 비동기로 전환 필요 - 현재는 동기로 실행됨
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handlePaymentFailed(event: PaymentFailedEvent) {
        try {
            logger.info("결제 실패 처리 시작: orderId=${event.orderId}")
            // TODO: 실제로는 로깅만 해야 하는데 잘못된 로직
            orderService.completeOrderWithPayment(event.orderId)
            logger.info("결제 실패 처리 완료: orderId=${event.orderId}")
        } catch (e: Exception) {
            logger.error("결제 실패 처리 실패: orderId=${event.orderId}, error=${e.message}", e)
            throw e
        }
    }
}
```

### 💡 힌트
- `handlePaymentCompleted`: 동기 이벤트 (결제 완료 후 주문 상태 변경 필수) → 코루틴 불필요
- `handlePaymentFailed`: 비동기 로깅만 필요 → 코루틴으로 전환

### 🤔 생각해보기
1. 왜 `handlePaymentCompleted`는 코루틴이 필요 없을까요?
2. `handlePaymentFailed`의 잘못된 로직은 무엇일까요?
3. `@Transactional(propagation = Propagation.REQUIRES_NEW)`는 그대로 유지해야 할까요?

### 🔍 정답 확인
<details>
<summary>정답 보기 (클릭)</summary>

```kotlin
@Component
class OrderEventHandler(
    private val orderService: OrderService,
    @Qualifier("eventCoroutineScope")
    private val coroutineScope: CoroutineScope
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    // 동기 이벤트 - 결제 완료 후 주문 상태 변경은 순서 보장 필요
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handlePaymentCompleted(event: PaymentCompletedEvent) {
        try {
            logger.info("결제 완료 처리 시작: orderId=${event.orderId}")
            orderService.completeOrderWithPayment(event.orderId)
            logger.info("결제 완료 처리 완료: orderId=${event.orderId}")
        } catch (e: Exception) {
            logger.error("결제 완료 처리 실패: orderId=${event.orderId}, error=${e.message}", e)
            throw e
        }
    }

    // 비동기 이벤트 - 로깅만 하므로 코루틴으로 전환
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handlePaymentFailed(event: PaymentFailedEvent) {
        coroutineScope.launch {
            logger.info("결제 실패 처리: orderId=${event.orderId}")
        }
    }
}
```

**설명:**
- `handlePaymentCompleted`: 주문 완료 처리가 동기적으로 이루어져야 함 → 코루틴 불필요
- `handlePaymentFailed`: 단순 로깅만 필요 → 코루틴으로 비동기 처리
  - ⚠️ 기존 코드에서 `orderService.completeOrderWithPayment()` 호출은 잘못된 로직
  - 결제 실패 시에는 로깅만 하고, 주문 완료를 호출하면 안 됨
- `@Transactional(REQUIRES_NEW)`: 동기 이벤트는 그대로 유지 (별도 트랜잭션 필요)

</details>

---

## Step 3-3: DataPlatformEventHandler 전환

### 📝 할 일
데이터 플랫폼 전송 핸들러를 전환하세요.

### 📍 파일 위치
```
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/DataPlatformEventHandler.kt
```

### ✅ 직접 작성해보세요!

**현재 코드:**
```kotlin
@Component
class DataPlatformEventHandler(
    private val dataPlatformClient: DataPlatformClient
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handleOrderCreated(event: OrderCreatedEvent) {
        logger.info("주문 데이터 플랫폼 전송 시작: orderId=${event.orderId}")
        // ... 전송 로직
    }

    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handlePaymentCompleted(event: PaymentCompletedEvent) {
        logger.info("결제 데이터 플랫폼 전송 시작: orderId=${event.orderId}")
        // ... 전송 로직
    }
}
```

### 💡 체크리스트
- [ ] `coroutineScope` 주입
- [ ] `@Async` 제거
- [ ] `coroutineScope.launch { }` 사용
- [ ] `withContext(Dispatchers.IO) { }` 사용 (HTTP 호출이 블로킹이므로)

### 🔍 정답 확인
<details>
<summary>정답 보기 (클릭)</summary>

```kotlin
@Component
class DataPlatformEventHandler(
    private val dataPlatformClient: DataPlatformClient,
    @Qualifier("eventCoroutineScope")
    private val coroutineScope: CoroutineScope
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handleOrderCreated(event: OrderCreatedEvent) {
        coroutineScope.launch {
            try {
                logger.info("주문 데이터 플랫폼 전송 시작: orderId=${event.orderId}")
                withContext(Dispatchers.IO) {
                    dataPlatformClient.sendOrderData(
                        orderId = event.orderId,
                        memberId = event.memberId,
                        amount = event.orderAmount
                    )
                }
                logger.info("주문 데이터 플랫폼 전송 완료: orderId=${event.orderId}")
            } catch (e: Exception) {
                logger.error("주문 데이터 플랫폼 전송 실패: orderId=${event.orderId}", e)
            }
        }
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handlePaymentCompleted(event: PaymentCompletedEvent) {
        coroutineScope.launch {
            try {
                logger.info("결제 데이터 플랫폼 전송 시작: orderId=${event.orderId}")
                withContext(Dispatchers.IO) {
                    dataPlatformClient.sendPaymentData(
                        paymentId = event.paymentId,
                        orderId = event.orderId,
                        memberId = event.memberId,
                        amount = event.amount
                    )
                }
                logger.info("결제 데이터 플랫폼 전송 완료: orderId=${event.orderId}")
            } catch (e: Exception) {
                logger.error("결제 데이터 플랫폼 전송 실패: orderId=${event.orderId}", e)
            }
        }
    }
}
```
</details>

---

## Step 3-4: 나머지 핸들러 전환

### 📝 할 일
나머지 이벤트 핸들러들도 동일한 패턴으로 전환하세요.

### 📍 전환할 파일들
1. `CouponEventHandler.kt`
2. `UserActionEventHandler.kt`

### 💡 패턴
```kotlin
// Before
@Async
@TransactionalEventListener
fun handleEvent(event: SomeEvent) {
    // 로직
}

// After
@TransactionalEventListener
fun handleEvent(event: SomeEvent) {
    coroutineScope.launch {
        try {
            withContext(Dispatchers.IO) {
                // 로직
            }
        } catch (e: Exception) {
            logger.error("...")
        }
    }
}
```

---

## Step 4: AsyncConfig 제거

### 📝 할 일
모든 핸들러 전환이 완료되면 `AsyncConfig`를 제거하세요.

### ✅ 체크리스트
- [ ] 모든 `@Async` 사용처 제거 확인
- [ ] `@EnableAsync` 제거
- [ ] `AsyncConfig.kt` 파일 삭제

### 📍 파일 위치
```
apps/commerce-api/src/main/kotlin/com/loopers/config/AsyncConfig.kt
```

### 🔍 확인 방법
```bash
# @Async 사용처 검색
grep -r "@Async" apps/commerce-api/src/main/kotlin/
# 결과가 없어야 함
```

---

## Step 5: 테스트

### 📝 할 일
동시성 테스트를 실행하여 코루틴 전환이 정상 작동하는지 확인하세요.

### ✅ 실행 명령
```bash
./gradlew :apps:commerce-api:test --tests "com.loopers.concurrency.ConcurrencyIntegrationTest"
```

### 💡 확인 포인트
1. ✅ 모든 테스트 통과
2. ✅ 좋아요 집계가 비동기로 처리됨
3. ✅ 이벤트 핸들러 로그 확인

### 📊 예상 성능 개선
```
Before (Thread):
- maxPoolSize: 50
- 100개 이벤트 → 50개까지만 동시 처리

After (Coroutine):
- limitedParallelism: 50
- 100개 이벤트 → 100개 모두 시작 가능
- 실제 스레드: 10~20개만 사용
```

---

## 🎓 학습 정리

### 핵심 개념

1. **CoroutineScope**
   - 코루틴의 생명주기 관리
   - SupervisorJob으로 격리

2. **Dispatchers**
   - `Dispatchers.IO`: I/O 작업용
   - `Dispatchers.Default`: CPU 작업용
   - `limitedParallelism(N)`: 병렬 제한

3. **withContext**
   - 블로킹 작업 명시
   - JPA 쿼리는 반드시 `withContext(Dispatchers.IO)` 필요

4. **launch vs async**
   - `launch`: Fire and forget (결과 불필요)
   - `async`: Deferred<T> 반환 (결과 필요)

### 주의사항

1. ⚠️ **JPA는 여전히 블로킹**
   - 코루틴으로 스레드는 절약되지만
   - DB 커넥션은 여전히 필요
   - R2DBC 전환 시 진짜 논블로킹

2. ⚠️ **예외 처리 필수**
   - `CoroutineExceptionHandler` 등록
   - 각 `launch` 블록에 try-catch

3. ⚠️ **트랜잭션 주의 (매우 중요!)**
   - 코루틴은 `withContext`로 스레드를 전환할 수 있음
   - `@Transactional`은 ThreadLocal 기반이라 스레드 전환 시 컨텍스트 유실
   - **JPA 변경감지(Dirty Checking)가 동작하지 않음!**
   - **해결책**: 엔티티 변경 후 반드시 `repository.save()` 명시적 호출
   - 예: `product.increaseLikesCount()` 후 `productRepository.save(product)` 필수

---

## 📚 추가 학습 자료

1. **공식 문서**
   - [Kotlin Coroutines Guide](https://kotlinlang.org/docs/coroutines-guide.html)
   - [Spring + Coroutines](https://spring.io/guides/tutorials/spring-boot-kotlin/)

2. **추천 블로그**
   - [코루틴 공식 가이드 한글 번역](https://myungpyo.medium.com/코루틴-공식-가이드-자세히-읽기-part-0-20230510-6b8f8c0a0e0)
   - [Spring에서 코루틴 제대로 쓰기](https://www.notion.so/Spring-Coroutine-e4a7f1d8e5b74f7c9c0f8e9d7a3b5c2f)

3. **다음 단계**
   - R2DBC 학습 (진짜 논블로킹 DB)
   - Flow API (코루틴 스트림)
   - WebFlux + Coroutine (완전한 Reactive Stack)

---

## 🐛 트러블슈팅

### Q1: "CoroutineScope not found" 에러
```
A: @Qualifier("eventCoroutineScope") 확인
   Bean 이름이 일치하는지 체크
```

### Q2: 이벤트가 처리되지 않음
```
A: coroutineScope.launch { } 로 제대로 감쌌는지 확인
   withContext(Dispatchers.IO) { } 사용했는지 확인
```

### Q3: 엔티티 변경이 DB에 반영되지 않음
```
A: 코루틴에서는 @Transactional의 변경감지가 동작하지 않음
   해결: 엔티티 변경 후 repository.save() 명시적 호출

   예시:
   ❌ product.increaseLikesCount() // 반영 안 됨
   ✅ product.increaseLikesCount()
      productRepository.save(product) // 명시적 save
```

### Q4: "No EntityManager" 에러
```
A: withContext(Dispatchers.IO) { } 안에서 JPA 쿼리 실행했는지 확인
   JPA는 블로킹 작업이므로 Dispatchers.IO 사용 필수
```

---

화이팅! 궁금한 점 있으면 언제든 물어보세요! 💪
