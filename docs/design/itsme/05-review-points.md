# 05. Review Points

## ⭐ 핵심 검토 포인트 (반드시 확인해주세요!)

### 1. 좋아요 기능의 멱등성 (Idempotency) 보장 🔄

#### 왜 중요한가?
- 사용자가 실수로 좋아요 버튼을 여러 번 누를 수 있음
- 네트워크 불안정으로 같은 요청이 중복 전송될 수 있음
- 같은 요청을 여러 번 보내도 동일한 결과가 보장되어야 함

#### 우리는 어떻게 해결했는가?

**1) DB 레벨 제약조건**
```sql
-- Like 테이블에 복합 유니크 제약조건
ALTER TABLE likes ADD CONSTRAINT uk_member_product
  UNIQUE (member_id, product_id);
```
→ 동일한 회원이 동일한 상품에 중복 좋아요 물리적으로 차단

**2) 애플리케이션 레벨 처리**

```kotlin
// 좋아요 등록
fun toggleLike(memberId: Long, productId: Long): LikeInfo {
    val existingLike = likeRepository.findByMemberIdAndProductId(memberId, productId)

    // 이미 존재하면? → 기존 데이터 반환 (멱등성 ✅)
    if (existingLike != null) {
        return LikeInfo.from(existingLike)
    }

    // 없으면? → 새로 생성
    val like = Like.create(memberId, productId)
    product.increaseLikeCount()
    return LikeInfo.from(likeRepository.save(like))
}

// 좋아요 취소
fun cancelLike(memberId: Long, productId: Long) {
    val like = likeRepository.findByMemberIdAndProductId(memberId, productId)

    // 좋아요가 없으면? → 아무것도 안 함 (멱등성 ✅)
    if (like == null) {
        return  // 이미 취소된 상태로 간주, 200 OK 반환
    }

    likeRepository.delete(like)
    product.decreaseLikeCount()
}
```

#### 핵심 포인트
| 구분 | 동작 | 결과 |
|-----|-----|-----|
| **등록 중복 요청** | 이미 존재하는 좋아요 재등록 시도 | 기존 데이터 반환, 좋아요 수 변화 없음 |
| **취소 중복 요청** | 이미 취소된 좋아요 재취소 시도 | 200 OK 반환, 에러 발생 없음 |
| **부작용 방지** | 좋아요 수(likesCount) 중복 증감 차단 | 데이터 정합성 보장 ✅ |

---

### 2. 재고 및 포인트 동시성 제어 (Concurrency Control) 🔒

#### 왜 중요한가?
여러 사용자가 동시에 주문할 때 발생할 수 있는 문제:

```
상황: 상품 재고 10개, 사용자 A와 B가 동시에 각각 8개씩 주문

[동시성 제어 없이]
T1: A가 재고 조회 (10개) ✓
T2: B가 재고 조회 (10개) ✓  ← 문제: 둘 다 10개로 보임
T3: A가 재고 차감 (10 - 8 = 2개)
T4: B가 재고 차감 (10 - 8 = 2개)  ← 재앙: 실제로는 -6개여야 함!
결과: 총 16개 판매, 재고는 2개로 표시 → 데이터 정합성 깨짐 ❌
```

#### 우리는 어떻게 해결했는가?

**비관적 락 (Pessimistic Lock) 적용**

```kotlin
// Repository에 비관적 락 설정
interface ProductRepository : JpaRepository<Product, Long> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT p FROM Product p WHERE p.id = :id")
    fun findByIdWithLock(@Param("id") id: Long): Product?
}

interface PointRepository : JpaRepository<Point, Long> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT p FROM Point p WHERE p.userId = :userId")
    fun findByUserIdWithLock(@Param("userId") userId: String): Point?
}
```

```kotlin
@Transactional
fun createOrder(command: CreateOrderCommand): OrderInfo {
    // 1. 재고 차감 (비관적 락으로 다른 트랜잭션 대기)
    command.items.forEach { item ->
        val product = productRepository.findByIdWithLock(item.productId)
            ?: throw ProductNotFoundException()

        if (!product.hasEnoughStock(item.quantity)) {
            throw InsufficientStockException()
        }

        product.decreaseStock(item.quantity)
    }

    // 2. 포인트 차감 (비관적 락 적용)
    val point = pointRepository.findByUserIdWithLock(command.userId)
        ?: throw PointNotFoundException()

    if (!point.hasEnoughBalance(totalAmount)) {
        throw InsufficientPointException()
    }

    point.use(totalAmount)

    // 3. 주문 생성 및 외부 시스템 연동
    val order = Order.create(command, totalAmount)
    externalOrderService.sendOrder(order)
    order.complete()

    return OrderInfo.from(order)
}
```

#### 비관적 락 동작 원리
```
[비관적 락 적용 후]
T1: A가 재고 조회 + 락 획득 (10개) 🔒
T2: B가 재고 조회 시도 → ⏳ 대기 (A의 락이 풀릴 때까지)
T3: A가 재고 차감 (10 - 8 = 2개)
T4: A의 트랜잭션 커밋 + 락 해제 🔓
T5: B가 재고 조회 + 락 획득 (2개) 🔒
T6: B가 재고 부족 확인 (2 < 8)
T7: B에게 InsufficientStockException 발생
결과: A만 주문 성공, B는 재고 부족 에러 → 정합성 보장 ✅
```

#### 왜 낙관적 락이 아닌 비관적 락을 선택했는가?

