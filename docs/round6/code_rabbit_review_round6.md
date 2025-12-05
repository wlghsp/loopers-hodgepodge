@coderabbitai[bot] commented on this pull request.

Actionable comments posted: 16

Note

Due to the large number of review comments, Critical, Major severity comments were prioritized as inline comments.

🟡 Minor comments (6)
docker/02-init-data.sql-37-54 (1)
37-54: Off-by-one 오류: 99,999개의 상품만 생성됩니다.

Line 43의 WHERE seq < 100000은 1부터 99,999까지만 생성하여 의도한 10만개가 아닌 99,999개의 상품만 생성합니다.

다음과 같이 수정하세요:

 WITH RECURSIVE numbers AS (
     SELECT 1 AS seq
     UNION ALL
     SELECT seq + 1
     FROM numbers
-    WHERE seq < 100000
+    WHERE seq < 100001
 )
또는:

-    WHERE seq < 100000
+    WHERE seq <= 100000
docker/02-init-data.sql-19-32 (1)
19-32: Off-by-one 오류: 99개의 브랜드만 생성됩니다.

Line 25의 WHERE seq < 100은 1부터 99까지만 생성하여 99개의 브랜드만 생성합니다.

다음과 같이 수정하세요:

 WITH RECURSIVE numbers AS (
     SELECT 1 AS seq
     UNION ALL
     SELECT seq + 1
     FROM numbers
-    WHERE seq < 100
+    WHERE seq < 101
 )
또는:

-    WHERE seq < 100
+    WHERE seq <= 100
apps/commerce-api/src/main/kotlin/com/loopers/support/error/ErrorType.kt-35-43 (1)
35-43: PAYMENT_NOT_FOUND 메시지가 도메인과 일치하지 않습니다.

PAYMENT_NOT_FOUND의 메시지가 "쿠폰을 찾을 수 없습니다."로 되어 있어 결제 도메인과 맞지 않습니다. 사용자 혼란을 줄이기 위해 결제 기준 문구로 수정하는 것이 좋겠습니다.

-    PAYMENT_NOT_FOUND(HttpStatus.NOT_FOUND, "PAYMENT_001", "쿠폰을 찾을 수 없습니다."),
+    PAYMENT_NOT_FOUND(HttpStatus.NOT_FOUND, "PAYMENT_001", "결제를 찾을 수 없습니다."),
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentReconciliationScheduler.kt-33-37 (1)
33-37: 사용되지 않는 coroutineScope 필드

coroutineScope가 정의되어 있지만 실제로 사용되지 않습니다. reconcileStaleOrders에서는 runBlocking 내에서 직접 async(Dispatchers.IO)를 호출하고 있습니다. 이 필드를 사용하거나 제거해야 합니다.

coroutineScope.async로 변경하거나 사용하지 않는 필드를 제거하세요:

-    // 코루틴 스코프 (애플리케이션 생명주기와 함께)
-    // SupervisorJob: 하나의 작업 실패가 다른 작업에 영향을 주지 않음
-    private val coroutineScope = CoroutineScope(
-        Dispatchers.IO + SupervisorJob()
-    )
또는 필드를 사용하도록 변경:

-                async(Dispatchers.IO) {
+                coroutineScope.async {
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentService.kt-38-38 (1)
38-38: cardType 변환 시 예외 처리 누락

PgDto.CardTypeDto.valueOf(cardType)는 유효하지 않은 cardType 값에 대해 IllegalArgumentException을 발생시킵니다. 이 예외는 Circuit Breaker의 fallback을 트리거하여 의도치 않은 결제 실패 기록이 생성될 수 있습니다.

+        val cardTypeDto = try {
+            PgDto.CardTypeDto.valueOf(cardType)
+        } catch (e: IllegalArgumentException) {
+            throw CoreException(ErrorType.BAD_REQUEST, "지원하지 않는 카드 타입입니다: $cardType")
+        }
+
         val pgRequest = PgDto.PaymentRequest(
             orderId = "ORDER${order.id.toString().padStart(6, '0')}",
-            cardType = PgDto.CardTypeDto.valueOf(cardType),
+            cardType = cardTypeDto,
apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/payment/PaymentApi.kt-54-56 (1)
54-56: orderId 파라미터 null 처리가 필요합니다.

required = false로 선언되어 있지만 타입이 String(non-nullable)입니다. 요청 시 orderId가 없으면 예외가 발생하거나, 빈 문자열로 처리될 수 있습니다. 필수 파라미터라면 required = true로 변경하고, 선택적이라면 String?으로 변경 후 null 처리를 추가하세요.

-    @RequestParam("orderId", required = false) orderId: String,
+    @RequestParam("orderId") orderId: String,
🧹 Nitpick comments (34)
http/pg-simulator/payments.http (1)
1-20: LGTM! API 테스트 문서가 잘 작성되었습니다.

PG 시뮬레이터의 세 가지 주요 엔드포인트에 대한 예제가 명확하게 제공되어 있습니다.

선택사항: 파일 마지막에 개행 문자를 추가하는 것이 일반적인 관례입니다.

 ### 주문에 엮인 결제 정보 조회
 GET {{pg-simulator}}/api/v1/payments?orderId=1351039135
 X-USER-ID: 135135
+
apps/pg-simulator/src/main/kotlin/com/loopers/support/error/ErrorType.kt (1)
5-10: 에러 코드 필드의 의미를 더 명확히 하는 것을 고민해볼 여지가 있습니다

현재 code에 HttpStatus.X.reasonPhrase(예: "Bad Request")를 그대로 사용하고 있어, 클라이언트 입장에서는 사람이 읽기 좋은 메시지인지, 기계가 해석하는 안정적인 에러 코드인지 구분이 모호할 수 있습니다.
장기적으로는 아래처럼 역할을 분리하는 것도 고려해볼 만합니다.

code: "BAD_REQUEST", "INTERNAL_ERROR" 혹은 "PG-XXXX" 같은 기계 친화적인 고정 코드
message: 지금처럼 한글 사용자 메시지
필요하다면 status.reasonPhrase는 별도 필드로 두거나, 지금처럼 서버 내부에서만 사용
또 commerce-api 쪽 ErrorType와 이름/의미를 맞춰두면 모듈 간 에러 처리 정책을 이해하기가 더 쉬워질 것 같습니다.

apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/PaymentTest.kt (1)
12-116: Payment 도메인 상태 전이 테스트 구성이 잘 되어 있습니다

정상 플로우(카드 결제 생성, 실패 결제 생성, PENDING→SUCCESS/FAILED 전이)와
비정상 플로우(PENDING이 아닌 상태에서 전이 시 INVALID_PAYMENT_STATUS 예외)
까지 핵심 시나리오를 잘 커버하고 있어서, 도메인 로직 리팩터링 시 회귀 방지에 도움이 될 것 같습니다.

다만, 추후 테스트가 더 늘어날 경우에는 아래 정도만 고려해 두시면 좋겠습니다.

Payment.createCardPayment(...) 패턴이 여러 테스트에서 반복되므로 공통 픽스처/팩토리 메서드로 뽑아내면 중복이 줄어듭니다.
PaymentStatus.TIMEOUT, CANCELED까지 도메인에서 의미를 갖는다면, 해당 상태 전이에 대한 테스트도 추가되면 더 완전한 커버리지가 됩니다.
현재 PR 범위에서는 그대로 두셔도 무방해 보입니다.

apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/ApiResponse.kt (1)
3-31: API 응답 래퍼 설계는 일관적이며, 약간의 확장 여지만 있습니다

meta(result, errorCode, message) + data 구조로 성공/실패를 명확히 구분한 점 좋습니다.
success()(파라미터 없음)과 success(data: T? = null) 오버로드 조합도,
빈 바디 성공: ApiResponse.success()
타입 있는 성공: ApiResponse.success(dto)
로 자연스럽게 사용할 수 있어 보입니다.
확장 관점에서, 에러 응답에도 payload를 싣고 싶어질 수 있으니 아래 정도는 추후에 고려해볼 수 있습니다.

fun <T> fail(errorCode: String, errorMessage: String, data: T? = null): ApiResponse<T?> 형태로 일반화
혹은 errorDetails 같은 별도 DTO를 두고 data는 항상 도메인 데이터만 싣도록 규칙화
지금 단계에서는 현재 설계만으로도 충분히 실용적이라고 판단됩니다.

apps/commerce-api/build.gradle.kts (1)
18-23: OpenFeign/Resilience4j 의존성 추가 방향은 적절하지만 버전 관리 방식은 정리해 두는 것이 좋겠습니다

OpenFeign, Resilience4j, AOP 스타터를 commerce-api에 추가한 선택 자체는 PG 연동/회복력 관점에서 타당해 보입니다. 다만:

현재는 각 의존성 버전이 하드코딩되어 있어, 추후 Spring Boot/Cloud 버전 업 시 호환성 관리가 번거로울 수 있습니다.
일반적으로는
**Spring Cloud BOM(spring-cloud-dependencies)**을 dependencyManagement에 선언해서 OpenFeign 버전을 거기서 가져오거나,
Gradle 버전 카탈로그/공통 extra 속성으로 버전을 한 곳에서 관리
하는 패턴이 유지보수에 유리합니다.
또한, 사용 중인 Spring Boot 버전과 위 라이브러리 버전 조합이 공식적으로 호환되는지 한 번만 문서/릴리스 노트로 확인해 두시는 것을 권장드립니다.

apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/TransactionStatus.kt (1)
3-7: PG 쪽 TransactionStatus 정의는 적절하나, 상위 도메인 PaymentStatus와의 매핑을 명시해 두면 좋겠습니다

PG 시뮬레이터에서 PENDING/SUCCESS/FAILED만 가지는 단순한 상태를 쓰는 것은 이해하기 쉽습니다. 다만 commerce-api 쪽 PaymentStatus에는 TIMEOUT, CANCELED 등이 추가로 존재하므로:

PG 응답의 TransactionStatus가 상위 도메인 PaymentStatus로 어떻게 변환되는지
(예: FAILED ↔︎ FAILED/TIMEOUT/CANCELED 중 어떤 것으로 매핑되는지),
그 매핑 규칙을 한 곳(예: Mapper/Service)에서 명시적으로 관리
해 두면 향후 상태가 추가되거나 해석 규칙이 바뀔 때 혼선을 줄일 수 있습니다. 지금 enum 정의 자체는 그대로 두셔도 무방해 보입니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderRepository.kt (1)
12-12: 페이지네이션 지원을 고려해보세요.

findByMemberId는 Pageable을 사용하여 페이지네이션을 지원하지만, 이 메서드는 List<Order>를 반환합니다. 특정 상태와 생성 시간 조건으로 조회할 때 결과가 많을 경우 메모리 및 성능 문제가 발생할 수 있습니다.

다음과 같이 페이지네이션을 추가하는 것을 권장합니다:

-    fun findByStatusAndCreatedAtBefore(status: OrderStatus, time: ZonedDateTime): List<Order>
+    fun findByStatusAndCreatedAtBefore(status: OrderStatus, time: ZonedDateTime, pageable: Pageable): Page<Order>
apps/pg-simulator/src/main/kotlin/com/loopers/config/web/WebMvcConfig.kt (1)
10-11: ArgumentResolver를 빈으로 정의하는 것을 권장합니다.

UserInfoArgumentResolver를 직접 인스턴스화하고 있습니다. 만약 이 resolver가 추후 의존성을 필요로 하게 된다면 수정이 필요합니다.

다음과 같이 빈으로 정의하여 의존성 주입이 가능하도록 하는 것을 권장합니다:

 @Configuration
 class WebMvcConfig : WebMvcConfigurer {
+    @Bean
+    fun userInfoArgumentResolver(): UserInfoArgumentResolver {
+        return UserInfoArgumentResolver()
+    }
+
-    override fun addArgumentResolvers(resolvers: MutableList<HandlerMethodArgumentResolver?>) {
-        resolvers.add(UserInfoArgumentResolver())
+    override fun addArgumentResolvers(resolvers: MutableList<HandlerMethodArgumentResolver?>) {
+        resolvers.add(userInfoArgumentResolver())
     }
 }
apps/commerce-api/src/main/kotlin/com/loopers/config/FeignConfig.kt (1)
1-8: Feign 클라이언트 설정이 적절합니다.

Spring Cloud OpenFeign을 활성화하는 표준적인 구성입니다. basePackages로 전체 프로젝트 범위를 지정했는데, 만약 Feign 클라이언트가 특정 패키지에만 있다면 좁은 범위로 제한하는 것도 고려해볼 수 있습니다.

필요시 더 구체적인 패키지로 범위를 좁힐 수 있습니다:

@EnableFeignClients(basePackages = ["com.loopers.infrastructure.pg"])
apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/CardNumberTest.kt (1)
1-42: 카드번호 마스킹 및 검증 테스트 구성이 명확합니다.

다양한 길이/포맷에 대한 마스킹 결과와 toString()까지 함께 검증하고, 빈 값·공백·너무 짧은 번호에 대한 예외 메시지와 ErrorType까지 체크하는 구조가 좋아 보입니다. 필요하다면 숫자/구분자 혼합의 경계 케이스(예: " 1234 " 등)도 추가해 두면 회귀 테스트에 더 도움이 될 것 같습니다.

apps/commerce-api/src/main/resources/application.yml (1)
32-69: PG 및 회로차단기 설정은 합리해 보이지만 환경·로그 전략을 한 번 더 점검해 주세요.

pg.base-url이 기본값으로 http://localhost:8082로 잡혀 있어, 실제 배포 환경에서는 프로필별 설정이나 외부 설정으로 반드시 덮어쓰는지 확인해 두는 편이 안전합니다.
com.loopers.infrastructure.pg.PgSimulatorClient 로그 레벨을 전체 프로필에서 DEBUG로 두면 PG 요청/응답에 포함된 결제 관련 정보가 과도하게 남을 수 있습니다. 운영 프로필에서는 INFO 이상으로 올리거나, 민감 데이터가 로그에 포함되지 않도록 로거 설정을 한 번 더 점검해 보시는 걸 권장합니다.
resilience4j.circuitbreaker / timelimiter의 키 구조와 값들은 일반적인 설정 범위 안에 있어 보이며, 실제 트래픽 패턴을 보면서 임계치(예: failure-rate-threshold, slow-call-*)를 미세 조정하면 더 안정적인 동작을 기대할 수 있습니다.
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/order/OrderJpaRepository.kt (1)
4-12: 주문 상태·생성일 기준 조회 메서드 추가가 자연스럽습니다.

findByStatusAndCreatedAtBefore 시그니처가 JPA 파생 쿼리 규칙에 맞고, 오래된 특정 상태 주문을 배치 처리하는 데 유용해 보입니다. 해당 조건(status, created_at)에 대한 인덱스를 DB 측에 잡아 두면 배치/조회 부하가 커졌을 때도 안정적으로 동작할 수 있습니다.

apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/PaymentEventPublisher.kt (1)
1-6: PaymentEventPublisher가 결제 이벤트 흐름을 명확히 표현합니다.

PaymentCreated와 PaymentHandled 각각에 대한 publish 메서드를 분리해 둬서 구현체에서 이벤트별 처리를 명시적으로 구현하기 좋습니다. 이후 이벤트 타입이 늘어나면 공통 부모 타입(PaymentEvent) 하나를 받는 오버로드를 추가하는 방향도 확장성 측면에서 고려해 볼 수 있습니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/CardNumber.kt (1)
14-29: 카드 번호 검증·마스킹 로직은 안전하게 잘 구성됨

공백/빈 값, 최소 길이(4자리 미만) 체크 후 예외 처리하는 부분과,
길이 4 이하는 전체 마스킹("****"), 그 이상은 마지막 4자리만 노출하는 방식 모두 일반적인 요구사항에 잘 맞습니다.
length = 20 컬럼 제약과도 (최대 19자리 카드번호 기준) 잘 호환됩니다.
다만 추후 실제 입력값에 공백·하이픈이 포함될 수 있다면, from 내부에서 숫자만 남기도록 전처리(예: filter { it.isDigit() })를 해 두면 도메인 계층에서 한 번 더 안전망을 치는 효과가 있을 것 같습니다.

apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/payment/PaymentCallbackController.kt (1)
11-21: 콜백 처리 엔드포인트 구현은 단순·명확하며, Bean Validation 연동 여지 있음

/api/v1/payments/callback을 PaymentCallbackService.handlePaymentCallback에 바로 위임하는 구조라 컨트롤러는 얇고 역할이 분리되어 있어 좋습니다.
만약 PaymentCallbackDto에 Bean Validation 애노테이션을 사용 중이라면, 파라미터에 @Valid를 추가해 자동 검증을 거치도록 하면 서비스 단에서의 수동 검증 코드를 줄일 수 있습니다.
apps/pg-simulator/src/main/resources/application.yml (1)
27-30: 환경별 데이터베이스 설정 권장

현재 메인 설정에 localhost:3306이 하드코딩되어 있습니다. 개발, QA, 프로덕션 환경에서 다른 데이터베이스 호스트를 사용하는 경우 프로파일별로 jdbc-url을 오버라이드하는 것이 좋습니다.

예시:

# dev 프로파일에서
---
spring:
  config:
    activate:
      on-profile: dev

datasource:
  mysql-jpa:
    main:
      jdbc-url: jdbc:mysql://dev-db-host:3306/paymentgateway
http/commerce-api/test-data-setup.http (1)
46-48: GET 요청에 불필요한 Content-Type 헤더

GET 요청은 일반적으로 요청 본문(body)을 포함하지 않으므로 Content-Type 헤더가 필요하지 않습니다. 이는 53-54번, 59-60번 라인에도 동일하게 적용됩니다.

 GET {{baseUrl}}/api/v1/points
 X-USER-ID: {{userId}}
-Content-Type: application/json
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackDto.kt (1)
23-23: 하드코딩된 상태 값 비교

status == "SUCCESS" 비교에서 문자열 리터럴을 직접 사용하고 있습니다. 타입 안전성을 높이고 오타를 방지하기 위해 enum이나 상수를 사용하는 것이 좋습니다.

enum class PaymentCallbackStatus(val value: String) {
    SUCCESS("SUCCESS"),
    FAILED("FAILED"),
    // ... other statuses
}

data class PaymentCallbackDto(
    val transactionKey: String,
    val status: String,
    val reason: String?
) {
    // ...
    fun isSuccess(): Boolean = status == PaymentCallbackStatus.SUCCESS.value
}
또는 status 필드의 타입을 직접 enum으로 변경하는 방안도 고려할 수 있습니다.

http/commerce-api/order-card-payment.http (1)
104-105: GET 요청에 불필요한 Content-Type 헤더

GET 요청은 요청 본문을 포함하지 않으므로 Content-Type 헤더가 필요하지 않습니다.

 GET {{baseUrl}}/api/v1/orders/1
-Content-Type: application/json

 ### ...

 GET {{baseUrl}}/api/v1/orders?page=0&size=20
 X-USER-ID: {{userId}}
-Content-Type: application/json
Also applies to: 110-112

apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/PaymentCallbackDtoTest.kt (1)
55-67: 테스트 코드는 잘 작성되었으나, DTO 설계를 재검토하세요.

테스트 자체는 잘 작성되었습니다. 다만 isSuccess()와 isFailed() 같은 헬퍼 메서드가 DTO에 있는 것은 이 코드베이스의 아키텍처 원칙(DTO는 순수 데이터 컨테이너)과 맞지 않을 수 있습니다. 이러한 비즈니스 로직은 도메인 레이어로 이동하는 것을 고려하세요.

학습된 내용에 따르면: DTO는 순수 데이터 컨테이너여야 하며, init 블록의 검증은 허용되지만 비즈니스 로직 메서드는 도메인 엔티티에 위치해야 합니다.

apps/commerce-api/src/main/kotlin/com/loopers/application/order/OrderFacade.kt (1)
18-21: FQN 대신 import 사용 권장

com.loopers.interfaces.api.order.OrderV1Dto.CreateOrderRequest를 전체 경로로 참조하고 있습니다. 가독성을 위해 상단에 import 문을 추가하는 것이 좋습니다.

 package com.loopers.application.order
 
 import com.loopers.domain.order.OrderService
+import com.loopers.interfaces.api.order.OrderV1Dto
 import org.springframework.data.domain.Page
 import org.springframework.data.domain.Pageable
 import org.springframework.stereotype.Component
     fun createOrder(
         memberId: String,
-        request: com.loopers.interfaces.api.order.OrderV1Dto.CreateOrderRequest
+        request: OrderV1Dto.CreateOrderRequest
     ): OrderInfo {
apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/event/payment/PaymentEventListener.kt (1)
14-21: Thread.sleep 대신 비동기 지연 방식 고려

@Async 컨텍스트에서 Thread.sleep을 사용하면 스레드 풀의 스레드가 블로킹됩니다. 시뮬레이션 목적이라면 문서화하거나, 프로덕션 환경에서는 비동기 방식(예: ScheduledExecutorService 또는 CompletableFuture.delayedExecutor)을 고려해 주세요.

+    // 시뮬레이션 목적: PG 처리 지연을 모방하기 위한 랜덤 대기 시간
     @Async
     @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
     fun handle(event: PaymentEvent.PaymentCreated) {
         val thresholdMillis = (1000L..5000L).random()
         Thread.sleep(thresholdMillis)
 
         paymentApplicationService.handle(event.transactionKey)
     }
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/pg/PgDto.kt (2)
3-3: 사용되지 않는 import

ApiResponse가 import되어 있지만 이 파일에서 사용되지 않습니다.

 package com.loopers.infrastructure.pg
 
-import com.loopers.interfaces.api.ApiResponse
-
 object PgDto {
21-29: status 필드 타입 불일치

PaymentStatusResponse의 status가 String 타입인 반면, PaymentResponse는 TransactionStatusDto enum을 사용합니다. 일관성을 위해 PaymentStatusResponse.status도 enum 타입으로 변경하는 것을 고려해 주세요.

     data class PaymentStatusResponse(
         val transactionKey: String,
         val orderId: String,
         val cardType: CardTypeDto,
         val cardNo: String,
         val amount: Long,
-        val status: String,
+        val status: TransactionStatusDto,
         val reason: String?
     )
apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderService.kt (2)
23-23: import 스타일 개선 필요

완전한 패키지 경로 대신 파일 상단에 import 문을 추가하는 것이 좋습니다.

+import com.loopers.domain.payment.PaymentService
 ...
-    private val paymentService: com.loopers.domain.payment.PaymentService,
+    private val paymentService: PaymentService,
136-142: 동일 트랜잭션 내 중복 save 호출

@Transactional 메서드 내에서 orderRepository.save(order)가 이미 Line 45에서 호출되었고, 롤백 시 Line 141에서 다시 호출됩니다. JPA의 dirty checking으로 인해 트랜잭션 커밋 시 자동으로 변경사항이 반영되므로, 롤백 시 추가 save 호출은 불필요합니다.

     private fun rollbackPaymentFailure(order: Order, usePoint: Long, member: Member) {
         if (usePoint > 0) {
             member.chargePoint(usePoint)
         }
         order.fail()
-        orderRepository.save(order)
     }
apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/payment/PaymentApi.kt (1)
28-29: Thread.sleep()은 요청 스레드를 차단합니다.

시뮬레이터 용도라면 의도된 동작일 수 있지만, Thread.sleep()은 요청 스레드를 차단하여 동시 요청 처리 성능에 영향을 줍니다. 향후 개선 시 비동기 처리(예: delay() + Coroutine 또는 CompletableFuture.delayedExecutor)를 고려해 보세요.

apps/pg-simulator/src/main/kotlin/com/loopers/infrastructure/payment/PaymentCoreRepository.kt (1)
28-31: @Transactional(readOnly = true) 어노테이션 누락 및 정렬 위치 검토 필요.

다른 조회 메서드들과 달리 findByOrderId에는 @Transactional(readOnly = true) 어노테이션이 없습니다. 또한 sortedByDescending은 메모리 내 정렬로, 데이터가 많아지면 성능에 영향을 줄 수 있습니다. JPA 레포지토리에서 ORDER BY updated_at DESC로 정렬하는 것이 더 효율적입니다.

+    @Transactional(readOnly = true)
     override fun findByOrderId(userId: String, orderId: String): List<Payment> {
-        return paymentJpaRepository.findByUserIdAndOrderId(userId, orderId)
-            .sortedByDescending { it.updatedAt }
+        return paymentJpaRepository.findByUserIdAndOrderIdOrderByUpdatedAtDesc(userId, orderId)
     }
apps/pg-simulator/src/main/kotlin/com/loopers/application/payment/PaymentApplicationService.kt (1)
83-87: notifyTransactionResult에 @Transactional(readOnly = true) 어노테이션 추가를 권장합니다.

데이터베이스에서 조회하는 메서드이지만 트랜잭션 어노테이션이 없습니다. 일관성 있는 트랜잭션 경계 설정을 위해 추가하세요.

+    @Transactional(readOnly = true)
     fun notifyTransactionResult(transactionKey: String) {
         val payment = paymentRepository.findByTransactionKey(transactionKey)
             ?: throw CoreException(ErrorType.NOT_FOUND, "(transactionKey: $transactionKey) 결제건이 존재하지 않습니다.")
         paymentRelay.notify(callbackUrl = payment.callbackUrl, transactionInfo = TransactionInfo.from(payment))
     }
apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/payment/PaymentDto.kt (2)
24-37: DTO 내 유효성 검증 로직 위치 검토가 필요합니다.

프로젝트 학습 내용에 따르면, DTO는 순수 데이터 컨테이너로 유지하고 유효성 검증 로직은 도메인 엔티티에 배치해야 합니다. 현재 validate() 메서드가 DTO에 있는데, 이를 PaymentCommand.CreateTransaction이나 도메인 레이어로 이동하는 것을 고려하세요. Based on learnings.

21-21: 콜백 URL 프리픽스가 하드코딩되어 있습니다.

http://localhost:8080이 하드코딩되어 있어 다른 환경에서는 유효성 검증이 실패할 수 있습니다. 시뮬레이터 전용이라면 주석으로 명시하고, 여러 환경을 지원해야 한다면 설정 값으로 외부화하세요.

apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/ApiControllerAdvice.kt (3)
17-20: 불필요한 import 문을 제거하세요.

joinToString, isNotEmpty, toRegex와 같은 Kotlin 표준 라이브러리 함수들은 자동으로 import되거나 확장 함수로 사용 가능합니다. 명시적인 import가 필요하지 않습니다.

다음 diff를 적용하여 불필요한 import를 제거하세요:

-import kotlin.collections.joinToString
-import kotlin.jvm.java
-import kotlin.text.isNotEmpty
-import kotlin.text.toRegex
89-92: 중첩 함수를 companion object로 추출하는 것을 고려하세요.

extractMissingParameter 함수가 중첩 함수로 정의되어 있습니다. 재사용성과 테스트 가능성을 위해 companion object의 private 함수로 추출하는 것을 고려해보세요.

다음과 같이 리팩토링할 수 있습니다:

+    companion object {
+        private fun extractMissingParameter(message: String): String {
+            val regex = "'(.+?)'".toRegex()
+            return regex.find(message)?.groupValues?.get(1) ?: ""
+        }
+    }
+
     @ExceptionHandler
     fun handleBadRequest(e: ServerWebInputException): ResponseEntity<ApiResponse<*>> {
-        fun extractMissingParameter(message: String): String {
-            val regex = "'(.+?)'".toRegex()
-            return regex.find(message)?.groupValues?.get(1) ?: ""
-        }
-
         val missingParams = extractMissingParameter(e.reason ?: "")
96-96: 오류 메시지의 따옴표 스타일을 일관되게 유지하세요.

96번째 줄에서 이스케이프된 작은따옴표(\')를 사용하고 있는데, 다른 오류 메시지들(37, 45, 68번째 줄 등)에서는 일반 작은따옴표(')를 사용하고 있습니다. 일관성을 위해 동일한 스타일을 사용하는 것이 좋습니다.

다음 diff를 적용하여 일관된 스타일을 유지하세요:

-            failureResponse(errorType = ErrorType.BAD_REQUEST, errorMessage = "필수 요청 값 \'$missingParams\'가 누락되었습니다.")
+            failureResponse(errorType = ErrorType.BAD_REQUEST, errorMessage = "필수 요청 값 '$missingParams'가 누락되었습니다.")
📜 Review details
Configuration used: CodeRabbit UI

Review profile: CHILL

Plan: Pro

📥 Commits
Reviewing files that changed from the base of the PR and between ec17ea1 and 36cd10e.

📒 Files selected for processing (76)
apps/commerce-api/build.gradle.kts (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/CommerceApiApplication.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/application/order/OrderFacade.kt (2 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/application/order/OrderInfo.kt (2 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/config/FeignConfig.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderRepository.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderService.kt (2 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/CardNumber.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/Payment.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackDto.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackService.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentMethod.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentReconciliationScheduler.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentRepository.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentService.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentStatus.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/strategy/PgStrategy.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/strategy/SimulatorPgStrategy.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/product/ProductService.kt (2 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/domain/shared/Email.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/order/OrderJpaRepository.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/order/OrderRepositoryImpl.kt (2 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/payment/PaymentJpaRepository.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/payment/PaymentRecoveryScheduler.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/payment/PaymentRepositoryImpl.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/pg/PgClientConfig.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/pg/PgDto.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/pg/PgSimulatorClient.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/order/OrderV1ApiSpec.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/order/OrderV1Controller.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/order/OrderV1Dto.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/payment/PaymentCallbackController.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/support/error/ErrorType.kt (1 hunks)
apps/commerce-api/src/main/resources/application.yml (1 hunks)
apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/CardNumberTest.kt (1 hunks)
apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/PaymentCallbackDtoTest.kt (1 hunks)
apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/PaymentTest.kt (1 hunks)
apps/pg-simulator/README.md (1 hunks)
apps/pg-simulator/build.gradle.kts (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/PaymentGatewayApplication.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/application/payment/OrderInfo.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/application/payment/PaymentApplicationService.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/application/payment/PaymentCommand.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/application/payment/TransactionInfo.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/config/web/WebMvcConfig.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/CardType.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/Payment.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/PaymentEvent.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/PaymentEventPublisher.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/PaymentRelay.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/PaymentRepository.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/TransactionKeyGenerator.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/TransactionStatus.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/domain/user/UserInfo.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/infrastructure/payment/PaymentCoreEventPublisher.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/infrastructure/payment/PaymentCoreRelay.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/infrastructure/payment/PaymentCoreRepository.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/infrastructure/payment/PaymentJpaRepository.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/ApiControllerAdvice.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/ApiResponse.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/argumentresolver/UserInfoArgumentResolver.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/payment/PaymentApi.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/payment/PaymentDto.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/event/payment/PaymentEventListener.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/support/error/CoreException.kt (1 hunks)
apps/pg-simulator/src/main/kotlin/com/loopers/support/error/ErrorType.kt (1 hunks)
apps/pg-simulator/src/main/resources/application.yml (1 hunks)
docker/01-schema.sql (1 hunks)
docker/02-init-data.sql (1 hunks)
http/commerce-api/commerce-api.http (1 hunks)
http/commerce-api/monitoring.http (1 hunks)
http/commerce-api/order-card-payment.http (1 hunks)
http/commerce-api/test-data-setup.http (1 hunks)
http/http-client.env.json (1 hunks)
http/pg-simulator/payments.http (1 hunks)
settings.gradle.kts (1 hunks)
🧰 Additional context used 🧠 Learnings (3) 📚 Learning: 2025-11-15T10:10:44.689Z
Learnt from: ghojeong
Repo: Loopers-dev-lab/loopers-spring-kotlin-template PR: 25
File: apps/commerce-api/src/main/kotlin/com/loopers/application/user/UserRegisterRequest.kt:6-11
Timestamp: 2025-11-15T10:10:44.689Z
Learning: In this Kotlin Spring project, DTOs (data transfer objects) should remain pure data containers without validation annotations or any logic. All validation logic, including format checks and business rules, must be placed in domain entities (typically in init blocks using CoreException). Do not suggest adding Jakarta Validation annotations (NotBlank, Email, Past, etc.) to DTO classes.
Applied to files:

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackDto.kt
apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/payment/PaymentDto.kt
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/pg/PgDto.kt
apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/PaymentCallbackDtoTest.kt
apps/commerce-api/src/main/kotlin/com/loopers/domain/shared/Email.kt
apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/order/OrderV1Dto.kt
📚 Learning: 2025-11-09T10:41:39.297Z
Learnt from: ghojeong
Repo: Loopers-dev-lab/loopers-spring-kotlin-template PR: 25
File: apps/commerce-api/src/main/kotlin/com/loopers/domain/product/ProductRepository.kt:1-12
Timestamp: 2025-11-09T10:41:39.297Z
Learning: In this codebase, domain repository interfaces are allowed to use Spring Data's org.springframework.data.domain.Page and org.springframework.data.domain.Pageable types. This is an accepted architectural decision and should not be flagged as a DIP violation.
Applied to files:

apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderRepository.kt
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/order/OrderRepositoryImpl.kt
apps/commerce-api/src/main/kotlin/com/loopers/domain/product/ProductService.kt
apps/pg-simulator/src/main/kotlin/com/loopers/infrastructure/payment/PaymentJpaRepository.kt
apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/PaymentRepository.kt
apps/commerce-api/src/main/kotlin/com/loopers/application/order/OrderFacade.kt
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/payment/PaymentJpaRepository.kt
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentRepository.kt
📚 Learning: 2025-11-27T22:53:56.762Z
Learnt from: CR
Repo: Loopers-dev-lab/loopers-spring-kotlin-template PR: 0
File: .codeguide/loopers-1-week.md:0-0
Timestamp: 2025-11-27T22:53:56.762Z
Learning: Applies to **/*.{test,spec}.{ts,tsx,js} : Integration test: If a user with the given ID exists, their point balance should be returned.
Applied to files:

http/commerce-api/test-data-setup.http
🔇 Additional comments (63)
apps/pg-simulator/build.gradle.kts (4)
1-3: JPA 플러그인 구성이 올바르게 적용됨.

Kotlin JPA 플러그인이 적절하게 추가되었으며, 엔티티 클래스의 no-arg 생성자 요구사항을 충족합니다.

7-11: Module and support dependencies verification required.

Internal project module dependencies have been added. Confirmation is needed that these modules actually exist and that there are no circular dependencies:

modules/jpa
modules/redis
supports/jackson
supports/logging
supports/monitoring
Verify the modules are defined in the project structure and contain build.gradle.kts files. Additionally, ensure no module depends back on apps/pg-simulator or creates any circular dependency chains.

14-16: Verify springDocOpenApiVersion property is defined.

The springdoc-openapi dependency references ${project.properties["springDocOpenApiVersion"]}, which must be defined in gradle.properties or build.gradle.kts. If this property is missing, the build will fail.

18-23: Verify QueryDSL and test fixtures configuration.

The setup references querydsl-apt::jakarta and uses testFixtures() from jpa and redis modules. Before proceeding, confirm:

Test fixtures support: Verify that modules/jpa and modules/redis have the java-test-fixtures plugin applied in their build.gradle.kts files
Jakarta compatibility: Ensure the Jakarta variant of querydsl-apt matches your project's JPA version (verify in project root build.gradle.kts or settings)
Kotlin KAPT plugin: Confirm that kotlin-kapt plugin is applied in this build file or inherited from a parent configuration
settings.gradle.kts (1)
6-6: LGTM! 새로운 PG 시뮬레이터 모듈 추가가 적절합니다.

모듈 구조와 네이밍이 기존 패턴을 따르고 있습니다.

apps/pg-simulator/src/main/kotlin/com/loopers/infrastructure/payment/PaymentJpaRepository.kt (1)
6-9: AI 요약과 실제 코드 간 불일치가 있습니다.

AI 요약에는 findByTransactionKey(transactionKey: String)와 findByOrderId(orderId: Long)로 명시되어 있지만, 실제 구현은 findByUserIdAndTransactionKey와 findByUserIdAndOrderId로 userId를 포함하고 있으며, orderId 타입도 String입니다. 실제 구현이 사용자별 데이터 격리 측면에서 더 안전합니다.

apps/commerce-api/src/main/kotlin/com/loopers/CommerceApiApplication.kt (1)
7-7: LGTM! 스케줄링 기능 활성화가 적절합니다.

PR에서 추가되는 결제 정산 및 복구 스케줄러를 위한 기반 설정입니다.

Also applies to: 12-12

docker/02-init-data.sql (1)
56-85: LGTM! 테스트 데이터 초기화 스크립트가 잘 구성되었습니다.

재귀 CTE를 사용한 대량 데이터 생성 전략과 문자셋 설정이 적절합니다. 회원, 쿠폰, 멤버 쿠폰 데이터도 테스트에 유용한 구성입니다.

apps/pg-simulator/README.md (1)
1-42: LGTM! PG 시뮬레이터 문서가 명확하게 작성되었습니다.

모듈의 목적, 실행 방법, 포트 설정, API 예제가 잘 정리되어 있어 다른 개발자들이 쉽게 사용할 수 있습니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/shared/Email.kt (1)
20-24: LGTM! EMAIL_PATTERN을 companion object로 리팩토링한 것이 적절합니다.

정규식 Pattern을 클래스 레벨로 이동하여 메모리 효율성을 개선했으며, Kotlin의 관용적 패턴을 따르고 있습니다. 모든 Email 인스턴스가 하나의 Pattern 객체를 공유하게 됩니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/product/ProductService.kt (1)
34-48: Verify Product.decreaseStock() exception handling and edge case handling

Cannot verify the concerns raised in this review comment. The referenced file path and related product domain classes could not be located in the repository. Please confirm the correct file paths and ensure the code is present before review can proceed.

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentStatus.kt (1)
3-18: 결제 상태 enum 및 헬퍼 메서드 구현은 현재 요구사항에 잘 맞습니다

description 필드와 isPending/isSuccess 등 상태 체크용 헬퍼 메서드 구성이 직관적이고, 도메인 코드에서 가독성을 높이는 데 도움이 됩니다. 별도 로직이 없는 단순 비교이기 때문에 유지보수 부담도 크지 않아 보입니다.

http/http-client.env.json (1)
2-4: 로컬 HTTP 클라이언트 환경에 pg-simulator 엔드포인트 추가 적절

commerce-api(8080)와 pg-simulator(8082)를 분리해 둔 구성은 직관적이고, 로컬에서 두 애플리케이션을 함께 띄우기에도 무리 없어 보입니다.

단, .http 스크립트에서 참조하는 변수명이 "pg-simulator"와 동일한지 한 번만 맞춰보시면(예: {{pg-simulator}}) 오타로 인한 요청 실패를 예방할 수 있습니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentMethod.kt (1)
3-8: 결제 수단 enum 정의가 단순하고 명확합니다

POINT, CARD 두 값에 대해 한글 description을 들고 있게 한 구조가 직관적이고, 이후 UI/응답 DTO로 변환할 때도 재사용하기 좋아 보입니다. 도메인에서 비교 시에는 enum 값 자체(PaymentMethod.CARD)를 기준으로 사용하면 의미도 분명해집니다.

http/commerce-api/commerce-api.http (1)
1-50: 잘 구성된 테스트 파일입니다!

API 테스트를 위한 HTTP 요청들이 잘 정리되어 있으며, 변수를 활용하여 재사용성이 좋습니다.

apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/CardType.kt (1)
1-7: 깔끔한 enum 정의입니다!

카드 타입을 명확하게 정의했으며, trailing comma 사용도 Kotlin 컨벤션을 따르고 있습니다.

http/commerce-api/monitoring.http (1)
1-31: 모니터링 엔드포인트가 잘 정리되어 있습니다!

액추에이터 엔드포인트를 테스트하기 위한 HTTP 요청들이 명확하게 문서화되어 있으며, 설정 관련 주석도 유용합니다.

apps/pg-simulator/src/main/kotlin/com/loopers/application/payment/OrderInfo.kt (1)
1-14: 명확하게 문서화된 데이터 클래스입니다!

KDoc 주석이 상세하게 작성되어 있고, 구조도 명확합니다. 주문에 대한 여러 트랜잭션을 잘 표현하고 있습니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentRepository.kt (1)
1-7: 결제 리포지토리 인터페이스 시그니처가 단순하고 도메인 친화적입니다.

transactionKey는 단일 결제, orderId는 다수 결제를 반환하도록 분리되어 있어 사용처에서 의도가 명확합니다. findByTransactionKey가 nullable인 점만 호출부에서 안전하게 처리해 주면 될 것 같습니다.

apps/pg-simulator/src/main/kotlin/com/loopers/domain/user/UserInfo.kt (1)
1-8: UserInfo 값 객체 정의가 목적에 잘 맞습니다.

userId만을 담는 얇은 data class로 HTTP 헤더 등에서 내려온 사용자 식별자를 도메인 오브젝트로 감싸는 패턴이 명확합니다. 추후 필요해지면 userId 형식 검증이나 추가 메타데이터를 이 타입에 확장하는 것도 수월해 보입니다.

apps/pg-simulator/src/main/kotlin/com/loopers/support/error/CoreException.kt (1)
1-6: CoreException이 ErrorType 기반 예외 표현을 잘 캡슐화합니다.

errorType과 선택적인 customMessage를 노출하면서, 실제 예외 메시지는 customMessage ?: errorType.message로 일관되게 구성되어 있어 API 레이어에서 기본 메시지와 커스텀 메시지를 모두 활용하기 좋습니다.

apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/order/OrderRepositoryImpl.kt (1)
37-42: 상태·생성일 조건 조회 메서드 위임 구현 적절

findByStatusAndCreatedAtBefore가 JPA 리포지토리에 그대로 위임되고 있어서, 도메인 인터페이스와 인프라 구현이 잘 정합을 맞추고 있습니다. 추가적인 비즈니스 로직이 없는 단순 조회 메서드로는 이 정도 구현이면 충분해 보입니다.

apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/payment/PaymentRepositoryImpl.kt (1)
7-21: 도메인 리포지토리 구현이 심플하게 잘 위임됨

PaymentRepositoryImpl이 JPA 리포지토리로만 깔끔하게 위임하고 있어서, 인프라 계층 역할이 명확하고 테스트/향후 확장에도 유리해 보입니다. 현재 요구사항 기준으로는 이대로 충분합니다.

apps/pg-simulator/src/main/kotlin/com/loopers/infrastructure/payment/PaymentCoreEventPublisher.kt (1)
8-18: 도메인 이벤트 → Spring 이벤트 어댑터 구현이 간결하고 명확함

PaymentEventPublisher를 ApplicationEventPublisher에 단순 위임하는 어댑터로 잘 분리되어 있어서, 이후 인프라 변경(예: 메시지 브로커 도입) 시에도 도메인 코드를 건드리지 않고 교체하기 좋겠습니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/CardNumber.kt (1)
8-12: Verify JPA compatibility with private constructor on @embeddable data class

The private constructor on @Embeddable may prevent JPA/Hibernate from instantiating the class during entity loading, depending on your no-arg compiler plugin configuration. Confirm that:

The no-arg plugin is properly configured to generate a no-arg constructor for @Embeddable classes, OR
An explicit protected no-arg constructor is added for JPA, OR
Integration tests confirm entity loading/saving works in production scenarios
If using the no-arg plugin without explicit configuration, verify it includes @Embeddable in its annotation list.

apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/pg/PgClientConfig.kt (1)
11-22: Feign Logger.Level.FULL 사용 시 카드 정보 로그 노출 위험

PG 연동용 Feign 클라이언트에서 Logger.Level.FULL을 공용 빈으로 설정하면, 요청/응답 바디 전체가 로그에 남을 수 있습니다. 결제 요청 바디에 카드 번호 등 민감정보가 포함될 가능성이 높기 때문에, 운영 환경에서는 상당히 위험한 설정입니다.

권장 사항:

기본은 BASIC 또는 NONE으로 두고, 로컬/개발 프로파일에서만 FULL을 켜거나,
커스텀 Logger를 도입해 카드 번호 등 민감 필드를 마스킹한 후 출력하거나,
최소한 프로파일별로 다른 feignLoggerLevel 빈을 구성해 운영에서는 본 설정이 적용되지 않도록 분리
하는 방안을 고려해 주세요.

apps/commerce-api/src/main/kotlin/com/loopers/application/order/OrderInfo.kt (1)
13-14: LGTM!

할인 금액과 최종 금액 필드가 깔끔하게 추가되었고, 도메인 객체로부터의 매핑도 일관된 패턴을 따르고 있습니다.

Also applies to: 25-26

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackDto.kt (1)
11-21: DTO 검증 로직 위치에 대한 검토 필요

학습된 코딩 가이드에 따르면, 이 코드베이스에서는 DTO가 순수한 데이터 컨테이너로 유지되어야 하며 모든 검증 로직은 도메인 엔티티에 위치해야 합니다. 그러나 PaymentCallbackDto는 클래스명에 "Dto" 접미사가 붙어있으면서도 init 블록에 검증 로직을 포함하고 있습니다.

현재 domain.payment 패키지에 위치하고 CoreException을 사용한 검증 패턴을 따르고 있어 의도적인 설계일 수 있으나, 명명 규칙과 아키텍처 일관성 측면에서 검토가 필요합니다.

Based on learnings, DTOs should be pure data containers in this codebase.

다음 중 하나를 고려해보세요:

도메인 엔티티로 취급한다면 클래스명을 PaymentCallback으로 변경
DTO로 유지한다면 검증 로직을 별도의 도메인 서비스나 엔티티로 이동
apps/pg-simulator/src/main/kotlin/com/loopers/application/payment/TransactionInfo.kt (1)
18-39: 구조가 깔끔하고 명확합니다.

데이터 클래스와 팩토리 메서드의 구현이 적절하며, Payment 도메인 엔티티를 TransactionInfo로 변환하는 매핑이 명확합니다.

apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/order/OrderV1ApiSpec.kt (1)
9-48: 잘 문서화된 API 명세입니다.

Swagger 어노테이션을 활용한 API 문서화가 명확하고 상세합니다. 특히 주문 생성 API의 설명에서 포인트 전액 결제와 카드 결제 시나리오를 잘 설명하고 있습니다.

apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/PaymentRepository.kt (1)
7-7: 메서드 시그니처가 호출 코드와 일치하지 않을 수 있습니다.

findByOrderId 메서드가 두 개의 매개변수(userId: String, orderId: String)를 요구하지만, PaymentRecoveryScheduler.kt에서 단일 매개변수로 호출될 수 있습니다. 이는 컴파일 오류를 발생시킬 수 있습니다. 또한 주문 ID 타입(String vs Long)의 일관성을 확인하세요.

apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/argumentresolver/UserInfoArgumentResolver.kt (1)
21-31: 깔끔한 구현입니다.

Argument resolver 구현이 적절하며, 헤더가 없을 때 명확한 오류 메시지를 제공합니다. UserInfo 생성자에서 userId 형식 검증이 이루어지는지 확인하는 것을 권장합니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/strategy/PgStrategy.kt (1)
6-16: Verify userId parameter usage consistency across PgStrategy implementations.

The interface follows the strategy pattern well for PG integration. However, verify that the userId parameter is consistently and appropriately used across all implementations of this interface, as it appears in every method signature.

apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/PaymentEvent.kt (1)
3-28: LGTM!

이벤트 클래스 구조가 깔끔합니다. PaymentCreated와 PaymentHandled를 object PaymentEvent 내에 중첩하여 네임스페이스를 명확히 하고, from() 팩토리 메서드로 도메인 객체에서 이벤트로의 변환을 캡슐화한 것이 좋습니다.

apps/commerce-api/src/main/kotlin/com/loopers/application/order/OrderFacade.kt (1)
34-48: LGTM!

getOrder와 getOrders 메서드가 잘 구현되었습니다. Pageable 사용은 이 코드베이스의 아키텍처 결정에 따라 허용됩니다. Based on learnings, domain repository interfaces are allowed to use Spring Data's Page and Pageable types.

apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/order/OrderV1Dto.kt (2)
6-13: LGTM!

DTO가 순수 데이터 컨테이너로 유지되어 있고 검증 로직이 없습니다. Based on learnings, 이 프로젝트에서는 DTO에 validation 어노테이션을 추가하지 않고 도메인 엔티티에서 검증을 처리합니다.

25-49: Verify createdAt type compatibility between OrderInfo and OrderResponse

Confirm whether OrderInfo.createdAt is a String type. If it's LocalDateTime or another type, serialization or explicit conversion will be needed before assigning it to the String field in OrderResponse.

apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/event/payment/PaymentEventListener.kt (1)
23-27: LGTM!

PaymentHandled 이벤트 핸들러가 깔끔하게 구현되어 있습니다. AFTER_COMMIT 페이즈에서 비동기로 결제 결과를 알리는 것이 적절합니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentReconciliationScheduler.kt (1)
149-157: LGTM!

@PreDestroy를 사용한 코루틴 스코프 정리가 적절합니다. 애플리케이션 종료 시 진행 중인 작업을 취소하여 리소스 누수를 방지합니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/strategy/SimulatorPgStrategy.kt (1)
24-28: Return type handling inconsistency between payment methods

The getPaymentStatus method returns PgDto.PaymentStatusResponse directly, but the review notes that requestPayment extracts .data from ApiResponse<PgDto.PaymentResponse>. Verify whether the underlying PgSimulatorClient methods have intentionally different return types or if the wrapper handling should be consistent between both methods.

apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/pg/PgSimulatorClient.kt (1)
18-34: API 응답 래핑 방식 불일치

requestPayment는 ApiResponse<T> 래퍼로 반환되는 반면, getPaymentStatus와 getPaymentsByOrderId는 DTO를 직접 반환합니다. 이러한 응답 형식의 불일치 원인을 확인하고, PG 서버의 실제 응답 구조가 엔드포인트마다 다른 것인지, 아니면 클라이언트 설계상 오류인지 판단이 필요합니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderService.kt (2)
100-104: 포인트 결제 완료 흐름 LGTM

포인트 전액 결제 시 재고 감소, 주문 완료, 외부 서비스 처리 순서가 적절합니다.

83-98: 포인트 차감 시점에 대한 트랜잭션 일관성 문제

member.usePoint(usePoint)가 호출된 후 이후 단계에서 예외가 발생하면 포인트가 차감된 상태로 남을 수 있습니다. 현재 rollbackPaymentFailure는 processCardPayment 내에서만 호출되므로, 다른 실패 시나리오(예: Line 45의 orderRepository.save 실패)에서는 포인트 롤백이 되지 않습니다.

포인트 차감을 결제 성공 이후로 이동하거나, 전체 흐름에 대한 롤백 로직을 보강하는 것을 고려해주세요.

⛔ Skipped due to learnings
Learnt from: ghojeong
Repo: Loopers-dev-lab/loopers-spring-kotlin-template PR: 48
File: apps/commerce-api/src/main/kotlin/com/loopers/application/order/OrderFacade.kt:80-83
Timestamp: 2025-11-30T15:44:28.336Z
Learning: User ghojeong prefers explicit state management over transaction rollback for handling payment failures in order creation flow. When payment fails after order creation, the order should be explicitly marked as cancelled and persisted, rather than relying on transaction rollback.
apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/order/OrderV1Controller.kt (3)
22-34: 주문 생성 엔드포인트 구조 LGTM

X-USER-ID 헤더를 통한 사용자 식별과 DTO 변환 패턴이 적절합니다.

36-47: 페이지네이션 조회 LGTM

기본값 설정(page=0, size=20)과 PageRequest 사용이 적절합니다.

49-57: 인가(Authorization) 검증 누락

getOrder 엔드포인트가 orderId만으로 주문을 조회하고 있어, 인증된 사용자가 다른 사용자의 주문을 조회할 수 있는 IDOR(Insecure Direct Object Reference) 취약점이 존재합니다.

X-USER-ID 헤더를 받아서 해당 주문이 요청자의 것인지 검증하거나, 서비스 레이어에서 권한 검증을 추가해주세요.

     @GetMapping("/{orderId}")
     override fun getOrder(
+        @RequestHeader("X-USER-ID") memberId: String,
         @PathVariable orderId: Long,
     ): ApiResponse<OrderV1Dto.OrderResponse> {
-        val orderInfo = orderFacade.getOrder(orderId)
+        val orderInfo = orderFacade.getOrder(orderId, memberId)

         return OrderV1Dto.OrderResponse.from(orderInfo)
             .let { ApiResponse.success(it) }
     }
⛔ Skipped due to learnings
Learnt from: ghojeong
Repo: Loopers-dev-lab/loopers-spring-kotlin-template PR: 25
File: apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/point/PointV1Controller.kt:20-20
Timestamp: 2025-11-15T10:13:57.949Z
Learning: Authentication and authorization issues should not be flagged in code reviews for this project. Security concerns related to user authentication, authorization, and identity verification (such as X-USER-ID header validation) are out of scope for review.
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackService.kt (1)
21-23: 멱등성 처리 LGTM

이미 처리된 결제(PENDING이 아닌 상태)에 대해 early return하여 중복 콜백 처리를 방지하는 것이 적절합니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentService.kt (2)
20-21: Circuit Breaker 패턴 적용 LGTM

외부 PG 시스템 호출에 Circuit Breaker를 적용하여 장애 전파를 방지하는 것이 적절합니다.

59-83: Fallback 구현 LGTM

실패 결제 기록을 저장한 후 예외를 던져 호출자에게 적절히 전파하는 패턴이 올바르게 구현되었습니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/Payment.kt (3)
61-74: 상태 전이 로직 LGTM

PENDING 상태에서만 상태 변경을 허용하는 검증 로직이 적절하게 구현되었습니다. 도메인 불변식을 잘 보호하고 있습니다.

95-107: createFailedPayment 팩토리 메서드 일관성 검토

createFailedPayment가 markAsFailed()를 호출하지 않고 status와 failureReason을 직접 설정합니다. 이는 초기 생성이므로 기능적으로는 문제없으나, paymentMethod가 기본값 POINT로 설정되는 것이 의도된 것인지 확인이 필요합니다.

15-24: JPA 엔티티 구조 LGTM

생성자 파라미터와 protected setter를 사용한 엔티티 설계가 Kotlin/JPA 베스트 프랙티스를 따르고 있습니다.

apps/pg-simulator/src/main/kotlin/com/loopers/domain/payment/Payment.kt (1)
17-21: 인덱스 구성 검토가 필요합니다.

transaction_key가 이미 @Id(PK)로 설정되어 있어 고유성이 보장됩니다. idx_unique_user_order_transaction의 고유 제약 조건이 비즈니스 요구사항에 맞는지 확인하세요. 동일 사용자/주문에 여러 결제 시도가 가능해야 한다면 이 제약이 문제가 될 수 있습니다.

apps/pg-simulator/src/main/kotlin/com/loopers/application/payment/PaymentApplicationService.kt (1)
69-81: 트랜잭션 커밋 전 이벤트 발행에 대한 주의가 필요합니다.

handle() 메서드에서 엔티티 상태 변경 후 같은 트랜잭션 내에서 이벤트를 발행합니다. 트랜잭션이 롤백되어도 이벤트는 이미 발행된 상태일 수 있습니다. 트랜잭션 커밋 후 이벤트 발행이 필요하다면 @TransactionalEventListener(phase = AFTER_COMMIT)를 고려하세요.

apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/payment/PaymentDto.kt (1)
101-135: LGTM!

CardTypeDto와 TransactionStatusResponse enum 매핑이 exhaustive when 표현식을 사용하여 컴파일 타임 안전성을 보장합니다. 새로운 enum 값이 추가되면 컴파일 에러로 누락을 방지할 수 있습니다.

apps/pg-simulator/src/main/kotlin/com/loopers/interfaces/api/ApiControllerAdvice.kt (8)
22-24: LGTM!

@RestControllerAdvice 어노테이션과 로거 설정이 올바르게 구성되어 있습니다.

26-30: LGTM!

CoreException 처리 로직이 올바릅니다. customMessage를 우선적으로 사용하여 로깅 및 응답을 구성하고 있습니다.

32-39: LGTM!

타입 불일치 예외 처리가 적절하며, null-safe 연산자를 사용하여 안전하게 처리하고 있습니다. 오류 메시지도 명확합니다.

41-47: LGTM!

필수 파라미터 누락 예외 처리가 명확하고 적절합니다.

102-105: LGTM!

NoResourceFoundException 처리가 적절합니다.

107-112: LGTM!

모든 예외를 포괄하는 fallback 핸들러가 적절하게 구현되어 있습니다. 에러 레벨로 로깅하고 INTERNAL_ERROR를 반환하는 것이 모범 사례입니다.

114-118: LGTM!

failureResponse 헬퍼 메서드가 깔끔하게 구현되어 있습니다. Elvis 연산자를 사용하여 errorMessage가 없을 경우 errorType.message로 fallback하는 로직이 적절합니다.

49-85: The enum constants access is already safe.

The code correctly checks isEnum before accessing enumConstants on line 58. According to Java/Kotlin specifications, Class.enumConstants is guaranteed to be non-null when Class.isEnum() returns true, so the guard condition is sufficient to prevent null pointer exceptions. No changes are needed here.

In apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderService.kt:

> +        try {
+            paymentService.requestCardPayment(
+                order = order,
+                userId = memberId,
+                cardType = cardType,
+                cardNo = cardNo,
+                amount = amount
+            )
+        } catch (e: CoreException) {
+            rollbackPaymentFailure(order, usePoint, member)
+            throw e
+        }
⚠️ Potential issue | 🟠 Major

CoreException 외의 예외 처리 누락

CoreException만 catch하므로 다른 런타임 예외(예: 네트워크 타임아웃, 예상치 못한 PG 응답 등)가 발생하면 롤백이 수행되지 않습니다.

-        } catch (e: CoreException) {
+        } catch (e: Exception) {
             rollbackPaymentFailure(order, usePoint, member)
-            throw e
+            throw if (e is CoreException) e else CoreException(
+                ErrorType.PAYMENT_UNAVAILABLE,
+                "결제 처리 중 오류가 발생했습니다: ${e.message}",
+                e
+            )
         }
📝 Committable suggestion
‼️ IMPORTANT
Carefully review the code before committing. Ensure that it accurately replaces the highlighted code, contains no missing lines, and has no issues with indentation. Thoroughly test & benchmark the code to ensure it meets the requirements.

⬇️ Suggested change
-        try {
-            paymentService.requestCardPayment(
-                order = order,
-                userId = memberId,
-                cardType = cardType,
-                cardNo = cardNo,
-                amount = amount
-            )
-        } catch (e: CoreException) {
-            rollbackPaymentFailure(order, usePoint, member)
-            throw e
-        }
+        try {
+            paymentService.requestCardPayment(
+                order = order,
+                userId = memberId,
+                cardType = cardType,
+                cardNo = cardNo,
+                amount = amount
+            )
+        } catch (e: Exception) {
+            rollbackPaymentFailure(order, usePoint, member)
+            throw if (e is CoreException) e else CoreException(
+                ErrorType.PAYMENT_UNAVAILABLE,
+                "결제 처리 중 오류가 발생했습니다: ${e.message}",
+                e
+            )
+        }
🤖 Prompt for AI Agents
In apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderService.kt
around lines 122 to 133, the code only catches CoreException so other runtime
exceptions (network timeouts, unexpected PG responses, etc.) won't trigger
rollback; add a broader catch (e.g., catch (e: Exception)) after the existing
CoreException catch to call rollbackPaymentFailure(order, usePoint, member) and
then rethrow the exception to ensure all failures perform rollback while
preserving original exception propagation.
In apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackService.kt:

> +        if (callback.isSuccess()) {
+            productService.decreaseStockByOrder(order)
+            payment.markAsSuccess()
+            order.complete()
+        }
⚠️ Potential issue | 🟠 Major

결제 실패 콜백 처리 누락

callback.isSuccess()가 false인 경우(결제 실패)에 대한 처리가 없습니다. 실패 콜백을 받아도 주문과 결제가 PENDING 상태로 무기한 유지됩니다.

         if (callback.isSuccess()) {
             productService.decreaseStockByOrder(order)
             payment.markAsSuccess()
             order.complete()
+        } else {
+            payment.markAsFailed(callback.message ?: "결제 실패")
+            order.fail()
         }
📝 Committable suggestion
‼️ IMPORTANT
Carefully review the code before committing. Ensure that it accurately replaces the highlighted code, contains no missing lines, and has no issues with indentation. Thoroughly test & benchmark the code to ensure it meets the requirements.

⬇️ Suggested change
-        if (callback.isSuccess()) {
-            productService.decreaseStockByOrder(order)
-            payment.markAsSuccess()
-            order.complete()
-        }
+        if (callback.isSuccess()) {
+            productService.decreaseStockByOrder(order)
+            payment.markAsSuccess()
+            order.complete()
+        } else {
+            payment.markAsFailed(callback.message ?: "결제 실패")
+            order.fail()
+        }
🤖 Prompt for AI Agents
In
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackService.kt
around lines 27 to 31, the code only handles callback.isSuccess() == true and
lacks a branch for payment failures, leaving order and payment stuck in PENDING;
add an else branch to handle failure by marking the payment as failed (e.g.
payment.markAsFailed()), updating the order to a failed/cancelled state (e.g.
order.fail() or order.cancel()), and ensure any reserved stock is released or
left unchanged as appropriate (call productService.releaseStockByOrder(order) if
you reserved stock earlier); also log the failure and include callback/reason
details to aid debugging.
In apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentReconciliationScheduler.kt:

> +    @Transactional
+    fun reconcileOrder(order: Order) {
⚠️ Potential issue | 🔴 Critical

코루틴 컨텍스트에서 @Transactional 주의

reconcileOrder에 @Transactional이 적용되어 있지만, 이 메서드는 async(Dispatchers.IO) 블록 내에서 호출됩니다. Spring의 트랜잭션 프록시는 스레드 로컬 기반이므로 코루틴에서 스레드가 전환되면 트랜잭션이 제대로 적용되지 않을 수 있습니다.

해결 방안:

@Transactional을 제거하고 각 리포지토리 호출에서 개별 트랜잭션 처리
또는 동기 호출로 변경 후 병렬 처리를 다른 방식으로 구현
또는 TransactionTemplate을 사용하여 명시적 트랜잭션 관리
#!/bin/bash
# 트랜잭션 관련 설정 확인
rg -n "TransactionTemplate|@EnableTransactionManagement" --type=kt
In apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentReconciliationScheduler.kt:

> +            when (pgStatus.status) {
+                "SUCCESS" -> {
+                    // 콜백 누락 케이스 → 수동 복구
+                    try {
+                        productService.decreaseStockByOrder(order)
+                        pendingPayment.markAsSuccess()
+                        order.complete()
+                        logger.info("Recovered payment: orderId=${order.id}, transactionKey=${pendingPayment.transactionKey}")
+                    } catch (e: Exception) {
+                        // 재고 부족 시 PG 취소 필요
+                        pendingPayment.markAsFailed("재고 부족: ${e.message}")
+                        order.fail()
+                        logger.error("Out of stock during reconciliation: orderId=${order.id}")
+                        // TODO: PG 취소 API 호출 및 CS 팀 알림
+                    }
+                }
+                "FAILED" -> {
+                    pendingPayment.markAsFailed(pgStatus.failureReason ?: "알 수 없는 오류")
+                    order.fail()
+                    logger.info("Payment failed during reconciliation: orderId=${order.id}")
+                }
+                else -> {
+                    // 아직 PENDING → 계속 대기
+                    logger.debug("Payment still pending: orderId=${order.id}")
+                }
+            }
⚠️ Potential issue | 🔴 Critical

pgStatus 필드명 불일치 가능성

Line 134에서 pgStatus.failureReason을 참조하지만, PgDto.PaymentStatusResponse에는 reason 필드만 존재합니다. 컴파일 에러가 발생할 수 있습니다.

                 "FAILED" -> {
-                    pendingPayment.markAsFailed(pgStatus.failureReason ?: "알 수 없는 오류")
+                    pendingPayment.markAsFailed(pgStatus.reason ?: "알 수 없는 오류")
                     order.fail()
                     logger.info("Payment failed during reconciliation: orderId=${order.id}")
                 }
📝 Committable suggestion
‼️ IMPORTANT
Carefully review the code before committing. Ensure that it accurately replaces the highlighted code, contains no missing lines, and has no issues with indentation. Thoroughly test & benchmark the code to ensure it meets the requirements.

⬇️ Suggested change
-            when (pgStatus.status) {
-                "SUCCESS" -> {
-                    // 콜백 누락 케이스 → 수동 복구
-                    try {
-                        productService.decreaseStockByOrder(order)
-                        pendingPayment.markAsSuccess()
-                        order.complete()
-                        logger.info("Recovered payment: orderId=${order.id}, transactionKey=${pendingPayment.transactionKey}")
-                    } catch (e: Exception) {
-                        // 재고 부족 시 PG 취소 필요
-                        pendingPayment.markAsFailed("재고 부족: ${e.message}")
-                        order.fail()
-                        logger.error("Out of stock during reconciliation: orderId=${order.id}")
-                        // TODO: PG 취소 API 호출 및 CS 팀 알림
-                    }
-                }
-                "FAILED" -> {
-                    pendingPayment.markAsFailed(pgStatus.failureReason ?: "알 수 없는 오류")
-                    order.fail()
-                    logger.info("Payment failed during reconciliation: orderId=${order.id}")
-                }
-                else -> {
-                    // 아직 PENDING → 계속 대기
-                    logger.debug("Payment still pending: orderId=${order.id}")
-                }
-            }
+            when (pgStatus.status) {
+                "SUCCESS" -> {
+                    // 콜백 누락 케이스 → 수동 복구
+                    try {
+                        productService.decreaseStockByOrder(order)
+                        pendingPayment.markAsSuccess()
+                        order.complete()
+                        logger.info("Recovered payment: orderId=${order.id}, transactionKey=${pendingPayment.transactionKey}")
+                    } catch (e: Exception) {
+                        // 재고 부족 시 PG 취소 필요
+                        pendingPayment.markAsFailed("재고 부족: ${e.message}")
+                        order.fail()
+                        logger.error("Out of stock during reconciliation: orderId=${order.id}")
+                        // TODO: PG 취소 API 호출 및 CS 팀 알림
+                    }
+                }
+                "FAILED" -> {
+                    pendingPayment.markAsFailed(pgStatus.reason ?: "알 수 없는 오류")
+                    order.fail()
+                    logger.info("Payment failed during reconciliation: orderId=${order.id}")
+                }
+                else -> {
+                    // 아직 PENDING → 계속 대기
+                    logger.debug("Payment still pending: orderId=${order.id}")
+                }
+            }
🤖 Prompt for AI Agents
In
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentReconciliationScheduler.kt
around lines 117 to 142, the code references pgStatus.failureReason which
doesn't exist on PgDto.PaymentStatusResponse (the field is named reason); update
references to use pgStatus.reason (with null-safe handling) or map the response
to a domain property before use—for exa