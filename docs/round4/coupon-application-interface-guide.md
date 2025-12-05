# Coupon Application & Interface Layer 가이드

## 📌 개요

이 문서는 **Coupon 도메인**의 Application 레이어(Facade)와 Interface 레이어(Controller) 구현 가이드입니다.

---

## 🏗️ 레이어 구조

```
Application Layer (Facade)
    ↓ 조율
Domain Layer (Service)
    ↓ 활용
Infrastructure Layer (Repository)

Interface Layer (Controller)
    ↓ 호출
Application Layer (Facade)
```

---

## 📦 Application Layer (Facade)

### 1. CouponCommand (입력 DTO)

Command 객체는 Interface 레이어에서 받은 요청을 Domain 레이어로 전달하기 위한 객체입니다.

```kotlin
package com.loopers.application.coupon

/**
 * 쿠폰 발급 Command
 */
data class IssueCouponCommand(
    val memberId: String,
    val couponId: Long,
)

/**
 * 쿠폰 사용 Command
 */
data class UseCouponCommand(
    val memberCouponId: Long,
)
```

---

### 2. CouponInfo (출력 DTO)

Info 객체는 Domain Entity를 Application 레이어의 DTO로 변환한 객체입니다.

```kotlin
package com.loopers.application.coupon

import com.loopers.domain.coupon.Coupon
import com.loopers.domain.coupon.CouponType
import com.loopers.domain.coupon.MemberCoupon
import org.springframework.data.domain.Page

/**
 * 쿠폰 정보
 */
data class CouponInfo(
    val id: Long,
    val name: String,
    val description: String?,
    val couponType: CouponType,
    val discountAmount: Long?,
    val discountRate: Int?,
) {
    companion object {
        fun from(coupon: Coupon): CouponInfo {
            return CouponInfo(
                id = coupon.id,
                name = coupon.name,
                description = coupon.description,
                couponType = coupon.couponType,
                discountAmount = coupon.discountAmount,
                discountRate = coupon.discountRate,
            )
        }

        fun fromList(coupons: List<Coupon>): List<CouponInfo> {
            return coupons.map { from(it) }
        }
    }
}

/**
 * 회원 쿠폰 정보
 */
data class MemberCouponInfo(
    val id: Long,
    val memberId: String,
    val coupon: CouponInfo,
    val isUsed: Boolean,
    val usedAt: String?,
    val createdAt: String,
) {
    companion object {
        fun from(memberCoupon: MemberCoupon): MemberCouponInfo {
            return MemberCouponInfo(
                id = memberCoupon.id,
                memberId = memberCoupon.memberId,
                coupon = CouponInfo.from(memberCoupon.coupon),
                isUsed = memberCoupon.usedAt != null,
                usedAt = memberCoupon.usedAt?.toString(),
                createdAt = memberCoupon.createdAt.toString(),
            )
        }

        fun fromList(memberCoupons: List<MemberCoupon>): List<MemberCouponInfo> {
            return memberCoupons.map { from(it) }
        }
    }
}

/**
 * 할인 계산 결과
 */
data class DiscountInfo(
    val orderAmount: Long,
    val discountAmount: Long,
    val finalAmount: Long,
)
```

**주요 패턴:**
- ✅ Companion object의 `from()` 메서드로 변환
- ✅ `fromList()` 메서드로 리스트 변환
- ✅ 도메인 객체의 의존성 제거 (String, Long 등 기본 타입 사용)

---

### 3. CouponService 메서드 시그니처

OrderFacade에서 사용할 CouponService의 메서드들입니다.

