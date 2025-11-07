# Spring Boot Kotlin 프로젝트의 통합 테스트와 E2E 테스트

## 목차
1. [테스트의 종류와 차이점](#1-테스트의-종류와-차이점)
2. [통합 테스트 (Integration Test)](#2-통합-테스트-integration-test)
3. [E2E 테스트 (End-to-End Test)](#3-e2e-테스트-end-to-end-test)
4. [테스트 유틸리티 구현](#4-테스트-유틸리티-구현)
5. [테스트 작성 시 주의사항](#5-테스트-작성-시-주의사항)

---

## 1. 테스트의 종류와 차이점

### 테스트 피라미드
```
       /\
      /  \     E2E 테스트 (가장 느림, 가장 넓은 범위)
     /----\
    /      \   통합 테스트 (중간 속도, 중간 범위)
   /--------\
  /          \ 단위 테스트 (가장 빠름, 가장 좁은 범위)
 /------------\
```

### 통합 테스트 vs E2E 테스트

| 구분 | 통합 테스트 | E2E 테스트 |
|------|------------|-----------|
| **테스트 범위** | 여러 컴포넌트 간 상호작용 (Service, Repository 등) | HTTP API를 통한 전체 플로우 |
| **Spring Context** | 필요한 빈만 로드 가능 | 전체 애플리케이션 컨텍스트 로드 |
| **Web Layer** | 제외 (컨트롤러 제외) | 포함 (컨트롤러 포함) |
| **속도** | 상대적으로 빠름 | 상대적으로 느림 |
| **목적** | 비즈니스 로직 검증 | 사용자 시나리오 검증 |

---

## 2. 통합 테스트 (Integration Test)

### 2.1 통합 테스트란?

통합 테스트는 **애플리케이션의 여러 계층(Layer)이 함께 올바르게 작동하는지 검증**하는 테스트입니다. 주로 Service Layer와 Repository Layer 간의 상호작용을 테스트합니다.

### 2.2 통합 테스트 구성

#### 필수 어노테이션
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

**주요 어노테이션 설명:**
- `@SpringBootTest`: Spring Boot 애플리케이션의 전체 컨텍스트를 로드
- `@MockitoSpyBean`: 실제 빈을 Spy로 감싸서 메서드 호출 검증 가능
- `@AfterEach`: 각 테스트 메서드 실행 후 데이터베이스를 초기화

### 2.3 통합 테스트 예시

#### 예시 1: 회원 가입 테스트
```kotlin
@DisplayName("회원 가입 시 Member 저장이 수행된다")
@Test
fun saveMemberOnJoin() {
    // Given
    val command = JoinMemberCommand("user1", "test@email.com", "1990-05-15", "MALE")

    // When
    memberFacade.joinMember(command)

    // Then
    verify(memberFacade).joinMember(any())
}
```
**테스트 포인트:**
- 실제 비즈니스 로직이 실행되는지 확인
- `@MockitoSpyBean`을 활용하여 메서드 호출 검증

---

#### 예시 2: 중복 회원 ID 검증
```kotlin
@DisplayName("이미 가입된 ID로 회원가입 시도 시 실패한다")
@Test
fun failToJoinWithDuplicateMemberId() {
    // Given: 기존 회원 저장
    val memberId = "testUser1"
    val member = Member(
        MemberId(memberId),
        Email("test@gmail.com"),
        BirthDate.from("1990-05-15"),
        Gender.MALE
    )
    memberJpaRepository.save(member)

    // When: 동일한 ID로 회원가입 시도
    val command2 = JoinMemberCommand(memberId, "test2@example.com", "1995-08-11", "FEMALE")

    // Then: 예외 발생 검증
    assertThrows<DuplicateMemberIdException> {
        memberFacade.joinMember(command2)
    }
}
```
**테스트 포인트:**
- Repository에 직접 데이터를 저장하여 테스트 환경 구성
- 비즈니스 규칙(중복 ID 방지) 검증

---

#### 예시 3: 회원 정보 조회 테스트
```kotlin
@DisplayName("해당 ID의 회원이 존재할 경우, 회원 정보가 반환된다")
@Test
fun getMemberInfoWhenExists() {
    // Given: 테스트 회원 저장
    val memberId = "testUser1"
    val member = Member(
        MemberId(memberId),
        Email("test@gmail.com"),
        BirthDate.from("1990-05-15"),
        Gender.MALE
    )
    memberJpaRepository.save(member)

    // When: 회원 조회
    val memberInfo = memberFacade.getMemberByMemberId(memberId)

    // Then: 결과 검증
    assertThat(memberInfo).isNotNull
    assertThat(memberInfo?.memberId).isEqualTo(memberId)
}
```

---

#### 예시 4: 포인트 충전 실패 테스트
```kotlin
@DisplayName("포인트 충전 시 해당 ID의 회원이 존재하지 않을 경우, 실패한다")
@Test
fun failToChargePointWhenMemberNotExists() {
    // When & Then: 존재하지 않는 회원의 포인트 충전 시도
    assertThrows<CoreException> {
        memberFacade.chargePoint("noUser1", 1000L)
    }
}
```

### 2.4 통합 테스트의 장점
- 실제 데이터베이스와 상호작용하여 **현실적인 테스트** 수행
- 여러 계층 간의 **통합 시나리오 검증**
- 트랜잭션, JPA 동작 등 **프레임워크 레벨의 동작 검증**

---

## 3. E2E 테스트 (End-to-End Test)

### 3.1 E2E 테스트란?

E2E 테스트는 **사용자 관점에서 HTTP API를 직접 호출하여 전체 플로우를 검증**하는 테스트입니다. 실제 사용자가 API를 호출하는 것과 동일한 환경에서 테스트합니다.

### 3.2 E2E 테스트 구성

#### 필수 어노테이션
```kotlin
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class MemberV1ApiE2ETest @Autowired constructor(
    private val testRestTemplate: TestRestTemplate,
    private val memberJpaRepository: MemberJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp,
) {
    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }
}
```

**주요 설정 설명:**
- `webEnvironment = RANDOM_PORT`: 랜덤 포트로 실제 웹 서버를 구동
- `TestRestTemplate`: HTTP 요청을 보내기 위한 테스트용 클라이언트
- 데이터베이스 초기화를 통한 **테스트 격리성** 보장

### 3.3 E2E 테스트 예시

#### 예시 1: 회원 가입 API 테스트 (성공 케이스)
```kotlin
@DisplayName("POST /api/v1/users/join - 회원 가입")
@Nested
inner class Join {
    @DisplayName("회원 가입이 성공할 경우, 생성된 유저 정보를 응답으로 반환한다")
    @Test
    fun successfulJoin() {
        // Given: 회원 가입 요청 데이터
        val request = JoinMemberRequest(
            "testUser1",
            "test@gmail.com",
            "1990-05-15",
            "MALE"
        )

        // When: POST /api/v1/users/join 호출
        val responseType = object : ParameterizedTypeReference<ApiResponse<MemberV1Dto.MemberResponse>>() {}
        val response = testRestTemplate.exchange(
            "/api/v1/users/join",
            HttpMethod.POST,
            HttpEntity(request),
            responseType
        )

        // Then: 응답 검증
        assertAll(
            { assertThat(response.statusCode).isEqualTo(HttpStatus.OK) },
            { assertThat(response.body?.data?.memberId).isEqualTo("testUser1") },
            { assertThat(response.body?.data?.email).isEqualTo("test@gmail.com") },
            { assertThat(response.body?.data?.gender).isEqualTo("MALE") },
        )
    }
}
```

**테스트 포인트:**
- HTTP 요청/응답 전체 흐름 검증
- 상태 코드, 응답 바디 구조 및 데이터 검증
- `ParameterizedTypeReference`를 사용한 제네릭 타입 안전성

---

#### 예시 2: 회원 가입 API 테스트 (실패 케이스)
```kotlin
@DisplayName("회원 가입 시에 성별이 없을 경우, 400 Bad Request 응답을 반환한다")
@Test
fun failWithoutGender() {
    // Given: 성별이 누락된 요청 데이터
    val request = mapOf(
        "memberId" to "testUser1",
        "email" to "test@gmail.com",
        "birthDate" to "1990-05-15"
        // gender 없음
    )

    // When: POST /api/v1/users/join 호출
    val response = testRestTemplate.postForEntity(
        "/api/v1/users/join",
        request,
        String::class.java
    )

    // Then: 400 Bad Request 검증
    assertThat(response.statusCode).isEqualTo(HttpStatus.BAD_REQUEST)
}
```

**테스트 포인트:**
- 요청 검증(Validation) 테스트
- 잘못된 요청에 대한 적절한 에러 응답 검증

---

#### 예시 3: 회원 정보 조회 API 테스트
```kotlin
@DisplayName("GET /api/v1/users/{memberId} - 회원 정보 조회")
@Nested
inner class GetMemberByMemberId {
    @DisplayName("내 정보 조회에 성공할 경우, 해당하는 유저 정보를 응답으로 반환한다")
    @Test
    fun successfulGetByMemberId() {
        // Given: 테스트 회원 데이터 저장
        val member = Member(
            MemberId("testUser1"),
            Email("test@gmail.com"),
            BirthDate.from("1990-05-15"),
            Gender.MALE
        )
        memberJpaRepository.save(member)

        // When: GET /api/v1/users/testUser1 호출
        val responseType = object : ParameterizedTypeReference<ApiResponse<MemberV1Dto.MemberResponse>>() {}
        val response = testRestTemplate.exchange(
            "/api/v1/users/testUser1",
            HttpMethod.GET,
            null,
            responseType
        )

        // Then: 응답 검증
        assertAll(
            { assertThat(response.statusCode).isEqualTo(HttpStatus.OK) },
            { assertThat(response.body?.data?.memberId).isEqualTo("testUser1") },
            { assertThat(response.body?.data?.email).isEqualTo("test@gmail.com") },
            { assertThat(response.body?.data?.gender).isEqualTo("MALE") },
        )
    }

    @DisplayName("존재하지 않는 ID로 조회할 경우, 404 Not Found 응답을 반환한다")
    @Test
    fun failWithNonexistentMemberId() {
        // When: 존재하지 않는 회원 조회
        val responseType = object : ParameterizedTypeReference<ApiResponse<MemberV1Dto.MemberResponse>>() {}
        val response = testRestTemplate.exchange(
            "/api/v1/users/noUser1",
            HttpMethod.GET,
            null,
            responseType
        )

        // Then: 404 Not Found 검증
        assertThat(response.statusCode).isEqualTo(HttpStatus.NOT_FOUND)
    }
}
```

---

#### 예시 4: 포인트 조회 API 테스트 (헤더 포함)
```kotlin
@DisplayName("GET /api/v1/points")
@Nested
inner class GetPoint {
    @DisplayName("포인트 조회에 성공할 경우, 보유 포인트를 응답으로 반환한다.")
    @Test
    fun successfulGetPoint() {
        // Given: 포인트를 보유한 회원 저장
        val memberId = MemberId("testUser1")
        val member = Member(
            memberId,
            Email("test@gmail.com"),
            BirthDate.from("1990-05-15"),
            Gender.MALE
        )
        member.chargePoint(1000L)
        memberJpaRepository.save(member)

        // When: GET /api/v1/points 호출 (X-USER-ID 헤더 포함)
        val headers = HttpHeaders().apply {
            set("X-USER-ID", memberId.value)
        }

        val responseType = object : ParameterizedTypeReference<ApiResponse<PointV1Dto.PointResponse>>() {}
        val response = testRestTemplate.exchange(
            "/api/v1/points",
            HttpMethod.GET,
            HttpEntity<Any>(headers),
            responseType
        )

        // Then: 응답 검증
        assertThat(response.statusCode).isEqualTo(HttpStatus.OK)
        assertThat(response.body?.data?.point).isEqualTo(1000L)
    }

    @DisplayName("X-USER-ID 헤더가 없을 경우, 400 Bad Request 응답을 반환한다.")
    @Test
    fun failWithoutXUserIdHeader() {
        // When: 헤더 없이 요청
        val response = testRestTemplate.exchange(
            "/api/v1/points",
            HttpMethod.GET,
            null,
            String::class.java
        )

        // Then: 400 Bad Request 검증
        assertThat(response.statusCode).isEqualTo(HttpStatus.BAD_REQUEST)
    }
}
```

**테스트 포인트:**
- 커스텀 헤더(`X-USER-ID`) 검증
- 필수 헤더 누락 시 에러 처리 검증

---

#### 예시 5: 포인트 충전 API 테스트
```kotlin
@DisplayName("POST /api/v1/points/charge")
@Nested
inner class ChargePoint {
    @DisplayName("존재하는 유저가 1000원을 충전할 경우, 충전된 보유 총량을 응답으로 반환한다.")
    @Test
    fun successfulChargePoint() {
        // Given: 회원 저장 및 요청 데이터 준비
        val memberId = MemberId("testUser1")
        val member = Member(
            memberId,
            Email("test@gmail.com"),
            BirthDate.from("1990-05-15"),
            Gender.MALE
        )
        memberJpaRepository.save(member)

        val request = PointV1Dto.ChargePointRequest(1000L)
        val headers = HttpHeaders().apply {
            set("X-USER-ID", memberId.value)
        }

        // When: POST /api/v1/points/charge 호출
        val responseType = object : ParameterizedTypeReference<ApiResponse<PointV1Dto.PointResponse>>() {}
        val response = testRestTemplate.exchange(
            "/api/v1/points/charge",
            HttpMethod.POST,
            HttpEntity(request, headers),
            responseType
        )

        // Then: 응답 검증
        assertThat(response.statusCode).isEqualTo(HttpStatus.OK)
        assertThat(response.body?.data?.point).isEqualTo(1000L)
    }

    @DisplayName("존재하지 않는 유저로 요청할 경우, 404 Not Found 응답을 반환한다")
    @Test
    fun failChargePointWithNonexistentMemberId() {
        // Given: 존재하지 않는 회원 ID로 요청
        val request = PointV1Dto.ChargePointRequest(1000L)
        val headers = HttpHeaders().apply {
            set("X-USER-ID", "noUser1")
        }

        // When: POST /api/v1/points/charge 호출
        val responseType = object : ParameterizedTypeReference<ApiResponse<PointV1Dto.PointResponse>>() {}
        val response = testRestTemplate.exchange(
            "/api/v1/points/charge",
            HttpMethod.POST,
            HttpEntity(request, headers),
            responseType
        )

        // Then: 404 Not Found 검증
        assertThat(response.statusCode).isEqualTo(HttpStatus.NOT_FOUND)
    }
}
```

### 3.4 E2E 테스트의 장점
- **실제 사용자 시나리오** 검증
- HTTP 요청/응답 전체 흐름 테스트
- 컨트롤러, 서비스, 리포지토리 **전 계층 통합 검증**
- API 명세와 실제 구현의 일치 여부 확인

---

## 4. 테스트 유틸리티 구현

### 4.1 DatabaseCleanUp 유틸리티

테스트 간 격리성을 보장하기 위해 각 테스트 후 데이터베이스를 초기화하는 유틸리티입니다.

```kotlin
@Component
class DatabaseCleanUp(
    @PersistenceContext private val entityManager: EntityManager,
) : InitializingBean {
    private val tableNames = mutableListOf<String>()

    // 애플리케이션 시작 시 모든 엔티티의 테이블명 수집
    override fun afterPropertiesSet() {
        entityManager.metamodel.entities
            .filter { entity -> entity.javaType.getAnnotation(Entity::class.java) != null }
            .map { entity -> entity.javaType.getAnnotation(Table::class.java).name }
            .forEach { tableNames.add(it) }
    }

    // 모든 테이블 TRUNCATE
    @Transactional
    fun truncateAllTables() {
        entityManager.flush()
        entityManager.createNativeQuery("SET FOREIGN_KEY_CHECKS = 0").executeUpdate()
        tableNames.forEach { table ->
            entityManager.createNativeQuery("TRUNCATE TABLE `$table`").executeUpdate()
        }
        entityManager.createNativeQuery("SET FOREIGN_KEY_CHECKS = 1").executeUpdate()
    }
}
```

**주요 기능:**
- `afterPropertiesSet()`: 스프링 빈 초기화 시 모든 엔티티 테이블명을 자동 수집
- `truncateAllTables()`: 외래 키 제약을 해제한 후 모든 테이블 TRUNCATE
- 각 테스트 후 `@AfterEach`에서 호출하여 **테스트 격리성** 보장

### 4.2 사용 방법

```kotlin
@SpringBootTest
class SomeIntegrationTest @Autowired constructor(
    private val databaseCleanUp: DatabaseCleanUp,
) {
    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }

    @Test
    fun someTest() {
        // 테스트 실행
    }
}
```

---

## 5. 테스트 작성 시 주의사항

### 5.1 테스트 격리성 (Test Isolation)
- 각 테스트는 **독립적**으로 실행되어야 함
- `@AfterEach`에서 데이터베이스 초기화 필수
- 테스트 순서에 의존하지 않도록 작성

### 5.2 Given-When-Then 패턴
```kotlin
@Test
fun exampleTest() {
    // Given: 테스트 준비 (데이터 세팅)
    val member = createMember()

    // When: 테스트 실행 (기능 수행)
    val result = memberService.getMember(member.id)

    // Then: 결과 검증 (assertion)
    assertThat(result).isNotNull()
}
```

### 5.3 테스트 네이밍 컨벤션
- **명확하고 구체적인** 테스트명 사용
- 테스트 의도를 **한눈에 파악** 가능하도록 작성
- `@DisplayName`을 활용한 한글 설명

```kotlin
// 좋은 예시
@DisplayName("회원 가입 시 이메일이 없으면 BadRequest를 반환한다")
@Test
fun failToJoinWithoutEmail() { ... }

// 나쁜 예시
@Test
fun test1() { ... }
```

### 5.4 @Nested를 활용한 테스트 그룹화
```kotlin
@DisplayName("POST /api/v1/users/join - 회원 가입")
@Nested
inner class Join {
    @Test
    fun successCase() { ... }

    @Test
    fun failCase() { ... }
}
```

### 5.5 assertAll을 활용한 다중 검증
```kotlin
assertAll(
    { assertThat(response.statusCode).isEqualTo(HttpStatus.OK) },
    { assertThat(response.body?.data?.memberId).isEqualTo("testUser1") },
    { assertThat(response.body?.data?.email).isEqualTo("test@gmail.com") },
)
```
- 모든 assertion을 실행하여 **실패한 항목 모두 확인** 가능
- 단일 assertion 실패 시에도 나머지 검증 계속 수행

### 5.6 테스트 데이터 준비
- **최소한의 데이터**만 준비
- 테스트와 **관련 없는 데이터는 제외**
- Repository를 직접 사용하여 테스트 환경 구성

---

## 6. 마치며

### 통합 테스트와 E2E 테스트의 적절한 활용

| 상황 | 추천 테스트 |
|------|------------|
| 비즈니스 로직 검증 | 통합 테스트 |
| API 명세 검증 | E2E 테스트 |
| 트랜잭션 동작 검증 | 통합 테스트 |
| HTTP 요청/응답 검증 | E2E 테스트 |
| 빠른 피드백 필요 | 통합 테스트 |
| 사용자 시나리오 검증 | E2E 테스트 |

### 테스트 작성의 이점
1. **버그 조기 발견**: 배포 전 문제 파악
2. **리팩토링 안정성**: 코드 변경 시 기존 동작 보장
3. **문서화 효과**: 테스트 코드 자체가 API 명세서 역할
4. **개발 생산성**: 수동 테스트 시간 단축

---

## 참고 자료
- [Spring Boot Testing Documentation](https://docs.spring.io/spring-boot/docs/current/reference/html/features.html#features.testing)
- [Kotlin Test Documentation](https://kotlinlang.org/docs/jvm-test-using-junit.html)
- [AssertJ Documentation](https://assertj.github.io/doc/)
