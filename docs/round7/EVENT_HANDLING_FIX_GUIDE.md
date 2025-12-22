# 이벤트 핸들링 개선 가이드

## 📋 배경

### 리뷰어 피드백
> AFTER_COMMIT으로하는 경우 메세지 유실되는 경우 기능이 비정상 동작할것 같아요.
> BEFORE_COMMIT으로 처리해서 트랜잭션 내에서 아토믹함을 보장하거나
> AFTER_COMMIT으로 하신뒤 보상 트랜잭션 혹은 다른 프로세스를 통해 최종적 일관성을 만들어야 할 것 같아요!

### 현재 문제점

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/like/event/ProductLikeEventHandler.kt`

```kotlin
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
fun handleProductLiked(event: ProductLikedEvent) {
    coroutineScope.launch {
        try {
            productLikeEventProcessor.processProductLiked(event.productId)
        } catch (e: Exception) {
            logger.error("좋아요 집계 실패: productId=${event.productId}", e)
        }
    }
}
```

**문제:**
1. **이벤트 유실 가능**: AFTER_COMMIT 후 서버 장애 시 이벤트 처리 안됨
2. **데이터 불일치**: Like는 저장되었지만 likesCount는 증가 안됨
3. **재시도 없음**: 예외 발생 시 로깅만 하고 끝

**시나리오:**
```
사용자 좋아요 클릭
  ↓
Like 저장 → 커밋 ✅
  ↓
AFTER_COMMIT 이벤트 발행
  ↓
💥 서버 크래시
  ↓
❌ likesCount 업데이트 안됨 (이벤트 유실)
```

---

## 🎯 해결 방안: BEFORE_COMMIT 전환

### 참고 PR
- [PR #54](https://github.com/Loopers-dev-lab/loopers-spring-kotlin-template/pull/54)
- [PR #55](https://github.com/Loopers-dev-lab/loopers-spring-kotlin-template/pull/55)
- [PR #56](https://github.com/Loopers-dev-lab/loopers-spring-kotlin-template/pull/56)

모두 **BEFORE_COMMIT**을 사용하여 핵심 비즈니스 로직의 원자성을 보장하고 있습니다.

---

---

## ⚠️ BEFORE_COMMIT 사용 시 주의사항

### 언제 BEFORE_COMMIT을 사용하면 안 되나요?

BEFORE_COMMIT은 메인 트랜잭션을 길게 만들기 때문에 다음 경우에는 **사용 금지**:

1. **외부 API 호출이 필요한 경우**
   - 예: 결제 PG사 호출, 알림 서비스(Slack, SMS) 호출
   - 이유: 외부 API 타임아웃 시 메인 트랜잭션까지 롤백됨
   - 대안: AFTER_COMMIT + 보상 트랜잭션 또는 Round 8 Kafka 방식

2. **대용량 파일 처리**
   - 예: 이미지 리사이징, 동영상 인코딩
   - 이유: 트랜잭션 타임아웃 발생 가능
   - 대안: 비동기 Job Queue

3. **10ms 이상 걸리는 작업**
   - 예: 복잡한 통계 계산, 대량 데이터 집계
   - 이유: 사용자 응답 시간 저하
   - 대안: Round 8 Kafka 방식 (이벤트 저장 후 비동기 처리)

### 현재 케이스는 왜 BEFORE_COMMIT이 적합한가?

✅ **Product 단건 조회 + likesCount 증가**는 매우 빠른 작업 (~5ms)
✅ 외부 의존성 없음 (DB 내부 작업만)
✅ 데이터 정합성이 중요 (좋아요 개수는 실시간 반영 필요)

**결론**: Phase 1으로 BEFORE_COMMIT 적용 후 → Phase 2에서 성능 측정 → 문제 있으면 Round 8 Kafka로 전환

---

## 📝 Phase 1: 긴급 수정 (BEFORE_COMMIT 전환)

### 1. ProductLikeEventHandler 수정

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/like/event/ProductLikeEventHandler.kt`