```kotlin
package com.loopers.domain.coupon

import com.loopers.domain.shared.Money
import org.springframework.stereotype.Service

@Service
class CouponService(
    private val couponRepository: CouponRepository,
    private val memberCouponRepository: MemberCouponRepository,
) {
    /**
     * 회원 쿠폰 조회 (비관적 락)
     * - 회원 ID와 쿠폰 ID로 회원 쿠폰 조회
     * - 사용 가능 여부 검증
     * - Pessimistic Write Lock 적용
     */
    fun getMemberCoupon(memberId: String, couponId: Long): MemberCoupon {
        val memberCoupon = memberCouponRepository.findByMemberIdAndCouponId(memberId, couponId)
            ?: throw CoreException(
                ErrorType.COUPON_NOT_FOUND,
                "회원의 쿠폰을 찾을 수 없습니다. memberId: $memberId, couponId: $couponId"
            )

        if (!memberCoupon.canUse()) {
            throw CoreException(
                ErrorType.COUPON_NOT_AVAILABLE,
                "사용할 수 없는 쿠폰입니다."
            )
        }

        return memberCoupon
    }

    /**
     * 할인 금액 계산
     */
    fun calculateDiscount(memberCoupon: MemberCoupon, orderAmount: Money): Money {
        return memberCoupon.calculateDiscount(orderAmount)
    }

    /**
     * 쿠폰 사용 처리
     */
    fun useCoupon(memberCoupon: MemberCoupon) {
        memberCoupon.use()
    }
}
```

**핵심:**
- ✅ `getMemberCoupon()`: 비관적 락으로 동시성 제어
- ✅ `calculateDiscount()`: 할인 금액 계산 위임
- ✅ `useCoupon()`: 쿠폰 사용 처리 위임

---

### 4. OrderFacade에서 쿠폰 적용

과제 요구사항에 따라 **OrderFacade에서 쿠폰을 적용**합니다.

```kotlin
package com.loopers.application.order

import com.loopers.domain.coupon.CouponService
import com.loopers.domain.member.MemberService
import com.loopers.domain.order.CreateOrderCommand
import com.loopers.domain.order.OrderItemCommand
import com.loopers.domain.order.OrderService
import com.loopers.domain.product.ProductService
import com.loopers.domain.shared.Money
import org.springframework.stereotype.Component
import org.springframework.transaction.annotation.Transactional

@Component
class OrderFacade(
    private val orderService: OrderService,
    private val productService: ProductService,
    private val memberService: MemberService,
    private val couponService: CouponService, // 쿠폰 서비스 추가
) {

    /**
     * 주문 생성 (쿠폰 적용)
     */
    @Transactional
    fun createOrder(request: CreateOrderRequest): OrderInfo {
        // 1. 쿠폰 적용 (있는 경우)
        var discountAmount = Money.zero()
        var memberCouponForUse: MemberCoupon? = null

        if (request.couponId != null) {
            // 상품 조회 (할인 금액 계산용)
            val productIds = request.items.map { it.productId }
            val products = productService.getProductsByIds(productIds)
            val productMap = products.associateBy { it.id!! }

            // 쿠폰 검증 및 조회 (비관적 락)
            val memberCoupon = couponService.getMemberCoupon(
                memberId = request.memberId,
                couponId = request.couponId
            )

            // 할인 금액 계산 (주문 금액 기준)
            val totalAmount = calculateOrderAmount(request.items, productMap)
            discountAmount = couponService.calculateDiscount(memberCoupon, totalAmount)

            memberCouponForUse = memberCoupon
        }

        // 2. OrderService에 할인 금액 전달하여 주문 생성
        val command = CreateOrderCommand(
            memberId = request.memberId,
            items = request.items.map { OrderItemCommand(it.productId, it.quantity) },
            discountAmount = discountAmount // 할인 금액 전달
        )
        val order = orderService.createOrder(command)

        // 3. 쿠폰 사용 처리 (주문 완료 후)
        memberCouponForUse?.let { couponService.useCoupon(it) }

        return OrderInfo.from(order)
    }

    /**
     * 주문 금액 계산 헬퍼 메서드
     */
    private fun calculateOrderAmount(
        items: List<OrderItemRequest>,
        productMap: Map<Long, Product>
    ): Money {
        return items
            .map { item ->
                val product = productMap[item.productId]
                    ?: throw CoreException(
                        ErrorType.PRODUCT_NOT_FOUND,
                        "상품을 찾을 수 없습니다. id: ${item.productId}"
                    )
                product.price.multiply(item.quantity)
            }
            .fold(Money.zero()) { acc, money -> acc.plus(money) }
    }
}
```