| 비교 항목 | 낙관적 락 | 비관적 락 (우리 선택) |
|---------|---------|---------|
| **충돌 빈도** | 낮을 때 유리 | 높을 때 유리 ✅ |
| **재시도 필요** | O (충돌 시 재시도) | X (락으로 순서 보장) ✅ |
| **사용자 경험** | 충돌 시 에러 → 재시도 필요 ❌ | 대기 후 정확한 재고 확인 ✅ |
| **구현 복잡도** | 재시도 로직 필요 | 상대적으로 단순 ✅ |
| **이 프로젝트** | ❌ | ✅ 선택! |

**선택 이유:**
1. **주문/재고는 충돌 가능성이 높음** (인기 상품일수록)
2. **재시도 로직보다 락으로 확실히 제어**하는 것이 안전
3. **트랜잭션이 짧아 락 대기 시간이 길지 않음**
4. **데드락 방지**: 락 획득 순서 통일 (Product → Point)

#### 핵심 포인트
| 구분 | 설명 | 효과 |
|-----|-----|-----|
| **비관적 락** | DB의 `SELECT FOR UPDATE` 사용 | 동시 접근 물리적 차단 🔒 |
| **트랜잭션 범위** | 재고 차감 + 포인트 차감 + 주문 생성 + 외부 연동 | 원자성 보장 (All or Nothing) ✅ |
| **롤백 보장** | 외부 시스템 실패 시 자동 롤백 | 재고/포인트 자동 복원 ✅ |
| **데드락 방지** | 락 획득 순서 통일 (Product → Point) | 교착 상태 방지 ✅ |

---

### 3. 외부 시스템 연동 실패 시 트랜잭션 롤백 🔄

#### 문제 상황
- 주문 생성 후 외부 시스템(배송/결제 등) 연동 필요
- 외부 시스템 장애 시 이미 차감된 재고와 포인트 처리 방법?

#### 우리의 해결 방법
```kotlin
@Transactional
fun createOrder(command: CreateOrderCommand): OrderInfo {
    // 1. 재고 차감
    // 2. 포인트 차감
    // 3. 주문 생성 (상태: PENDING)

    try {
        // 4. 외부 시스템 연동
        externalOrderClient.sendOrder(order)
        order.complete()  // 상태 → COMPLETED
    } catch (e: ExternalSystemException) {
        order.fail()  // 상태 → FAILED
        throw OrderCreationFailedException()  // 트랜잭션 롤백 → 재고/포인트 자동 복원
    }

    return OrderInfo.from(order)
}
```

#### 핵심 포인트
- **외부 시스템 연동을 트랜잭션 범위에 포함**
- **실패 시 자동 롤백으로 재고/포인트 복원** (보상 트랜잭션 불필요)
- **주문 상태 추적**: PENDING → COMPLETED / FAILED

---

### 4. 좋아요 수 비정규화를 통한 조회 성능 최적화 📊

#### 문제 상황
- 상품 목록 조회 시 각 상품의 좋아요 수를 COUNT 쿼리로 계산하면 성능 저하
- 페이지네이션된 목록에서 N+1 문제 발생 가능

#### 우리의 해결 방법
```kotlin
@Entity
class Product(
    // ... other fields

    @Column(name = "likes_count", nullable = false)
    var likesCount: Int = 0  // 좋아요 수를 Product 엔티티에 저장
) {
    fun increaseLikeCount() { this.likesCount++ }
    fun decreaseLikeCount() { if (this.likesCount > 0) this.likesCount-- }
}
```

#### 핵심 포인트
- **조회 성능 향상**: COUNT 쿼리 없이 바로 조회
- **정렬 가능**: `ORDER BY likes_count DESC` 지원
- **동기화 보장**: 좋아요 등록/취소 시 즉시 증감
- **트레이드오프**: 저장 공간 증가 vs 조회 성능 향상 (조회 성능 선택)

---

## 📋 추가 고려 사항

### 5. Value Object (VO) 도입으로 도메인 로직 응집

**해결 방법**
```kotlin
@Embeddable
data class Stock(
    @Column(name = "stock", nullable = false)
    private val value: Int
) {
    init { require(value >= 0) { "재고는 0 이상이어야 합니다" } }

    fun decrease(quantity: Int): Stock {
        require(value >= quantity) { "재고가 부족합니다" }
        return Stock(value - quantity)
    }
}
```

**효과**: 비즈니스 규칙이 VO에 응집 + 불변 객체로 안전성 보장

---

### 6. 연관관계: 단방향 우선 적용
- **단방향 연관관계 우선**: `Product → Brand`, `Like → Member/Product`
- **예외 (양방향)**: `Order ↔ OrderItem` (생명주기 함께 관리)
- **효과**: 순환 참조 방지, 복잡도 감소

---

### 7. API 응답 일관성
```kotlin
data class ApiResponse<T>(
    val code: Int,
    val message: String,
    val data: T? = null
)
```
- **모든 API에서 동일한 응답 구조** 사용
- **한국어 에러 메시지**로 명확한 상황 전달

---

## 📌 핵심 요약 (Quick Summary)

| 포인트 | 해결 방법 | 효과 |
|-------|---------|-----|
| **좋아요 멱등성** | 조회 후 존재 확인 + DB Unique 제약 | 중복 요청 시에도 정합성 보장 ✅ |
| **재고/포인트 동시성** | 비관적 락 (PESSIMISTIC_WRITE) | 동시 주문 시 정합성 보장 ✅ |
| **외부 시스템 실패** | 트랜잭션 롤백 + 주문 상태 관리 | 재고/포인트 자동 복원 ✅ |
| **좋아요 수 조회** | Product 엔티티에 비정규화 | 조회 성능 향상 + 정렬 가능 ✅ |
| **도메인 로직 응집** | Value Object (Money, Stock, Quantity) | 비즈니스 규칙 응집 + 불변성 ✅ |
| **API 응답** | 표준화된 ApiResponse 구조 | 일관된 응답 형식 ✅ |