**변경 전:**
```kotlin
@Component
class ProductLikeEventHandler(
    @Qualifier("eventCoroutineScope")
    private val coroutineScope: CoroutineScope,
    private val productLikeEventProcessor: ProductLikeEventProcessor
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)  // ❌
    fun handleProductLiked(event: ProductLikedEvent) {
        coroutineScope.launch {  // ❌ 비동기
            try {
                productLikeEventProcessor.processProductLiked(event.productId)
            } catch (e: Exception) {
                logger.error("좋아요 집계 실패: productId=${event.productId}", e)
            }
        }
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)  // ❌
    fun handleProductUnliked(event: ProductUnlikedEvent) {
        coroutineScope.launch {  // ❌ 비동기
            try {
                productLikeEventProcessor.processProductUnliked(event.productId)
            } catch (e: Exception) {
                logger.error("좋아요 취소 집계 실패: productId=${event.productId}", e)
            }
        }
    }
}
```

**변경 후:**
```kotlin
@Component
class ProductLikeEventHandler(
    private val productLikeEventProcessor: ProductLikeEventProcessor  // ✅ coroutineScope 제거
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @TransactionalEventListener(phase = TransactionPhase.BEFORE_COMMIT)  // ✅ BEFORE_COMMIT
    fun handleProductLiked(event: ProductLikedEvent) {
        // ✅ 동기 처리 - coroutineScope.launch 제거
        try {
            productLikeEventProcessor.processProductLiked(event.productId)
        } catch (e: Exception) {
            logger.error("좋아요 집계 실패: productId=${event.productId}", e)
            throw e  // ✅ 예외 전파 - 전체 트랜잭션 롤백
        }
    }

    @TransactionalEventListener(phase = TransactionPhase.BEFORE_COMMIT)  // ✅ BEFORE_COMMIT
    fun handleProductUnliked(event: ProductUnlikedEvent) {
        try {
            productLikeEventProcessor.processProductUnliked(event.productId)
        } catch (e: Exception) {
            logger.error("좋아요 취소 집계 실패: productId=${event.productId}", e)
            throw e  // ✅ 예외 전파
        }
    }
}
```

**주요 변경점:**
1. `AFTER_COMMIT` → `BEFORE_COMMIT`
2. `coroutineScope.launch` 제거 (동기 처리)
3. 예외 발생 시 `throw e`로 전체 트랜잭션 롤백
4. `@Qualifier("eventCoroutineScope")` 의존성 제거

---

### 2. ProductLikeEventProcessor 수정

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/like/event/ProductLikeEventHandler.kt`

**변경 전:**
```kotlin
@Component
class ProductLikeEventProcessor(
    private val productRepository: ProductRepository
) {
    @Transactional(propagation = Propagation.REQUIRES_NEW)  // ❌ 별도 트랜잭션
    fun processProductLiked(productId: Long) {
        val product = productRepository.findByIdWithLockOrThrow(productId)
        product.increaseLikesCount()
        productRepository.save(product)
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)  // ❌ 별도 트랜잭션
    fun processProductUnliked(productId: Long) {
        val product = productRepository.findByIdWithLockOrThrow(productId)
        product.decreaseLikesCount()
        productRepository.save(product)
    }
}
```

**변경 후:**
```kotlin
@Component
class ProductLikeEventProcessor(
    private val productRepository: ProductRepository
) {
    @Transactional(propagation = Propagation.REQUIRED)  // ✅ 같은 트랜잭션
    fun processProductLiked(productId: Long) {
        val product = productRepository.findByIdWithLockOrThrow(productId)
        product.increaseLikesCount()
        productRepository.save(product)
    }

    @Transactional(propagation = Propagation.REQUIRED)  // ✅ 같은 트랜잭션
    fun processProductUnliked(productId: Long) {
        val product = productRepository.findByIdWithLockOrThrow(productId)
        product.decreaseLikesCount()
        productRepository.save(product)
    }
}
```

**주요 변경점:**
- `REQUIRES_NEW` → `REQUIRED`
- 부모 트랜잭션(LikeService)과 같은 트랜잭션에서 실행
- 하나의 트랜잭션으로 Like 저장 + likesCount 업데이트 보장

---

### 3. 트랜잭션 흐름 변화

**변경 전 (AFTER_COMMIT):**
```
[트랜잭션 1: LikeService.addLike]
  ├─ Like 저장
  └─ 커밋 ✅
      ↓
