# Mockito Spy를 활용한 통합 테스트

## 1. Spy란?

**Spy**는 실제 객체를 감싸서(wrapping) **실제 동작은 그대로 수행하면서, 메서드 호출을 추적**할 수 있는 테스트 객체입니다.

---

## 2. Mock vs Spy 비교

| 구분 | Mock | Spy |
|------|------|-----|
| **객체 타입** | 가짜 객체 | 실제 객체를 감싼 것 |
| **동작 방식** | 모든 메서드가 stubbing 필요 | 실제 메서드가 실행됨 |
| **사용 목적** | 의존성 격리, 단위 테스트 | 실제 동작 + 호출 검증, 통합 테스트 |
| **반환값** | 기본적으로 null 또는 기본값 | 실제 메서드의 반환값 |

### 코드 비교
```kotlin
// Mock: 가짜 객체
@MockBean
private lateinit var memberFacade: MemberFacade
// memberFacade.joinMember() 호출 시 아무 동작도 하지 않음 (null 반환)

// Spy: 실제 객체를 감싼 것
@MockitoSpyBean
private lateinit var memberFacade: MemberFacade
// memberFacade.joinMember() 호출 시 실제로 회원 가입 동작 수행 (DB 저장 등)
```

---

## 3. Spy 사용 방법

### 3.1 통합 테스트에서 Spy 설정

```kotlin
@SpringBootTest
class MemberFacadeIntegrationTest @Autowired constructor(
    private val memberJpaRepository: MemberJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp,
) {
    @MockitoSpyBean
    private lateinit var memberFacade: MemberFacade

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }
}
```

**주요 어노테이션:**
- `@MockitoSpyBean`: Spring Boot의 실제 빈을 Spy로 감싸서 주입
- 실제 Spring Context에 등록된 빈을 사용하므로 모든 의존성이 실제로 동작

---

## 4. Spy 검증 예시

### 4.1 기본 메서드 호출 검증

```kotlin
@DisplayName("회원 가입 시 Member 저장이 수행된다")
@Test
fun saveMemberOnJoin() {
    // Given: 회원 가입 요청 데이터
    val command = JoinMemberCommand("user1", "test@email.com", "1990-05-15", "MALE")

    // When: 실제로 회원 가입 동작 수행 (DB 저장됨)
    memberFacade.joinMember(command)

    // Then: 메서드가 호출되었는지 검증
    verify(memberFacade).joinMember(any())
}
```

**동작 흐름:**
1. `memberFacade.joinMember(command)` 실행 → **실제로 DB에 저장**
2. `verify(memberFacade).joinMember(any())` → 메서드 호출 확인

---

### 4.2 다양한 검증 방법

#### 특정 파라미터로 호출되었는지 검증
```kotlin
@Test
fun verifyWithSpecificParameter() {
    val command = JoinMemberCommand("user1", "test@email.com", "1990-05-15", "MALE")

    memberFacade.joinMember(command)

    // 정확히 이 파라미터로 호출되었는지 검증
    verify(memberFacade).joinMember(command)
}
```

#### 호출 횟수 검증
```kotlin
@Test
fun verifyCallCount() {
    val command = JoinMemberCommand("user1", "test@email.com", "1990-05-15", "MALE")

    memberFacade.joinMember(command)
    memberFacade.joinMember(command)

    // 정확히 2번 호출되었는지 검증
    verify(memberFacade, times(2)).joinMember(any())
}
```

#### 호출되지 않았는지 검증
```kotlin
@Test
fun verifyNeverCalled() {
    // deleteMember 메서드가 호출되지 않았는지 검증
    verify(memberFacade, never()).deleteMember(any())
}
```

#### 최소/최대 호출 횟수 검증
```kotlin
@Test
fun verifyAtLeastOnce() {
    val command = JoinMemberCommand("user1", "test@email.com", "1990-05-15", "MALE")

    memberFacade.joinMember(command)
    memberFacade.joinMember(command)

    // 최소 1번 이상 호출되었는지 검증
    verify(memberFacade, atLeastOnce()).joinMember(any())

    // 최대 3번 이하로 호출되었는지 검증
    verify(memberFacade, atMost(3)).joinMember(any())
}
```

---

### 4.3 ArgumentCaptor를 활용한 파라미터 검증

메서드에 전달된 **실제 파라미터 값을 캡처**하여 검증할 수 있습니다.

```kotlin
@Test
fun captureAndVerifyArgument() {
    // Given
    val command = JoinMemberCommand("user1", "test@email.com", "1990-05-15", "MALE")

    // When
    memberFacade.joinMember(command)

    // Then: ArgumentCaptor로 파라미터 캡처
    val captor = argumentCaptor<JoinMemberCommand>()
    verify(memberFacade).joinMember(captor.capture())

    // 캡처한 값 검증
    val capturedCommand = captor.firstValue
    assertThat(capturedCommand.memberId).isEqualTo("user1")
    assertThat(capturedCommand.email).isEqualTo("test@email.com")
    assertThat(capturedCommand.gender).isEqualTo("MALE")
}
```

---

### 4.4 ArgumentMatcher를 활용한 조건부 검증

특정 조건을 만족하는 파라미터로 호출되었는지 검증합니다.

```kotlin
@Test
fun verifyWithArgumentMatcher() {
    // Given
    val command = JoinMemberCommand("user1", "test@email.com", "1990-05-15", "MALE")

    // When
    memberFacade.joinMember(command)

    // Then: 특정 조건을 만족하는 파라미터로 호출되었는지 검증
    verify(memberFacade).joinMember(
        argThat { cmd ->
            cmd.memberId == "user1" && cmd.email.contains("@")
        }
    )
}
```