**핵심:**
- ✅ 쿠폰은 **주문 생성 시에만 사용**
- ✅ 별도의 쿠폰 발급/조회 API 불필요
- ✅ `@Transactional`로 전체 원자성 보장
- ✅ 할인 금액을 OrderService에 전달

**Facade 설계 원칙:**
1. ✅ `@Component`로 Spring Bean 등록
2. ✅ `@Transactional`로 트랜잭션 관리
3. ✅ Domain Service를 주입받아 조율
4. ✅ Entity → Info 변환만 수행 (비즈니스 로직 없음)
5. ✅ 여러 Service를 조합 (OrderService, CouponService)

---

### 5. OrderService 수정사항

OrderService는 할인 금액을 받아서 Order 생성 시 적용합니다.

**변경 전:**
```kotlin
@Transactional
fun createOrder(command: CreateOrderCommand): Order {
    // 상품 조회
    val productIds = command.items.map { it.productId }
    val productMap = productRepository.findAllByIdIn(productIds)
        .associateBy { it.id!! }

    // 회원 조회
    val member = memberRepository.findByMemberIdOrThrow(command.memberId)

    // Order 생성
    val order = Order.create(command.memberId, command.items, productMap)

    // 재고 차감
    order.items.forEach { item ->
        item.product.decreaseStock(item.quantity)
    }

    // 회원 결제 처리 (포인트 검증 및 차감)
    member.pay(order.totalAmount)

    // 주문 저장
    val savedOrder = orderRepository.save(order)

    // 외부 시스템 연동
    externalOrderService.processOrder(savedOrder)
    savedOrder.complete()

    return savedOrder
}
```

**변경 후:**
```kotlin
@Transactional
fun createOrder(command: CreateOrderCommand): Order {
    // 상품 조회
    val productIds = command.items.map { it.productId }
    val productMap = productRepository.findAllByIdIn(productIds)
        .associateBy { it.id!! }

    // 회원 조회
    val member = memberRepository.findByMemberIdOrThrow(command.memberId)

    // Order 생성 (할인 금액 포함)
    val order = Order.create(
        memberId = command.memberId,
        orderItems = command.items,
        productMap = productMap,
        discountAmount = command.discountAmount // 할인 금액 전달
    )

    // 재고 차감
    order.items.forEach { item ->
        item.product.decreaseStock(item.quantity)
    }

    // 회원 결제 처리 (할인 적용된 최종 금액으로 차감)
    member.pay(order.finalAmount)

    // 주문 저장
    val savedOrder = orderRepository.save(order)

    // 외부 시스템 연동
    externalOrderService.processOrder(savedOrder)
    savedOrder.complete()

    return savedOrder
}
```

**주요 변경사항:**
1. ✅ `CreateOrderCommand`에 `discountAmount: Money` 필드 추가
2. ✅ `Order.create()`에 `discountAmount` 파라미터 추가
3. ✅ `member.pay(order.finalAmount)` - 할인 적용된 최종 금액으로 결제

---

### 6. Order 도메인 수정사항

Order 엔티티에 할인 금액과 최종 금액 필드를 추가합니다.

