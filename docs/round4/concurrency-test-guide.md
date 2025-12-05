# 동시성 테스트 가이드

## 개요

이 문서는 **4가지 동시성 요구사항**에 대한 테스트 작성 가이드입니다.

| # | 요구사항 | 비관적 락 적용 위치 |
|---|---------|-------------------|
| 1 | 좋아요 개수 정합성 | `ProductRepository.findByIdWithLock()` |
| 2 | 쿠폰 1회만 사용 | `MemberCouponRepository.findByMemberIdAndCouponIdWithLock()` |
| 3 | 포인트 정합성 | `MemberRepository.findByMemberIdWithLock()` |
| 4 | 재고 정합성 | `ProductRepository.findAllByIdInWithLock()` |

---

## 테스트 파일 위치

```
apps/commerce-api/src/test/kotlin/com/loopers/concurrency/
└── ConcurrencyIntegrationTest.kt
```

---

## 기본 구조

### 1. 테스트 클래스 설정

```kotlin
@SpringBootTest
class ConcurrencyIntegrationTest @Autowired constructor(
    private val likeFacade: LikeFacade,
    private val orderFacade: OrderFacade,
    private val memberJpaRepository: MemberJpaRepository,
    private val productJpaRepository: ProductJpaRepository,
    // ... 필요한 Repository들
    private val databaseCleanUp: DatabaseCleanUp,
) {
    private lateinit var brand: Brand

    @BeforeEach
    fun setUp() {
        // 테스트 데이터 초기 설정
    }

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }
}
```

### 2. 동시성 테스트 기본 패턴

```kotlin
@Test
fun concurrencyTest() {
    // 1. 테스트 데이터 준비
    val product = createProduct(10)
    val members = (1..20).map { createMember("user$it", 100_000) }
    
    // 2. 스레드 설정
    val executor = Executors.newFixedThreadPool(20)
    val latch = CountDownLatch(1)
    
    // 3. 작업 제출 (아직 실행 안 됨)
    members.forEach { member ->
        executor.submit {
            try {
                latch.await()  // 신호 대기
                orderFacade.createOrder(...)
            } catch (e: Exception) {
                println("실패: ${e.message}")
            }
        }
    }
    
    // 4. 동시 시작 신호
    latch.countDown()
    
    // 5. 종료 대기
    executor.shutdown()
    while (!executor.isTerminated) Thread.sleep(50)
    
    // 6. 검증
    val result = productJpaRepository.findById(product.id).get()
    assertThat(result.stock.quantity).isEqualTo(0)
}
```

---

## 작성할 테스트 목록

### 1. 좋아요 동시성 테스트
- **시나리오**: 동일한 상품에 100명이 동시에 좋아요
- **검증**: 좋아요 개수가 정확히 100개

### 2. 쿠폰 동시성 테스트
- **시나리오**: 동일한 쿠폰으로 10개 기기에서 동시 주문
- **검증**: 쿠폰은 1번만 사용됨

### 3. 포인트 동시성 테스트
- **시나리오**: 동일한 유저가 5개 주문을 동시에 수행
- **검증**: 포인트가 정확히 차감됨

### 4. 재고 동시성 테스트
- **시나리오**: 재고 10개 상품에 20명이 동시 주문
- **검증**: 10명만 성공, 재고는 0

---

## Helper Methods

```kotlin
private fun createMember(memberId: String, point: Long): Member {
    val member = memberJpaRepository.save(
        Member(
            memberId = MemberId(memberId),
            email = Email("$memberId@test.com"),
            birthDate = BirthDate.from("2000-01-01"),
            gender = Gender.MALE
        )
    )
    if (point > 0) {
        member.chargePoint(point)
        memberJpaRepository.save(member)
    }
    return member
}

private fun createProduct(stock: Int, price: Long = 10_000L): Product {
    return productJpaRepository.save(
        Product(
            name = "테스트 상품",
            description = "테스트용 상품입니다",
            price = Money(price),
            stock = Stock(stock),
            brand = brand
        )
    )
}

private fun createCoupon(): Coupon {
    // 쿠폰 생성 로직
}

private fun createMemberCoupon(memberId: String, coupon: Coupon): MemberCoupon {
    // 회원 쿠폰 발급 로직
}
```

---

## 핵심 도구

### CountDownLatch
모든 스레드를 동시에 시작시키는 도구

```kotlin
val latch = CountDownLatch(1)  // 신호용

// 작업 제출
executor.submit {
    latch.await()  // 신호 대기
    // 작업 수행
}

// 모든 작업 제출 후 신호 발송
latch.countDown()
```

### ExecutorService
스레드 풀 관리

```kotlin
val executorService = Executors.newFixedThreadPool(32)
executorService.submit { /* task */ }
executorService.shutdown()
while (!executorService.isTerminated) {
    Thread.sleep(100)
}
```

### AtomicInteger (선택)
성공/실패 카운트가 필요한 경우

```kotlin
val successCount = AtomicInteger(0)
successCount.incrementAndGet()
```

---

## 실행 방법

```bash
# 전체 테스트
./gradlew :apps:commerce-api:test --tests "com.loopers.concurrency.*"

# 개별 테스트
./gradlew :apps:commerce-api:test --tests "com.loopers.concurrency.ConcurrencyIntegrationTest.likeConcurrencyTest"
```

---

## 체크리스트

- [ ] 좋아요 동시성: 100명 동시 좋아요 → 정확히 100개
- [ ] 쿠폰 동시성: 같은 쿠폰 10번 사용 → 1번만 성공
- [ ] 포인트 동시성: 5개 주문 동시 처리 → 정확히 차감
- [ ] 재고 동시성: 재고 10개에 20명 주문 → 10명만 성공

---

## 주의사항

1. **DB 클린업**: `@AfterEach`에서 반드시 테이블 초기화
2. **CountDownLatch**: 
   - `CountDownLatch(1)` 사용 (신호용)
   - 모든 작업 제출 후 `countDown()` 호출
   - 각 작업은 `await()`로 신호 대기
3. **스레드 풀**: 작업 개수만큼 스레드 생성
4. **ExecutorService**: 반드시 `shutdown()` 호출
5. **비관적 락**: Repository에서 `@Lock(LockModeType.PESSIMISTIC_WRITE)` 사용
