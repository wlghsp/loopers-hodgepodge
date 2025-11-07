# Spring Boot에서 @RestControllerAdvice를 활용한 전역 예외 처리

## 1. @RestControllerAdvice란?

`@RestControllerAdvice`는 **모든 컨트롤러에서 발생하는 예외를 한 곳에서 처리**할 수 있게 해주는 Spring의 기능입니다.

### 주요 장점
- 예외 처리 로직 중복 제거
- 일관된 에러 응답 형식 제공
- 컨트롤러 코드 간결화

---

## 2. 기본 구조

### 2.1 전역 예외 핸들러 클래스
```kotlin
@RestControllerAdvice
class ApiControllerAdvice {
    private val log = LoggerFactory.getLogger(ApiControllerAdvice::class.java)

    @ExceptionHandler
    fun handle(e: CoreException): ResponseEntity<ApiResponse<*>> {
        log.warn("CoreException : {}", e.customMessage ?: e.message, e)
        return failureResponse(errorType = e.errorType, errorMessage = e.customMessage)
    }
}
```

### 2.2 커스텀 예외 및 에러 타입
```kotlin
// 커스텀 예외
class CoreException(
    val errorType: ErrorType,
    val customMessage: String? = null,
) : RuntimeException(customMessage ?: errorType.message)

// 에러 타입 정의
enum class ErrorType(val status: HttpStatus, val code: String, val message: String) {
    INTERNAL_ERROR(HttpStatus.INTERNAL_SERVER_ERROR, "Internal Server Error", "일시적인 오류가 발생했습니다."),
    BAD_REQUEST(HttpStatus.BAD_REQUEST, "Bad Request", "잘못된 요청입니다."),
    NOT_FOUND(HttpStatus.NOT_FOUND, "Not Found", "존재하지 않는 요청입니다."),
    CONFLICT(HttpStatus.CONFLICT, "Conflict", "이미 존재하는 리소스입니다."),
}
```

### 2.3 API 응답 형식
```kotlin
data class ApiResponse<T>(
    val meta: Metadata,
    val data: T?,
) {
    data class Metadata(
        val result: Result,
        val errorCode: String?,
        val message: String?,
    ) {
        enum class Result { SUCCESS, FAIL }
    }
}
```

---

## 3. 다양한 예외 처리 예시

### 3.1 커스텀 예외 처리 (CoreException)
```kotlin
@ExceptionHandler
fun handle(e: CoreException): ResponseEntity<ApiResponse<*>> {
    log.warn("CoreException : {}", e.customMessage ?: e.message, e)
    return failureResponse(errorType = e.errorType, errorMessage = e.customMessage)
}
```
**사용 예시:**
```kotlin
throw CoreException(ErrorType.NOT_FOUND, "회원을 찾을 수 없습니다.")
```

---

### 3.2 Validation 에러 처리 (`@Valid`)
```kotlin
@ExceptionHandler
fun handleMethodArgumentNotValid(e: MethodArgumentNotValidException): ResponseEntity<ApiResponse<*>> {
    val fieldErrors = e.bindingResult.fieldErrors
    val errorMessage = fieldErrors.joinToString(", ") { error ->
        "${error.field}: ${error.defaultMessage}"
    }

    log.warn("Validation failed: {}", errorMessage)
    return failureResponse(
        errorType = ErrorType.BAD_REQUEST,
        errorMessage = errorMessage
    )
}
```
**응답 예시:**
```json
{
  "meta": {
    "result": "FAIL",
    "errorCode": "Bad Request",
    "message": "email: 이메일 형식이 올바르지 않습니다, age: 0 이상이어야 합니다"
  },
  "data": null
}
```

---

### 3.3 필수 헤더 누락 처리
```kotlin
@ExceptionHandler
fun handleMissingRequestHeader(e: MissingRequestHeaderException): ResponseEntity<ApiResponse<*>> {
    val errorMessage = e.message
    log.warn("MissingRequestHeaderException: {}", errorMessage)
    return failureResponse(
        errorType = ErrorType.BAD_REQUEST,
        errorMessage = errorMessage
    )
}
```
**발생 상황:** `@RequestHeader("X-USER-ID") userId: String` 헤더 누락

---

### 3.4 요청 파라미터 타입 불일치
```kotlin
@ExceptionHandler
fun handleBadRequest(e: MethodArgumentTypeMismatchException): ResponseEntity<ApiResponse<*>> {
    val name = e.name
    val type = e.requiredType?.simpleName ?: "unknown"
    val value = e.value ?: "null"
    val message = "요청 파라미터 '$name' (타입: $type)의 값 '$value'이(가) 잘못되었습니다."
    return failureResponse(errorType = ErrorType.BAD_REQUEST, errorMessage = message)
}
```
**발생 상황:** `/api/users?age=abc` (숫자 대신 문자열 전달)

---

### 3.5 필수 파라미터 누락
```kotlin
@ExceptionHandler
fun handleBadRequest(e: MissingServletRequestParameterException): ResponseEntity<ApiResponse<*>> {
    val name = e.parameterName
    val type = e.parameterType
    val message = "필수 요청 파라미터 '$name' (타입: $type)가 누락되었습니다."
    return failureResponse(errorType = ErrorType.BAD_REQUEST, errorMessage = message)
}
```

---

### 3.6 JSON 파싱 에러 처리 (핵심!)

이 부분이 **가장 실무적이고 복잡한 예외 처리**입니다.