**추가 필드:**
```kotlin
@Entity
@Table(name = "orders")
class Order(
    memberId: String,
    items: List<OrderItem> = emptyList(),
    discountAmount: Money = Money.zero(), // 할인 금액
) : BaseEntity() {

    @Column(name = "member_id", nullable = false, length = 50)
    var memberId: String = memberId
        protected set

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 20)
    var status: OrderStatus = OrderStatus.PENDING
        protected set

    @Embedded
    @AttributeOverride(name = "amount", column = Column(name = "total_amount", nullable = false))
    var totalAmount: Money = Money.zero()
        protected set

    @Embedded
    @AttributeOverride(name = "amount", column = Column(name = "discount_amount", nullable = false))
    var discountAmount: Money = discountAmount // 할인 금액
        protected set

    @Embedded
    @AttributeOverride(name = "amount", column = Column(name = "final_amount", nullable = false))
    var finalAmount: Money = Money.zero() // 최종 금액
        protected set

    @OneToMany(mappedBy = "order", cascade = [jakarta.persistence.CascadeType.ALL], orphanRemoval = true)
    protected val mutableItems: MutableList<OrderItem> = items.toMutableList()

    val items: List<OrderItem>
        get() = mutableItems.toList()

    init {
        items.forEach { it.assignOrder(this) }
        this.totalAmount = calculateTotalAmount()
        this.finalAmount = this.totalAmount.minus(this.discountAmount)
    }

    // ... 기존 메서드들 ...

    companion object {
        fun create(
            memberId: String,
            orderItems: List<OrderItemCommand>,
            productMap: Map<Long, Product>,
            discountAmount: Money = Money.zero() // 할인 금액 추가
        ): Order {
            val items = orderItems.map { itemCommand ->
                val product = productMap[itemCommand.productId]
                    ?: throw CoreException(
                        ErrorType.PRODUCT_NOT_FOUND,
                        "상품을 찾을 수 없습니다. id: ${itemCommand.productId}"
                    )

                val quantity = Quantity.of(itemCommand.quantity)
                product.validateStock(quantity)

                OrderItem.of(product, quantity)
            }

            return Order(memberId, items, discountAmount)
        }
    }
}
```

**주요 변경사항:**
1. ✅ `discountAmount: Money` 필드 추가 (할인 금액)
2. ✅ `finalAmount: Money` 필드 추가 (최종 결제 금액)
3. ✅ `init` 블록에서 `finalAmount` 계산: `totalAmount - discountAmount`
4. ✅ `Order.create()`에 `discountAmount` 파라미터 추가

---

### 7. CreateOrderCommand 수정사항

```kotlin
package com.loopers.domain.order

import com.loopers.domain.shared.Money

data class CreateOrderCommand(
    val memberId: String,
    val items: List<OrderItemCommand>,
    val discountAmount: Money = Money.zero(), // 할인 금액 추가
)

data class OrderItemCommand(
    val productId: Long,
    val quantity: Int,
)
```

**주요 변경사항:**
- ✅ `discountAmount: Money` 필드 추가 (기본값: Money.zero())

---

## 🌐 Interface Layer (Controller)

### 주문 요청에 쿠폰 ID 추가

기존 주문 요청에 `couponId` 필드를 추가합니다.

```kotlin
package com.loopers.application.order

import io.swagger.v3.oas.annotations.media.Schema
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Positive

/**
 * 주문 생성 요청
 */
data class CreateOrderRequest(
    @Schema(description = "회원 ID", example = "member123")
    @field:NotBlank(message = "회원 ID는 필수입니다")
    val memberId: String,

    @Schema(description = "주문 상품 목록")
    @field:NotNull(message = "주문 상품 목록은 필수입니다")
    val items: List<OrderItemRequest>,

    @Schema(description = "쿠폰 ID (선택)", example = "42")
    val couponId: Long? = null, // ✅ 쿠폰 ID 추가 (선택사항)
)

data class OrderItemRequest(
    @Schema(description = "상품 ID", example = "1")
    @field:NotNull(message = "상품 ID는 필수입니다")
    @field:Positive(message = "상품 ID는 양수여야 합니다")
    val productId: Long,

    @Schema(description = "수량", example = "2")
    @field:NotNull(message = "수량은 필수입니다")
    @field:Positive(message = "수량은 양수여야 합니다")
    val quantity: Int,
)
```

**핵심:**
- ✅ 쿠폰은 **주문 요청의 선택 필드**
- ✅ 별도의 쿠폰 API 불필요
- ✅ 주문 Controller는 기존과 동일

**참고:**
- 과제 요구사항에서는 **별도의 쿠폰 조회/발급 API가 필요하지 않습니다**
- 쿠폰은 **주문 시에만 사용**되므로 OrderController에서 처리합니다
- 테스트를 위해 쿠폰 데이터는 미리 DB에 넣어두거나 테스트 픽스처로 생성합니다

---

## 📋 주문 시 쿠폰 적용 흐름

과제 요구사항에 따라 **주문 API에서 쿠폰을 적용**합니다.

