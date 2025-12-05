# API 구현 가이드

## 📋 목차
1. [Member API 수정](#1-member-api-수정)
2. [Brand API 구현](#2-brand-api-구현)
3. [Product API 구현](#3-product-api-구현)
4. [Like API 구현](#4-like-api-구현)
5. [Order API 구현](#5-order-api-구현)
6. [Coupon API 구현](#6-coupon-api-구현)

---

## 1. Member API 수정

### 📍 현재 상태
- ✅ `POST /api/v1/users/join` (구현됨)
- ✅ `GET /api/v1/users/{memberId}` (구현됨)
- ❌ `POST /api/v1/users` (필요)
- ❌ `GET /api/v1/users/me` (필요)

### 🔧 수정 사항

#### MemberV1Controller.kt
```kotlin
@RestController
@RequestMapping("/api/v1/users")
class MemberV1Controller(
    private val memberFacade: MemberFacade,
) : MemberV1ApiSpec {

    // 변경: /join -> /
    @PostMapping
    override fun join(
        @Valid @RequestBody request: JoinMemberRequest
    ): ApiResponse<MemberV1Dto.MemberResponse> {
        return memberFacade.joinMember(request.toCommand())
            .let { MemberV1Dto.MemberResponse.from(it) }
            .let { ApiResponse.success(it) }
    }

    // 추가: 내 정보 조회
    @GetMapping("/me")
    override fun getMe(
        @RequestHeader("X-USER-ID") memberId: String
    ): ApiResponse<MemberV1Dto.MemberResponse> {
        return memberFacade.getMemberByMemberId(memberId)
            ?.let { MemberV1Dto.MemberResponse.from(it) }
            ?.let { ApiResponse.success(it) }
            ?: throw CoreException(ErrorType.NOT_FOUND, "유저를 찾을 수 없습니다")
    }

    // 기존 유지 (삭제하지 말 것 - 테스트에서 사용 중일 수 있음)
    @GetMapping("/{memberId}")
    override fun getMemberByMemberId(
        @PathVariable memberId: String,
    ): ApiResponse<MemberV1Dto.MemberResponse> {
        return memberFacade.getMemberByMemberId(memberId)
            ?.let { MemberV1Dto.MemberResponse.from(it) }
            ?.let { ApiResponse.success(it) }
            ?: throw CoreException(ErrorType.NOT_FOUND, "유저를 찾을 수 없습니다")
    }
}
```

#### MemberV1ApiSpec.kt 수정
```kotlin
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.Parameter
import io.swagger.v3.oas.annotations.media.Schema
import io.swagger.v3.oas.annotations.tags.Tag

@Tag(name = "Member V1 API", description = "회원 관련 API 입니다.")
interface MemberV1ApiSpec {
    @Operation(
        summary = "회원 가입",
        description = "회원 가입합니다.",
    )
    fun join(
        @Schema(name = "회원 정보", description = "가입할 회원 정보")
        request: JoinMemberRequest
    ): ApiResponse<MemberV1Dto.MemberResponse>

    @Operation(
        summary = "내 정보 조회",
        description = "로그인한 회원의 정보를 조회합니다.",
    )
    fun getMe(
        @Parameter(description = "회원 ID", required = true)
        memberId: String
    ): ApiResponse<MemberV1Dto.MemberResponse>

    @Operation(
        summary = "회원 정보 조회",
        description = "ID로 회원 정보를 조회합니다.",
    )
    fun getMemberByMemberId(
        @Parameter(description = "회원 ID", required = true)
        memberId: String
    ): ApiResponse<MemberV1Dto.MemberResponse>
}
```

---

## 2. Brand API 구현

### 📍 필요 API
- `GET /api/v1/brands/{brandId}` - 브랜드 정보 조회

### 📂 파일 생성

#### `interfaces/api/brand/BrandV1Controller.kt`
```kotlin
package com.loopers.interfaces.api.brand

import com.loopers.application.brand.BrandFacade
import com.loopers.interfaces.api.ApiResponse
import com.loopers.support.error.CoreException
import com.loopers.support.error.ErrorType
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/v1/brands")
class BrandV1Controller(
    private val brandFacade: BrandFacade,
) : BrandV1ApiSpec {

    @GetMapping("/{brandId}")
    override fun getBrand(
        @PathVariable brandId: Long
    ): ApiResponse<BrandV1Dto.BrandResponse> {
        return brandFacade.getBrand(brandId)
            .let { BrandV1Dto.BrandResponse.from(it) }
            .let { ApiResponse.success(it) }
    }
}
```

#### `application/brand/BrandFacade.kt` 수정 필요
```kotlin
// BrandFacade가 BrandInfo를 반환하도록 수정됨
@Component
class BrandFacade(
    private val brandService: BrandService,
) {
    fun getBrand(brandId: Long): BrandInfo {
        return brandService.getBrand(brandId)
            .let { BrandInfo.from(it) }
    }

    fun getBrands(pageable: Pageable): Page<BrandInfo> {
        return brandService.getBrands(pageable)
            .map { BrandInfo.from(it) }
    }
}
```

#### `interfaces/api/brand/BrandV1ApiSpec.kt`
```kotlin
package com.loopers.interfaces.api.brand

import com.loopers.interfaces.api.ApiResponse
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.media.Schema
import io.swagger.v3.oas.annotations.tags.Tag

@Tag(name = "Brand V1 API", description = "브랜드 관련 API 입니다.")
interface BrandV1ApiSpec {
    @Operation(
        summary = "브랜드 조회",
        description = "ID로 브랜드를 조회합니다.",
    )
    fun getBrand(
        @Schema(name = "브랜드 ID", description = "조회할 브랜드의 ID")
        brandId: Long,
    ): ApiResponse<BrandV1Dto.BrandResponse>
}
```

#### `interfaces/api/brand/BrandV1Dto.kt`
```kotlin
package com.loopers.interfaces.api.brand

import com.loopers.application.brand.BrandInfo

class BrandV1Dto {

    data class BrandResponse(
        val id: Long,
        val name: String,
        val description: String?
    ) {
        companion object {
            fun from(info: BrandInfo): BrandResponse {
                return BrandResponse(
                    id = info.id,
                    name = info.name,
                    description = info.description
                )
            }
        }
    }
}
```

---

## 3. Product API 구현

### 📍 필요 API
- `GET /api/v1/products` - 상품 목록 조회 (정렬, 필터링, 페이징)
- `GET /api/v1/products/{productId}` - 상품 상세 조회

### 📂 파일 생성

#### `interfaces/api/product/ProductV1Controller.kt`
```kotlin
package com.loopers.interfaces.api.product

import com.loopers.application.product.ProductFacade
import com.loopers.domain.product.ProductSortType
import com.loopers.interfaces.api.ApiResponse
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageRequest
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/v1/products")
class ProductV1Controller(
    private val productFacade: ProductFacade,
) : ProductV1ApiSpec {

    @GetMapping
    override fun getProducts(
        @RequestParam(required = false) brandId: Long?,
        @RequestParam(required = false, defaultValue = "LATEST") sort: ProductSortType,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "20") size: Int
    ): ApiResponse<Page<ProductV1Dto.ProductResponse>> {
        val pageable = PageRequest.of(page, size)

        // 기존 ProductFacade.getProducts(brandId, sort, pageable) 활용
        return productFacade.getProducts(brandId, sort, pageable)
            .map { ProductV1Dto.ProductResponse.from(it) }
            .let { ApiResponse.success(it) }
    }

    @GetMapping("/{productId}")
    override fun getProduct(
        @PathVariable productId: Long
    ): ApiResponse<ProductV1Dto.ProductResponse> {
        // 기존 ProductFacade.getProduct(productId) 활용
        return productFacade.getProduct(productId)
            .let { ProductV1Dto.ProductResponse.from(it) }
            .let { ApiResponse.success(it) }
    }
}
```

> **참고**: `ProductFacade`에 이미 `getProduct(productId)`, `getProducts(brandId, sort, pageable)` 메서드가 존재합니다.
> `ProductSortType`은 `com.loopers.domain.product.ProductRepository`에 정의된 enum입니다 (LATEST, PRICE_ASC, LIKES_DESC).

#### `interfaces/api/product/ProductV1ApiSpec.kt`
```kotlin
package com.loopers.interfaces.api.product

import com.loopers.domain.product.ProductSortType
import com.loopers.interfaces.api.ApiResponse
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.Parameter
import io.swagger.v3.oas.annotations.tags.Tag
import org.springframework.data.domain.Page

@Tag(name = "Product V1 API", description = "상품 관련 API 입니다.")
interface ProductV1ApiSpec {
    @Operation(
        summary = "상품 목록 조회",
        description = "상품 목록을 조회합니다. 브랜드 필터링, 정렬, 페이징을 지원합니다.",
    )
    fun getProducts(
        @Parameter(description = "브랜드 ID (필터링)")
        brandId: Long?,
        @Parameter(description = "정렬 기준 (LATEST, PRICE_ASC, LIKES_DESC)")
        sort: ProductSortType,
        @Parameter(description = "페이지 번호")
        page: Int,
        @Parameter(description = "페이지 크기")
        size: Int
    ): ApiResponse<Page<ProductV1Dto.ProductResponse>>

    @Operation(
        summary = "상품 상세 조회",
        description = "ID로 상품 상세 정보를 조회합니다.",
    )
    fun getProduct(
        @Parameter(description = "상품 ID")
        productId: Long
    ): ApiResponse<ProductV1Dto.ProductResponse>
}
```

#### `interfaces/api/product/ProductV1Dto.kt`
```kotlin
package com.loopers.interfaces.api.product

import com.loopers.application.product.ProductInfo

class ProductV1Dto {

    data class ProductResponse(
        val id: Long,
        val name: String,
        val description: String?,
        val price: Long,
        val stock: Int,
        val brandId: Long,
        val brandName: String,
        val likesCount: Int
    ) {
        companion object {
            fun from(info: ProductInfo): ProductResponse {
                return ProductResponse(
                    id = info.id,
                    name = info.name,
                    description = info.description,
                    price = info.price,
                    stock = info.stock,
                    brandId = info.brandId,
                    brandName = info.brandName,
                    likesCount = info.likesCount
                )
            }
        }
    }
}
```

---

## 4. Like API 구현

### 📍 필요 API
- `POST /api/v1/like/products/{productId}` - 좋아요 등록 (멱등)
- `DELETE /api/v1/like/products/{productId}` - 좋아요 취소 (멱등)
- `GET /api/v1/like/products` - 내가 좋아요 한 상품 목록

### 📂 파일 생성

#### `interfaces/api/like/LikeV1Controller.kt`
```kotlin
package com.loopers.interfaces.api.like

import com.loopers.application.like.LikeFacade
import com.loopers.interfaces.api.ApiResponse
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageRequest
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/v1/like")
class LikeV1Controller(
    private val likeFacade: LikeFacade,
) : LikeV1ApiSpec {

    @PostMapping("/products/{productId}")
    override fun likeProduct(
        @RequestHeader("X-USER-ID") memberId: String,
        @PathVariable productId: Long
    ): ApiResponse<LikeV1Dto.LikeResponse> {
        // 기존 LikeFacade.addLike(memberId, productId) 활용
        likeFacade.addLike(memberId, productId)
        return ApiResponse.success(
            LikeV1Dto.LikeResponse(
                productId = productId,
                liked = true
            )
        )
    }

    @DeleteMapping("/products/{productId}")
    override fun unlikeProduct(
        @RequestHeader("X-USER-ID") memberId: String,
        @PathVariable productId: Long
    ): ApiResponse<LikeV1Dto.LikeResponse> {
        // 기존 LikeFacade.cancelLike(memberId, productId) 활용
        likeFacade.cancelLike(memberId, productId)
        return ApiResponse.success(
            LikeV1Dto.LikeResponse(
                productId = productId,
                liked = false
            )
        )
    }

    @GetMapping("/products")
    override fun getLikedProducts(
        @RequestHeader("X-USER-ID") memberId: String,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "20") size: Int
    ): ApiResponse<Page<LikeV1Dto.LikedProductResponse>> {
        val pageable = PageRequest.of(page, size)
        // 기존 LikeFacade.getMyLikes(memberId, pageable) 활용
        return likeFacade.getMyLikes(memberId, pageable)
            .map { LikeV1Dto.LikedProductResponse.from(it) }
            .let { ApiResponse.success(it) }
    }
}
```

> **참고**: `LikeFacade`에 이미 `addLike(memberId, productId)`, `cancelLike(memberId, productId)`, `getMyLikes(memberId, pageable)` 메서드가 존재합니다.
> memberId는 `String` 타입입니다. (X-USER-ID 헤더 값)

#### `interfaces/api/like/LikeV1ApiSpec.kt`
```kotlin
package com.loopers.interfaces.api.like

import com.loopers.interfaces.api.ApiResponse
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.Parameter
import io.swagger.v3.oas.annotations.tags.Tag
import org.springframework.data.domain.Page

@Tag(name = "Like V1 API", description = "좋아요 관련 API 입니다.")
interface LikeV1ApiSpec {
    @Operation(
        summary = "상품 좋아요",
        description = "상품에 좋아요를 등록합니다. 멱등성을 보장합니다.",
    )
    fun likeProduct(
        @Parameter(description = "회원 ID (X-USER-ID)", required = true)
        memberId: String,
        @Parameter(description = "상품 ID", required = true)
        productId: Long
    ): ApiResponse<LikeV1Dto.LikeResponse>

    @Operation(
        summary = "상품 좋아요 취소",
        description = "상품 좋아요를 취소합니다. 멱등성을 보장합니다.",
    )
    fun unlikeProduct(
        @Parameter(description = "회원 ID (X-USER-ID)", required = true)
        memberId: String,
        @Parameter(description = "상품 ID", required = true)
        productId: Long
    ): ApiResponse<LikeV1Dto.LikeResponse>

    @Operation(
        summary = "좋아요 한 상품 목록 조회",
        description = "내가 좋아요 한 상품 목록을 조회합니다.",
    )
    fun getLikedProducts(
        @Parameter(description = "회원 ID (X-USER-ID)", required = true)
        memberId: String,
        @Parameter(description = "페이지 번호")
        page: Int,
        @Parameter(description = "페이지 크기")
        size: Int
    ): ApiResponse<Page<LikeV1Dto.LikedProductResponse>>
}
```

#### `interfaces/api/like/LikeV1Dto.kt`
```kotlin
package com.loopers.interfaces.api.like

import com.loopers.application.like.LikeInfo

class LikeV1Dto {

    data class LikeResponse(
        val productId: Long,
        val liked: Boolean
    )

    data class LikedProductResponse(
        val id: Long,
        val memberId: String,
        val productId: Long,
        val productName: String,
        val price: Long,
        val createdAt: String
    ) {
        companion object {
            fun from(info: LikeInfo): LikedProductResponse {
                return LikedProductResponse(
                    id = info.id,
                    memberId = info.memberId,
                    productId = info.product.id,
                    productName = info.product.name,
                    price = info.product.price.amount,
                    createdAt = info.createdAt
                )
            }
        }
    }
}
```

---

## 5. Order API 구현

### 📍 필요 API
- `POST /api/v1/orders` - 주문 생성 (쿠폰 포함)
- `GET /api/v1/orders` - 유저의 주문 목록 조회
- `GET /api/v1/orders/{orderId}` - 단일 주문 상세 조회

### 📂 파일 생성

#### `interfaces/api/order/OrderV1Controller.kt`
```kotlin
package com.loopers.interfaces.api.order

import com.loopers.application.order.CreateOrderRequest
import com.loopers.application.order.OrderFacade
import com.loopers.application.order.OrderItemRequest
import com.loopers.interfaces.api.ApiResponse
import jakarta.validation.Valid
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageRequest
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/v1/orders")
class OrderV1Controller(
    private val orderFacade: OrderFacade,
) : OrderV1ApiSpec {

    @PostMapping
    override fun createOrder(
        @RequestHeader("X-USER-ID") memberId: String,
        @Valid @RequestBody request: OrderV1Dto.CreateOrderRequest
    ): ApiResponse<OrderV1Dto.OrderResponse> {
        // 기존 CreateOrderRequest 활용 (application/order/OrderRequest.kt)
        val createOrderRequest = CreateOrderRequest(
            memberId = memberId,
            items = request.items.map { OrderItemRequest(it.productId, it.quantity) },
            couponId = request.couponId
        )

        return orderFacade.createOrder(createOrderRequest)
            .let { OrderV1Dto.OrderResponse.from(it) }
            .let { ApiResponse.success(it) }
    }

    @GetMapping
    override fun getOrders(
        @RequestHeader("X-USER-ID") memberId: String,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "20") size: Int
    ): ApiResponse<Page<OrderV1Dto.OrderResponse>> {
        val pageable = PageRequest.of(page, size)
        // OrderFacade에 getOrdersByMemberId 메서드 추가 필요
        return orderFacade.getOrdersByMemberId(memberId, pageable)
            .map { OrderV1Dto.OrderResponse.from(it) }
            .let { ApiResponse.success(it) }
    }

    @GetMapping("/{orderId}")
    override fun getOrder(
        @PathVariable orderId: Long
    ): ApiResponse<OrderV1Dto.OrderResponse> {
        // OrderFacade에 getOrder 메서드 추가 필요
        return orderFacade.getOrder(orderId)
            .let { OrderV1Dto.OrderResponse.from(it) }
            .let { ApiResponse.success(it) }
    }
}
```

> **참고**: `CreateOrderRequest`, `OrderItemRequest`는 이미 `application/order/OrderRequest.kt`에 정의되어 있습니다.

### 📝 OrderFacade에 추가 필요한 메서드
```kotlin
// application/order/OrderFacade.kt에 추가

fun getOrdersByMemberId(memberId: String, pageable: Pageable): Page<OrderInfo> {
    return orderService.getOrdersByMemberId(memberId, pageable)
        .map { OrderInfo.from(it) }
}

fun getOrder(orderId: Long): OrderInfo {
    return orderService.getOrder(orderId)
        .let { OrderInfo.from(it) }
}
```

> **참고**: `OrderService`에 이미 `getOrder(orderId)`, `getOrdersByMemberId(memberId, pageable)` 메서드가 존재합니다.

#### `interfaces/api/order/OrderV1ApiSpec.kt`
```kotlin
package com.loopers.interfaces.api.order

import com.loopers.interfaces.api.ApiResponse
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.Parameter
import io.swagger.v3.oas.annotations.tags.Tag
import org.springframework.data.domain.Page

@Tag(name = "Order V1 API", description = "주문 관련 API 입니다.")
interface OrderV1ApiSpec {
    @Operation(
        summary = "주문 생성",
        description = "상품을 주문합니다. 쿠폰을 적용할 수 있습니다.",
    )
    fun createOrder(
        @Parameter(description = "회원 ID", required = true)
        memberId: String,
        @Parameter(description = "주문 정보", required = true)
        request: OrderV1Dto.CreateOrderRequest
    ): ApiResponse<OrderV1Dto.OrderResponse>

    @Operation(
        summary = "주문 목록 조회",
        description = "내 주문 목록을 조회합니다.",
    )
    fun getOrders(
        @Parameter(description = "회원 ID", required = true)
        memberId: String,
        @Parameter(description = "페이지 번호")
        page: Int,
        @Parameter(description = "페이지 크기")
        size: Int
    ): ApiResponse<Page<OrderV1Dto.OrderResponse>>

    @Operation(
        summary = "주문 상세 조회",
        description = "주문 상세 정보를 조회합니다.",
    )
    fun getOrder(
        @Parameter(description = "주문 ID", required = true)
        orderId: Long
    ): ApiResponse<OrderV1Dto.OrderResponse>
}
```

#### `interfaces/api/order/OrderV1Dto.kt`
```kotlin
package com.loopers.interfaces.api.order

import com.loopers.application.order.OrderInfo
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.NotEmpty
import jakarta.validation.constraints.NotNull

class OrderV1Dto {

    data class CreateOrderRequest(
        @field:NotEmpty(message = "주문 상품은 최소 1개 이상이어야 합니다")
        val items: List<OrderItemRequest>,

        val couponId: Long? = null
    )

    data class OrderItemRequest(
        @field:NotNull(message = "상품 ID는 필수입니다")
        val productId: Long,

        @field:Min(value = 1, message = "수량은 1개 이상이어야 합니다")
        val quantity: Int
    )

    data class OrderResponse(
        val id: Long,
        val memberId: String,
        val status: String,
        val totalAmount: Long,
        val items: List<OrderItemResponse>,
        val createdAt: String
    ) {
        companion object {
            fun from(info: OrderInfo): OrderResponse {
                return OrderResponse(
                    id = info.id,
                    memberId = info.memberId,
                    status = info.status.name,
                    totalAmount = info.totalAmount,
                    items = info.items.map { OrderItemResponse.from(it) },
                    createdAt = info.createdAt
                )
            }
        }
    }

    data class OrderItemResponse(
        val id: Long,
        val productId: Long,
        val productName: String,
        val quantity: Int,
        val price: Long,
        val subtotal: Long
    ) {
        companion object {
            fun from(info: OrderItemInfo): OrderItemResponse {
                return OrderItemResponse(
                    id = info.id,
                    productId = info.productId,
                    productName = info.productName,
                    quantity = info.quantity,
                    price = info.price,
                    subtotal = info.subtotal
                )
            }
        }
    }
}
```

> **참고**: 기존 `OrderInfo`에는 `status: OrderStatus`, `totalAmount: Long`, `items: List<OrderItemInfo>` 필드가 있습니다.
> `OrderItemInfo`는 별도 클래스로 정의되어 있습니다 (application/order/OrderInfo.kt).

---

## 6. Coupon API 구현

### 📍 필요 API
- `POST /api/v1/coupons/{couponId}/issue` - 쿠폰 발급
- `GET /api/v1/coupons/me` - 내 쿠폰 목록 조회

### 📂 파일 생성

#### `interfaces/api/coupon/CouponV1Controller.kt`
```kotlin
package com.loopers.interfaces.api.coupon

import com.loopers.application.coupon.CouponFacade
import com.loopers.interfaces.api.ApiResponse
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/v1/coupons")
class CouponV1Controller(
    private val couponFacade: CouponFacade,
) : CouponV1ApiSpec {

    @PostMapping("/{couponId}/issue")
    override fun issueCoupon(
        @RequestHeader("X-USER-ID") memberId: String,
        @PathVariable couponId: Long
    ): ApiResponse<CouponV1Dto.CouponResponse> {
        return couponFacade.issueCoupon(memberId, couponId)
            .let { CouponV1Dto.CouponResponse.from(it) }
            .let { ApiResponse.success(it) }
    }

    @GetMapping("/me")
    override fun getMyCoupons(
        @RequestHeader("X-USER-ID") memberId: String
    ): ApiResponse<List<CouponV1Dto.CouponResponse>> {
        return couponFacade.getMemberCoupons(memberId)
            .map { CouponV1Dto.CouponResponse.from(it) }
            .let { ApiResponse.success(it) }
    }
}
```

#### `interfaces/api/coupon/CouponV1ApiSpec.kt`
```kotlin
package com.loopers.interfaces.api.coupon

import com.loopers.interfaces.api.ApiResponse
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.Parameter
import io.swagger.v3.oas.annotations.tags.Tag

@Tag(name = "Coupon V1 API", description = "쿠폰 관련 API 입니다.")
interface CouponV1ApiSpec {
    @Operation(
        summary = "쿠폰 발급",
        description = "회원에게 쿠폰을 발급합니다.",
    )
    fun issueCoupon(
        @Parameter(description = "회원 ID", required = true)
        memberId: String,
        @Parameter(description = "쿠폰 ID", required = true)
        couponId: Long
    ): ApiResponse<CouponV1Dto.CouponResponse>

    @Operation(
        summary = "내 쿠폰 목록 조회",
        description = "내가 보유한 쿠폰 목록을 조회합니다.",
    )
    fun getMyCoupons(
        @Parameter(description = "회원 ID", required = true)
        memberId: String
    ): ApiResponse<List<CouponV1Dto.CouponResponse>>
}
```

#### `interfaces/api/coupon/CouponV1Dto.kt`
```kotlin
package com.loopers.interfaces.api.coupon

import com.loopers.application.coupon.MemberCouponInfo

class CouponV1Dto {

    data class CouponResponse(
        val id: Long,
        val memberId: String,
        val couponId: Long,
        val couponName: String,
        val couponType: String,
        val discountAmount: Long?,
        val discountRate: Int?,
        val isUsed: Boolean,
        val createdAt: String
    ) {
        companion object {
            fun from(info: MemberCouponInfo): CouponResponse {
                return CouponResponse(
                    id = info.id,
                    memberId = info.memberId,
                    couponId = info.coupon.id,
                    couponName = info.coupon.name,
                    couponType = info.coupon.couponType.name,
                    discountAmount = info.coupon.discountAmount,
                    discountRate = info.coupon.discountRate,
                    isUsed = info.isUsed,
                    createdAt = info.createdAt
                )
            }
        }
    }
}
```

> **참고**: 기존 `MemberCouponInfo`와 `CouponInfo`가 `application/coupon/CouponInfo.kt`에 정의되어 있습니다.

### 📝 CouponFacade 생성 필요
```kotlin
// application/coupon/CouponFacade.kt

package com.loopers.application.coupon

import com.loopers.domain.coupon.CouponService
import org.springframework.stereotype.Component

@Component
class CouponFacade(
    private val couponService: CouponService,
) {
    fun issueCoupon(memberId: String, couponId: Long): MemberCouponInfo {
        val memberCoupon = couponService.issueCoupon(memberId, couponId)
        return MemberCouponInfo.from(memberCoupon)
    }

    fun getMemberCoupons(memberId: String): List<MemberCouponInfo> {
        return couponService.getMemberCoupons(memberId)
            .map { MemberCouponInfo.from(it) }
    }
}
```

### 📝 CouponService에 추가 필요한 메서드
```kotlin
// domain/coupon/CouponService.kt에 추가

@Transactional
fun issueCoupon(memberId: String, couponId: Long): MemberCoupon {
    val coupon = couponRepository.findByIdOrThrow(couponId)
    val memberCoupon = MemberCoupon.issue(memberId, coupon)
    return memberCouponRepository.save(memberCoupon)
}

@Transactional(readOnly = true)
fun getMemberCoupons(memberId: String): List<MemberCoupon> {
    return memberCouponRepository.findByMemberId(memberId)
}
```

---

## 📋 체크리스트

### 1. Member API (수정)

- [ ] `POST /api/v1/users/join` → `POST /api/v1/users` 경로 수정
- [ ] `GET /api/v1/users/me` 추가
- [ ] MemberV1ApiSpec에 `getMe()` 추가

### 2. Brand API (✅ 기존 코드 활용)

- [x] BrandFacade 존재 → `BrandInfo` 반환하도록 수정 완료
- [ ] BrandV1Controller - `@RequestMapping` 경로 수정 (`/api/v1/brands`)
- [ ] BrandV1Controller - `@GetMapping("/{brandId}")` 추가

### 3. Product API (✅ 기존 Facade 활용)

- [ ] ProductV1Controller 생성
- [ ] ProductV1ApiSpec 생성
- [ ] ProductV1Dto 생성
- [x] ProductFacade 메서드 존재 (`getProduct`, `getProducts`)

### 4. Like API (✅ 기존 Facade 활용)

- [ ] LikeV1Controller 생성
- [ ] LikeV1ApiSpec 생성
- [ ] LikeV1Dto 생성
- [x] LikeFacade 메서드 존재 (`addLike`, `cancelLike`, `getMyLikes`)

### 5. Order API (✅ 기존 Facade 부분 활용)

- [ ] OrderV1Controller 생성
- [ ] OrderV1ApiSpec 생성
- [ ] OrderV1Dto 생성
- [ ] OrderFacade에 `getOrder`, `getOrdersByMemberId` 메서드 추가
- [x] OrderInfo, OrderItemInfo 존재
- [x] CreateOrderRequest, OrderItemRequest 존재

### 6. Coupon API (신규 생성 필요)

- [ ] CouponV1Controller 생성
- [ ] CouponV1ApiSpec 생성
- [ ] CouponV1Dto 생성
- [ ] CouponFacade 생성
- [x] MemberCouponInfo, CouponInfo 존재
- [ ] CouponService에 `issueCoupon`, `getMemberCoupons` 메서드 추가

---

## 🔐 X-USER-ID 헤더 정책

> **모든 API는 별도의 인증 없이 X-USER-ID 헤더로 동작합니다.**

### X-USER-ID 헤더가 필요한 API (인증 필요)

| API | 메서드 | 설명 |
|-----|--------|------|
| `/api/v1/users/me` | GET | 내 정보 조회 |
| `/api/v1/points` | GET | 내 포인트 조회 |
| `/api/v1/points/charge` | POST | 내 포인트 충전 |
| `/api/v1/like/products/{productId}` | POST | 좋아요 등록 |
| `/api/v1/like/products/{productId}` | DELETE | 좋아요 취소 |
| `/api/v1/like/products` | GET | 내가 좋아요한 상품 목록 |
| `/api/v1/orders` | POST | 주문 생성 |
| `/api/v1/orders` | GET | 내 주문 목록 |
| `/api/v1/coupons/{couponId}/issue` | POST | 쿠폰 발급 |
| `/api/v1/coupons/me` | GET | 내 쿠폰 목록 |

### X-USER-ID 헤더가 필요 없는 API (공개)

| API | 메서드 | 설명 |
|-----|--------|------|
| `/api/v1/users` | POST | 회원가입 (인증 전) |
| `/api/v1/brands/{brandId}` | GET | 브랜드 조회 (공개 정보) |
| `/api/v1/products` | GET | 상품 목록 (공개 정보) |
| `/api/v1/products/{productId}` | GET | 상품 상세 (공개 정보) |
| `/api/v1/orders/{orderId}` | GET | 주문 상세 (주문 ID로 조회) |

### 헤더 형식
```
X-USER-ID: {회원가입 시 입력한 memberId}
```

예시:
```bash
curl -X GET http://localhost:8080/api/v1/users/me \
  -H "X-USER-ID: user123"
```

---

## ⚠️ 주의사항

1. **X-USER-ID 헤더** - 인증이 필요한 API는 반드시 X-USER-ID 헤더를 포함해야 합니다
2. **memberId 타입** - X-USER-ID 값은 `String` 타입입니다 (회원가입 시 입력한 ID)
3. **멱등성** - Like API는 같은 요청을 여러 번 해도 동일한 결과를 보장해야 합니다
4. **페이징** - 목록 조회 API는 모두 페이징을 지원합니다
5. **정렬** - Product 목록은 LATEST, PRICE_ASC, LIKES_DESC를 지원합니다
6. **트랜잭션** - 주문 API는 쿠폰/재고/포인트 처리가 모두 하나의 트랜잭션으로 처리되어야 합니다

---

## 🧪 테스트 시나리오

### 전체 플로우
1. 회원가입: `POST /api/v1/users`
2. 포인트 충전: `POST /api/v1/points/charge` (X-USER-ID 필요)
3. 상품 목록 조회: `GET /api/v1/products`
4. 상품 좋아요: `POST /api/v1/like/products/{productId}` (X-USER-ID 필요)
5. 쿠폰 발급: `POST /api/v1/coupons/{couponId}/issue` (X-USER-ID 필요)
6. 주문 생성: `POST /api/v1/orders` (X-USER-ID 필요, 쿠폰 포함)
7. 주문 목록 조회: `GET /api/v1/orders` (X-USER-ID 필요)