---

## 5. 실전 활용 예시

### 5.1 포인트 충전 시나리오

```kotlin
@SpringBootTest
class PointServiceIntegrationTest {
    @MockitoSpyBean
    private lateinit var memberFacade: MemberFacade

    @Autowired
    private lateinit var pointService: PointService

    @Test
    fun chargePointAndVerify() {
        // Given: 회원 생성
        val memberId = "testUser1"
        val member = createMember(memberId)
        memberRepository.save(member)

        // When: 포인트 충전 (실제 동작 수행)
        pointService.chargePoint(memberId, 1000L)

        // Then: memberFacade의 chargePoint 메서드가 정확한 파라미터로 호출되었는지 검증
        verify(memberFacade).chargePoint(
            eq(memberId),
            eq(1000L)
        )

        // And: 실제 DB에 저장되었는지 확인
        val updatedMember = memberRepository.findById(memberId)
        assertThat(updatedMember?.point).isEqualTo(1000L)
    }
}
```

---

### 5.2 주문 처리 시나리오

```kotlin
@SpringBootTest
class OrderServiceIntegrationTest {
    @MockitoSpyBean
    private lateinit var paymentService: PaymentService

    @MockitoSpyBean
    private lateinit var inventoryService: InventoryService

    @Autowired
    private lateinit var orderService: OrderService

    @Test
    fun processOrderWithMultipleVerifications() {
        // Given
        val order = createOrder(productId = "P001", quantity = 2, amount = 20000L)

        // When: 주문 처리 (실제 동작 수행)
        orderService.processOrder(order)

        // Then: 여러 서비스가 올바른 순서로 호출되었는지 검증
        val inOrder = inOrder(inventoryService, paymentService)

        // 1. 재고 확인이 먼저 호출됨
        inOrder.verify(inventoryService).checkStock("P001", 2)

        // 2. 결제가 그 다음에 호출됨
        inOrder.verify(paymentService).processPayment(
            argThat { payment -> payment.amount == 20000L }
        )

        // 3. 재고 차감이 마지막에 호출됨
        inOrder.verify(inventoryService).decreaseStock("P001", 2)
    }
}
```

---

## 6. Spy 사용 시 주의사항

### 6.1 Kotlin의 final 클래스 문제

Kotlin의 클래스는 기본적으로 `final`이므로 Mockito가 Spy를 만들 수 없습니다.

```kotlin
// ❌ 잘못된 예시: final 클래스는 spy 불가
class MemberFacade { ... }

// ✅ 해결 방법 1: open 키워드 사용
open class MemberFacade { ... }

// ✅ 해결 방법 2: interface 사용 (더 권장)
interface MemberFacade { ... }
class MemberFacadeImpl : MemberFacade { ... }

// ✅ 해결 방법 3: all-open 플러그인 사용 (build.gradle.kts)
allOpen {
    annotation("org.springframework.stereotype.Service")
}
```

### 6.2 verify 호출 순서

```kotlin
// ❌ 잘못된 예시: 실제 메서드 호출 전에 verify
verify(memberFacade).joinMember(any())
memberFacade.joinMember(command)

// ✅ 올바른 예시: 실제 메서드 호출 후 verify
memberFacade.joinMember(command)
verify(memberFacade).joinMember(any())
```

### 6.3 any()와 실제 값 혼용 주의

```kotlin
// ❌ 잘못된 예시: any()와 실제 값을 섞어서 사용
verify(memberFacade).chargePoint("user1", any())

// ✅ 올바른 예시 1: 모두 matcher 사용
verify(memberFacade).chargePoint(eq("user1"), any())

// ✅ 올바른 예시 2: 모두 실제 값 사용
verify(memberFacade).chargePoint("user1", 1000L)
```

---

## 7. Mock vs Spy 선택 가이드

| 상황 | 선택 |
|------|------|
| 단위 테스트에서 의존성 격리 | Mock |
| 통합 테스트에서 실제 동작 + 호출 검증 | **Spy** |
| 외부 API 호출 방지 | Mock |
| 실제 비즈니스 로직 실행 필요 | **Spy** |
| 빠른 테스트 실행 속도 필요 | Mock |
| 전체 플로우 검증 필요 | **Spy** |

---

## 8. 핵심 정리

### Spy의 특징
✅ **실제 동작 수행** - 진짜 비즈니스 로직 실행
✅ **메서드 호출 추적** - 언제, 몇 번, 어떤 파라미터로 호출되었는지 검증
✅ **통합 테스트에 적합** - 여러 컴포넌트 간 상호작용 검증
✅ **부분 stubbing 가능** - 필요한 메서드만 stubbing하고 나머지는 실제 동작

### 주요 검증 메서드
```kotlin
verify(spy).method()                    // 1번 호출 검증
verify(spy, times(n)).method()          // n번 호출 검증
verify(spy, never()).method()           // 호출되지 않음 검증
verify(spy, atLeastOnce()).method()     // 최소 1번 이상 검증
verify(spy, atMost(n)).method()         // 최대 n번 이하 검증
inOrder(spy1, spy2).verify()            // 호출 순서 검증
```

### 언제 사용하나?
- **통합 테스트**에서 실제 동작을 수행하면서
- 특정 메서드가 **올바르게 호출되었는지 확인**할 때
- 여러 컴포넌트 간 **상호작용을 검증**할 때

Spy를 활용하면 **실제 동작의 정확성과 메서드 호출의 추적성**을 동시에 확보할 수 있습니다!