**주문 요청 예시:**
```json
{
  "items": [
    { "productId": 1, "quantity": 2 },
    { "productId": 3, "quantity": 1 }
  ],
  "couponId": 42
}
```

**처리 흐름:**
1. 쿠폰 검증 (존재 여부, 사용 가능 여부)
2. 재고 확인 및 차감
3. 포인트 확인 및 차감 (쿠폰 할인 적용 후)
4. 쿠폰 사용 처리
5. 주문 생성

**별도의 쿠폰 API는 구현하지 않습니다** (요구사항에 없음)

---

## 🔄 주문 시 쿠폰 적용 흐름

```
1. Client
   ↓ POST /api/v1/orders
   { "items": [...], "couponId": 42 }

2. OrderV1Controller
   ↓ CreateOrderRequest

3. OrderFacade (@Transactional)
   ├─ 상품 조회 및 재고 확인
   ├─ 쿠폰 검증 및 할인 계산 (CouponService)
   ├─ 포인트 차감 (MemberService)
   ├─ 재고 차감 (ProductService)
   ├─ 쿠폰 사용 처리 (CouponService)
   └─ 주문 생성 (OrderService)

4. Response
   Order (Entity) → OrderInfo → OrderResponse → ApiResponse
```

**핵심:**
- ✅ 모든 처리가 **하나의 트랜잭션**에서 실행
- ✅ 하나라도 실패하면 **전체 롤백**
- ✅ 쿠폰은 주문 완료 시점에 사용 처리

---

## 🎯 공통 응답 포맷

기존 프로젝트의 `ApiResponse` 활용:

```json
{
  "meta": {
    "result": "SUCCESS",
    "errorCode": null,
    "message": null
  },
  "data": {
    "id": 1,
    "memberId": "member123",
    "coupon": {
      "id": 1,
      "name": "신규 회원 5000원 할인 쿠폰",
      "description": "신규 회원 대상 5000원 할인",
      "couponType": "FIXED_AMOUNT",
      "discountAmount": 5000,
      "discountRate": null
    },
    "isUsed": false,
    "usedAt": null,
    "createdAt": "2024-01-01T00:00:00"
  }
}
```

**실패 응답:**
```json
{
  "meta": {
    "result": "FAIL",
    "errorCode": "COUPON_004",
    "message": "이미 발급받은 쿠폰입니다. 쿠폰 ID: 1"
  },
  "data": null
}
```

---

## ✅ 체크리스트

### Application Layer (Facade)
- [ ] `@Component` 어노테이션을 사용했는가?
- [ ] 클래스 레벨에 `@Transactional(readOnly = true)`를 적용했는가?
- [ ] 쓰기 작업에만 `@Transactional`을 명시했는가?
- [ ] Command 객체를 정의했는가?
- [ ] Info 객체의 `from()` 메서드를 구현했는가?
- [ ] Domain Service만 호출하고 비즈니스 로직은 포함하지 않았는가?

### Interface Layer (Controller)
- [ ] `@RestController`와 `@RequestMapping`을 사용했는가?
- [ ] API Spec 인터페이스를 정의하고 구현했는가?
- [ ] Request DTO에 Validation 어노테이션을 적용했는가?
- [ ] Request DTO의 `toCommand()` 메서드를 구현했는가?
- [ ] Response DTO의 `from()` 메서드를 구현했는가?
- [ ] Swagger 어노테이션으로 API 문서화를 했는가?
- [ ] `ApiResponse`로 응답을 래핑했는가?

---

## 💡 핵심 요약

1. **Facade는 조율자** - Domain Service를 호출하고 DTO 변환만 수행
2. **Command 패턴** - Request → Command → Domain 흐름
3. **Info 패턴** - Entity → Info → Response 흐름
4. **API Spec 분리** - 인터페이스로 Swagger 문서화, Controller는 구현
5. **Validation** - Jakarta Validation으로 입력 검증
6. **공통 응답** - ApiResponse로 일관된 응답 포맷
7. **레이어 분리** - 각 레이어는 자신의 역할만 수행

---

이 가이드를 따라 구현하면 **일관성 있고 확장 가능한** Application & Interface 레이어를 만들 수 있습니다! 🚀