[트랜잭션 2: ProductLikeEventProcessor] (비동기)
  ├─ Product 조회
  ├─ likesCount++
  └─ 커밋 (또는 실패 시 유실)
```

**변경 후 (BEFORE_COMMIT):**
```
[트랜잭션 1: LikeService.addLike]
  ├─ Like 저장
  ├─ [이벤트 핸들러]
  │   ├─ Product 조회
  │   └─ likesCount++
  └─ 전체 커밋 ✅ (또는 전체 롤백)
```

---

## ✅ 개선 효과

### Before (문제)
- ❌ Like 100개 저장되었지만 likesCount는 95 (5개 유실)
- ❌ 이벤트 유실 시 복구 불가
- ❌ 데이터 불일치

### After (해결)
- ✅ Like 저장 + likesCount 업데이트가 원자적
- ✅ 하나라도 실패하면 전체 롤백
- ✅ 데이터 일관성 100% 보장

---

## 🔍 테스트 방법

### 1. 기존 테스트 확인

**파일**: `apps/commerce-api/src/test/kotlin/com/loopers/application/like/LikeFacadeIntegrationTest.kt`

현재 테스트는 비동기 처리를 기다리는 코드가 있습니다:

```kotlin
// 비동기 이벤트 처리 대기 (최대 3초)
var retryCount = 0
var updatedProduct = productJpaRepository.findById(product.id!!).get()
while (updatedProduct.likesCount != 1 && retryCount < 30) {
    Thread.sleep(100)
    updatedProduct = productJpaRepository.findById(product.id!!).get()
    retryCount++
}
```

**변경 후에는 이 대기 로직이 불필요합니다!**

**수정 권장:**
```kotlin
@DisplayName("좋아요를 추가할 수 있다")
@Test
fun addLike() {
    val member = memberJpaRepository.save(...)
    val product = productJpaRepository.save(...)

    val result = likeFacade.addLike(member.memberId.value, product.id!!)

    assertThat(result).isNotNull
    assertThat(result.memberId).isEqualTo(member.memberId.value)
    assertThat(result.product.id).isEqualTo(product.id)

    // ✅ 동기 처리이므로 바로 확인 가능
    val updatedProduct = productJpaRepository.findById(product.id!!).get()
    assertThat(updatedProduct.likesCount).isEqualTo(1)
}
```

### 2. 트랜잭션 롤백 테스트 추가

**파일**: `apps/commerce-api/src/test/kotlin/com/loopers/domain/like/event/ProductLikeEventHandlerRollbackTest.kt` (신규 생성)

```kotlin
package com.loopers.domain.like.event

import com.loopers.application.like.LikeFacade
import com.loopers.domain.member.Member
import com.loopers.infrastructure.jpa.like.LikeJpaRepository
import com.loopers.infrastructure.jpa.member.MemberJpaRepository
import com.loopers.infrastructure.jpa.product.ProductJpaRepository
import com.loopers.support.error.CoreException
import com.loopers.supports.test.DatabaseCleanUp
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import java.time.LocalDate