```kotlin
@ExceptionHandler
fun handleBadRequest(e: HttpMessageNotReadableException): ResponseEntity<ApiResponse<*>> {
    val errorMessage = when (val rootCause = e.rootCause) {
        // 1️⃣ Enum 타입 불일치
        is InvalidFormatException -> {
            val fieldName = rootCause.path.joinToString(".") { it.fieldName ?: "?" }

            val valueIndicationMessage = when {
                rootCause.targetType.isEnum -> {
                    val enumClass = rootCause.targetType
                    val enumValues = enumClass.enumConstants.joinToString(", ") { it.toString() }
                    "사용 가능한 값 : [$enumValues]"
                }
                else -> ""
            }

            val expectedType = rootCause.targetType.simpleName
            val value = rootCause.value

            "필드 '$fieldName'의 값 '$value'이(가) 예상 타입($expectedType)과 일치하지 않습니다. $valueIndicationMessage"
        }

        // 2️⃣ 필수 필드 누락
        is MismatchedInputException -> {
            val fieldPath = rootCause.path.joinToString(".") { it.fieldName ?: "?" }
            "필수 필드 '$fieldPath'이(가) 누락되었습니다."
        }

        // 3️⃣ JSON 매핑 오류
        is JsonMappingException -> {
            val fieldPath = rootCause.path.joinToString(".") { it.fieldName ?: "?" }
            "필드 '$fieldPath'에서 JSON 매핑 오류가 발생했습니다: ${rootCause.originalMessage}"
        }

        // 4️⃣ 기타 JSON 파싱 오류
        else -> "요청 본문을 처리하는 중 오류가 발생했습니다. JSON 메세지 규격을 확인해주세요."
    }

    return failureResponse(errorType = ErrorType.BAD_REQUEST, errorMessage = errorMessage)
}
```

#### 예시 1: Enum 값 불일치
**요청:**
```json
{
  "gender": "INVALID"
}
```
**응답:**
```json
{
  "meta": {
    "result": "FAIL",
    "errorCode": "Bad Request",
    "message": "필드 'gender'의 값 'INVALID'이(가) 예상 타입(Gender)과 일치하지 않습니다. 사용 가능한 값 : [MALE, FEMALE]"
  },
  "data": null
}
```

#### 예시 2: 필수 필드 누락
**요청:**
```json
{
  "email": "test@example.com"
  // memberId 누락
}
```
**응답:**
```json
{
  "meta": {
    "result": "FAIL",
    "errorCode": "Bad Request",
    "message": "필수 필드 'memberId'이(가) 누락되었습니다."
  },
  "data": null
}
```

---

### 3.7 존재하지 않는 엔드포인트 (404)
```kotlin
@ExceptionHandler
fun handleNotFound(e: NoResourceFoundException): ResponseEntity<ApiResponse<*>> {
    return failureResponse(errorType = ErrorType.NOT_FOUND)
}
```

---

### 3.8 모든 예외의 최종 처리 (Fallback)
```kotlin
@ExceptionHandler
fun handle(e: Throwable): ResponseEntity<ApiResponse<*>> {
    log.error("Exception : {}", e.message, e)
    val errorType = ErrorType.INTERNAL_ERROR
    return failureResponse(errorType = errorType)
}
```
**역할:** 위에서 처리되지 않은 모든 예외를 잡아서 500 에러 반환

---

## 4. 공통 응답 생성 메서드

```kotlin
private fun failureResponse(
    errorType: ErrorType,
    errorMessage: String? = null
): ResponseEntity<ApiResponse<*>> =
    ResponseEntity(
        ApiResponse.fail(
            errorCode = errorType.code,
            errorMessage = errorMessage ?: errorType.message
        ),
        errorType.status,
    )
```

---

## 5. 실전 활용 예시

### 5.1 Service Layer에서 예외 발생
```kotlin
class MemberService {
    fun getMember(memberId: String): Member {
        return memberRepository.findByMemberId(memberId)
            ?: throw CoreException(ErrorType.NOT_FOUND, "회원을 찾을 수 없습니다: $memberId")
    }
}
```

### 5.2 Controller에서는 예외 처리 불필요
```kotlin
@RestController
class MemberController(private val memberService: MemberService) {
    @GetMapping("/api/v1/users/{memberId}")
    fun getMember(@PathVariable memberId: String): ApiResponse<MemberResponse> {
        // 예외 발생 시 자동으로 ApiControllerAdvice에서 처리
        val member = memberService.getMember(memberId)
        return ApiResponse.success(member.toResponse())
    }
}
```

---

## 6. 핵심 정리

### @RestControllerAdvice의 장점
✅ **일관된 에러 응답 형식** - 모든 API가 동일한 구조로 에러 반환
✅ **유지보수성 향상** - 예외 처리 로직이 한 곳에 집중
✅ **자세한 에러 메시지** - 사용자가 무엇이 잘못되었는지 명확히 알 수 있음
✅ **로깅 통합** - 모든 예외를 한 곳에서 로깅

### 예외 처리 계층 구조
```
1. CoreException (커스텀 예외)
2. Spring Validation 예외
3. HTTP 요청 관련 예외 (파라미터, 헤더, 바디)
4. JSON 파싱 예외
5. 404 Not Found
6. 기타 모든 예외 (Throwable)
```

### 가장 유용한 포인트
**JSON 파싱 에러에서 `rootCause` 분석하여 구체적인 에러 메시지 제공**
- Enum 값 불일치 → 사용 가능한 값 목록 표시
- 필수 필드 누락 → 어떤 필드가 없는지 명확히 표시
- 타입 불일치 → 기대하는 타입과 전달된 값 표시

이렇게 구현하면 **API 사용자(프론트엔드 개발자)가 에러를 빠르게 이해하고 해결**할 수 있습니다!