@SpringBootTest
class ProductLikeEventHandlerRollbackTest @Autowired constructor(
    private val likeFacade: LikeFacade,
    private val memberJpaRepository: MemberJpaRepository,
    private val likeJpaRepository: LikeJpaRepository,
    private val productJpaRepository: ProductJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp
) {

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }

    @DisplayName("좋아요 집계 실패 시 Like도 저장되지 않는다 (전체 롤백)")
    @Test
    fun rollbackLikeWhenCountUpdateFails() {
        // given
        val member = memberJpaRepository.save(
            Member(
                memberId = "testUser",
                email = "test@example.com",
                birthDate = LocalDate.of(1990, 1, 1),
                gender = "M"
            )
        )
        val invalidProductId = 999999L  // 존재하지 않는 상품

        // when & then: 상품 조회 실패로 예외 발생
        assertThrows<CoreException> {
            likeFacade.addLike(member.memberId.value, invalidProductId)
        }

        // then: Like도 저장되지 않음 (전체 롤백 확인)
        val likes = likeJpaRepository.findAll()
        assertThat(likes).isEmpty()
    }
}
```

---

## 📊 성능 영향 분석

### 트랜잭션 시간 증가

**변경 전:**
- Like 저장: ~10ms
- **전체 응답 시간: ~10ms**

**변경 후:**
- Like 저장: ~10ms
- Product 조회 + 업데이트: ~5ms
- **전체 응답 시간: ~15ms**

**결론:** 약 5ms 증가하지만 **데이터 일관성**을 위해 감수할 가치가 있음

### 락 경합 가능성

동일 Product에 대한 동시 좋아요 요청 시:
- `findByIdWithLockOrThrow()` 사용으로 비관적 락 적용
- 순차 처리로 정확성 보장

**동시성 테스트 확인:**
- `apps/commerce-api/src/test/kotlin/com/loopers/concurrency/ConcurrencyIntegrationTest.kt`
- 100명 동시 좋아요 테스트 이미 존재 ✅

---

## 📚 참고 자료

### 관련 PR
- [PR #54: 비동기 처리 활성화](https://github.com/Loopers-dev-lab/loopers-spring-kotlin-template/pull/54)
- [PR #55: 트랜잭션 경계 분리](https://github.com/Loopers-dev-lab/loopers-spring-kotlin-template/pull/55)
- [PR #56: 인터페이스 분리 원칙](https://github.com/Loopers-dev-lab/loopers-spring-kotlin-template/pull/56)
- [PR #58: DomainEvent 표준화](https://github.com/Loopers-dev-lab/loopers-spring-kotlin-template/pull/58)

### Spring TransactionalEventListener
- [공식 문서](https://docs.spring.io/spring-framework/reference/data-access/transaction/event.html)

### 트랜잭션 전파 (Propagation)
- `REQUIRED`: 기존 트랜잭션 참여 (없으면 새로 생성)
- `REQUIRES_NEW`: 항상 새 트랜잭션 생성
- [Spring 공식 문서](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/tx-propagation.html)

---

## ✅ 체크리스트

### Phase 1 수정 완료 체크
- [ ] ProductLikeEventHandler: `AFTER_COMMIT` → `BEFORE_COMMIT` 변경
- [ ] ProductLikeEventHandler: `coroutineScope.launch` 제거
- [ ] ProductLikeEventHandler: 예외 발생 시 `throw e` 추가
- [ ] ProductLikeEventProcessor: `REQUIRES_NEW` → `REQUIRED` 변경
- [ ] 테스트 실행 확인 (`./gradlew :apps:commerce-api:test`)
- [ ] LikeFacadeIntegrationTest 비동기 대기 로직 제거 (선택)

### Phase 2 개선 완료 체크 (선택)
- [ ] LikeEventPublisher 인터페이스 생성
- [ ] SpringLikeEventPublisher 구현체 생성
- [ ] LikeService 의존성 변경
- [ ] DomainEvent 인터페이스 생성 (선택)
- [ ] 멱등성 체크 로직 추가 (선택)

---

## 🎯 최종 결과

### 변경 전
```
사용자 좋아요 클릭
  ↓
[트랜잭션] Like 저장 → 커밋 ✅
  ↓
[비동기] likesCount++ (실패 가능) ⚠️
```

### 변경 후
```
사용자 좋아요 클릭
  ↓
[트랜잭션]
  ├─ Like 저장
  ├─ likesCount++
  └─ 전체 커밋 ✅ (또는 전체 롤백)
```

**핵심:**
- ✅ **원자성 보장**: 하나의 트랜잭션으로 묶임
- ✅ **데이터 일관성**: 100% 정확한 카운트
- ✅ **이벤트 유실 방지**: BEFORE_COMMIT으로 커밋 전 처리

---

**작성일**: 2025-12-14
**작성자**: Claude Code
**관련 이슈**: 리뷰어 피드백 - AFTER_COMMIT 이벤트 유실 문제
