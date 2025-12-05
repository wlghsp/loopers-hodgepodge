# 도메인 설계 가이드

## 📌 설계 원칙

이 프로젝트는 **도메인 주도 설계(DDD)** 원칙을 따릅니다.

### 핵심 원칙
1. **풍부한 도메인 모델**: 비즈니스 로직은 도메인 엔티티 내부에 위치
2. **불변성 보장**: VO(Value Object)는 불변 객체로 설계
3. **캡슐화**: 외부에서 직접 상태를 변경할 수 없도록 `protected set` 사용
4. **자기 검증**: 엔티티와 VO는 생성 시점에 유효성 검증
5. **명시적 메서드**: 상태 변경은 의미 있는 메서드명으로 표현

---

## 🏗️ 도메인 구조

### 1. 엔티티 (Entity)

**엔티티는 식별자(ID)를 가지며, 생명주기 동안 상태가 변경될 수 있는 객체입니다.**

#### 기본 구조

```kotlin
@Entity
@Table(name = "table_name")
class DomainEntity(
    // 생성자 매개변수로 필수 속성만 받기
    name: String,
    description: String?,
) : BaseEntity() {

    // 컬럼 매핑 + protected set으로 캡슐화
    @Column(name = "name", nullable = false, length = 100)
    var name: String = name
        protected set

    @Column(name = "description", columnDefinition = "TEXT")
    var description: String? = description
        protected set

    // 비즈니스 메서드로 상태 변경
    fun changeName(newName: String) {
        // 검증 로직
        if (newName.isBlank()) {
            throw CoreException(ErrorType.BAD_REQUEST, "이름은 필수입니다.")
        }
        this.name = newName
    }
}
```

#### 예시: Product 엔티티 패턴 분석

```kotlin
@Entity
@Table(name = "products")
class Product(
    name: String,
    description: String?,
    price: Money,          // VO 사용
    stock: Stock,          // VO 사용
    brand: Brand,          // 연관관계
) : BaseEntity() {

    @Column(name = "name", nullable = false, length = 200)
    var name: String = name
        protected set  // ✅ 외부에서 직접 변경 불가

    @Embedded
    @AttributeOverride(name = "amount", column = Column(name = "price", nullable = false))
    var price: Money = price
        protected set  // ✅ VO는 불변이지만, 교체는 protected

    @Embedded
    @AttributeOverride(name = "quantity", column = Column(name = "stock", nullable = false))
    var stock: Stock = stock
        protected set

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "brand_id", nullable = false)
    var brand: Brand = brand
        private set  // ✅ 브랜드는 변경 불가

    @Column(name = "likes_count", nullable = false)
    var likesCount: Int = 0
        protected set

    // ✅ 비즈니스 메서드로 상태 변경
    fun increaseLikesCount() {
        likesCount++
    }

    fun decreaseLikesCount() {
        if (likesCount > 0) likesCount--
    }

    // ✅ 검증 + 변경을 분리하여 제공
    fun validateStock(quantity: Quantity) {
        if (!hasEnoughStock(quantity)) {
            throw CoreException(
                ErrorType.INSUFFICIENT_STOCK,
                "재고가 부족합니다. 상품: $name"
            )
        }
    }

    fun decreaseStock(quantity: Quantity) {
        stock = stock.decrease(quantity.value)
    }

    // ✅ 조합 메서드도 제공 (편의성)
    fun decreaseStockWithValidation(quantity: Quantity) {
        validateStock(quantity)
        decreaseStock(quantity)
    }
}
```

---

### 2. 값 객체 (Value Object)

**값 객체는 식별자가 없으며, 값 자체로 동일성을 판단하는 불변 객체입니다.**

#### 기본 구조

```kotlin
@Embeddable
data class ValueObject(
    @Column(name = "field_name", nullable = false)
    val value: Type,  // ✅ val로 불변성 보장
) {
    init {
        // ✅ 생성 시점에 유효성 검증
        if (value < 0) {
            throw CoreException(ErrorType.BAD_REQUEST, "값은 0 이상이어야 합니다.")
        }
    }

    // ✅ 상태 변경이 필요하면 새 객체를 반환
    fun increase(amount: Type): ValueObject {
        return ValueObject(this.value + amount)
    }

    companion object {
        fun of(value: Type) = ValueObject(value)
        fun zero() = ValueObject(0)
    }
}
```

#### 예시: Money VO 패턴 분석

```kotlin
@Embeddable
data class Money(
    @Column(name = "amount", nullable = false)
    val amount: Long,  // ✅ val로 불변
) {
    init {
        // ✅ 생성 시점 검증
        if (amount < 0) {
            throw CoreException(
                ErrorType.INVALID_POINT_AMOUNT,
                "금액은 0이상이어야 합니다. 입력값: $amount"
            )
        }
    }

    // ✅ 새 객체 반환 (불변성 유지)
    fun plus(other: Money): Money = Money(this.amount + other.amount)

    fun minus(other: Money): Money {
        if (amount < other.amount) {
            throw CoreException(
                ErrorType.INVALID_POINT_AMOUNT,
                "금액이 부족합니다."
            )
        }
        return Money(this.amount - other.amount)
    }

    fun multiply(quantity: Int): Money {
        if (quantity < 0) {
            throw CoreException(
                ErrorType.INVALID_QUANTITY,
                "곱할 수량은 0 이상이어야 합니다."
            )
        }
        return Money(this.amount * quantity)
    }

    // ✅ 도메인 의미 있는 비교 메서드
    fun isGreaterThanOrEqual(other: Money): Boolean = this.amount >= other.amount

    companion object {
        fun of(amount: Long) = Money(amount)
        fun zero() = Money(0L)
    }
}
```

#### 예시: Stock VO 패턴 분석

```kotlin
@Embeddable
data class Stock(
    @Column(name = "stock", nullable = false)
    val quantity: Int,
) {
    init {
        if (quantity < 0) {
            throw CoreException(ErrorType.INVALID_STOCK)
        }
    }

    // ✅ 비즈니스 로직 포함
    fun decrease(amount: Int): Stock {
        if (amount <= 0) {
            throw CoreException(
                ErrorType.INVALID_STOCK,
                "차감할 수량은 0보다 커야 합니다."
            )
        }
        if (!hasEnough(amount)) {
            throw CoreException(
                ErrorType.INSUFFICIENT_STOCK,
                "재고가 부족합니다."
            )
        }
        return Stock(quantity - amount)  // ✅ 새 객체 반환
    }

    fun hasEnough(required: Int): Boolean = quantity >= required

    companion object {
        fun of(quantity: Int) = Stock(quantity)
        fun zero() = Stock(0)
    }
}
```

---

### 3. 연관관계 매핑

#### 다대일 (ManyToOne)

```kotlin
@Entity
class Product(
    brand: Brand,
) : BaseEntity() {

    @ManyToOne(fetch = FetchType.LAZY)  // ✅ 기본은 LAZY
    @JoinColumn(name = "brand_id", nullable = false)
    var brand: Brand = brand
        private set  // ✅ 연관관계는 생성 후 변경 불가
}
```

#### 일대다 (OneToMany)

```kotlin
@Entity
class Order(
    items: List<OrderItem> = emptyList(),
) : BaseEntity() {

    // ✅ protected mutable 컬렉션 + public immutable 접근자 패턴
    @OneToMany(
        mappedBy = "order",
        cascade = [CascadeType.ALL],
        orphanRemoval = true
    )
    protected val mutableItems: MutableList<OrderItem> = items.toMutableList()

    val items: List<OrderItem>
        get() = mutableItems.toList()  // ✅ 불변 리스트로 반환

    init {
        // ✅ 양방향 연관관계 설정
        items.forEach { it.assignOrder(this) }
    }

    // ✅ 비즈니스 메서드로만 추가
    fun addItem(item: OrderItem) {
        mutableItems.add(item)
        item.assignOrder(this)
    }
}
```

---

### 4. Enum 활용

**Enum은 단순한 상수 집합이 아니라, 타입별 비즈니스 로직을 담을 수 있는 강력한 도구입니다.**

#### 기본 Enum (비즈니스 로직 없음)

```kotlin
enum class CouponType(
    val description: String
) {
    FIXED_AMOUNT("정액 쿠폰"),
    PERCENTAGE("정률 쿠폰");
}
```

#### 고급 Enum (전략 패턴 - 비즈니스 로직 포함)

**타입별로 다른 로직이 필요한 경우, abstract 메서드를 활용하여 각 Enum 상수가 자신만의 구현을 갖도록 할 수 있습니다.**

```kotlin
enum class CouponType(val description: String) {
    FIXED_AMOUNT("정액 쿠폰") {
        override fun calculateDiscount(
            discountAmount: Long?,
            discountRate: Int?,
            orderAmount: Money
        ): Money {
            val discount = Money.of(discountAmount!!)
            return if (orderAmount.isGreaterThanOrEqual(discount)) {
                discount
            } else {
                orderAmount  // 주문 금액보다 큰 경우 주문 금액만큼만 할인
            }
        }

        override fun validate(discountAmount: Long?, discountRate: Int?) {
            if (discountAmount == null || discountAmount <= 0) {
                throw CoreException(
                    ErrorType.INVALID_COUPON_DISCOUNT,
                    "정액 쿠폰은 할인 금액이 필수입니다."
                )
            }
            if (discountRate != null) {
                throw CoreException(
                    ErrorType.INVALID_COUPON_DISCOUNT,
                    "정액 쿠폰은 할인율을 가질 수 없습니다."
                )
            }
        }
    },

    PERCENTAGE("정률 쿠폰") {
        override fun calculateDiscount(
            discountAmount: Long?,
            discountRate: Int?,
            orderAmount: Money
        ): Money {
            val rate = discountRate!!
            val discountValue = (orderAmount.amount * rate) / 100
            return Money.of(discountValue)
        }

        override fun validate(discountAmount: Long?, discountRate: Int?) {
            if (discountRate == null || discountRate !in 1..100) {
                throw CoreException(
                    ErrorType.INVALID_COUPON_DISCOUNT,
                    "정률 쿠폰은 1~100 사이의 할인율이 필수입니다."
                )
            }
            if (discountAmount != null) {
                throw CoreException(
                    ErrorType.INVALID_COUPON_DISCOUNT,
                    "정률 쿠폰은 할인 금액을 가질 수 없습니다."
                )
            }
        }
    };

    // ✅ 각 Enum 상수가 구현해야 하는 추상 메서드
    abstract fun calculateDiscount(
        discountAmount: Long?,
        discountRate: Int?,
        orderAmount: Money
    ): Money

    abstract fun validate(discountAmount: Long?, discountRate: Int?)
}
```

**장점:**
- ✅ **전략 패턴 구현**: 타입별 로직이 타입과 함께 위치
- ✅ **OCP 준수**: 새 타입 추가 시 Enum만 수정
- ✅ **테스트 용이**: Enum 단위로 독립적 테스트 가능
- ✅ **when 불필요**: 각 타입이 자신의 로직을 가짐
```

```kotlin
@Entity
class Coupon(
    couponType: CouponType,
) : BaseEntity() {

    @Enumerated(EnumType.STRING)  // ✅ STRING 사용 (ORDINAL X)
    @Column(name = "coupon_type", nullable = false, length = 20)
    var couponType: CouponType = couponType
        protected set
}
```

---

## 🎯 Coupon 도메인 설계 예시

### 1. Coupon 엔티티

```kotlin
@Entity
@Table(name = "coupons")
class Coupon(
    name: String,
    description: String?,
    couponType: CouponType,
    discountAmount: Long?,      // 정액 쿠폰용
    discountRate: Int?,         // 정률 쿠폰용
) : BaseEntity() {

    @Column(name = "name", nullable = false, length = 100)
    var name: String = name
        protected set

    @Column(name = "description", columnDefinition = "TEXT")
    var description: String? = description
        protected set

    @Enumerated(EnumType.STRING)
    @Column(name = "type", nullable = false, length = 20)
    var couponType: CouponType = couponType
        protected set

    @Column(name = "discount_amount")
    var discountAmount: Long? = discountAmount
        protected set

    @Column(name = "discount_rate")
    var discountRate: Int? = discountRate
        protected set

    init {
        validateCouponFields()
    }

    override fun guard() {
        validateCouponFields()
    }

    // ✅ 검증 로직을 CouponType에 위임
    private fun validateCouponFields() {
        couponType.validate(discountAmount, discountRate)
    }

    // ✅ 할인 계산 로직을 CouponType에 위임
    fun calculateDiscount(orderAmount: Money): Money {
        return couponType.calculateDiscount(discountAmount, discountRate, orderAmount)
    }
}
```

### 2. MemberCoupon 엔티티 (사용자-쿠폰 매핑)

```kotlin
@Entity
@Table(
    name = "member_coupons",
    indexes = [
        Index(name = "idx_member_coupon", columnList = "member_id, coupon_id"),
        Index(name = "idx_member_used", columnList = "member_id, used_at")
    ]
)
class MemberCoupon(
    memberId: String,
    coupon: Coupon,
) : BaseEntity() {

    @Column(name = "member_id", nullable = false, length = 50)
    var memberId: String = memberId
        protected set

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "coupon_id", nullable = false)
    var coupon: Coupon = coupon
        protected set

    @Column(name = "used_at")
    var usedAt: ZonedDateTime? = null
        protected set

    // ✅ 비즈니스 메서드: 쿠폰 사용 가능 여부 확인
    fun canUse(): Boolean {
        return usedAt == null && deletedAt == null
    }

    // ✅ 비즈니스 메서드: 쿠폰 사용 처리
    fun use() {
        if (!canUse()) {
            throw CoreException(
                ErrorType.COUPON_ALREADY_USED,
                "이미 사용된 쿠폰입니다. 쿠폰 ID: ${coupon.id}"
            )
        }
        this.usedAt = ZonedDateTime.now()
    }

    // ✅ 할인 금액 계산 위임
    fun calculateDiscount(orderAmount: Money): Money {
        return coupon.calculateDiscount(orderAmount)
    }

    companion object {
        fun issue(memberId: String, coupon: Coupon): MemberCoupon {
            return MemberCoupon(memberId, coupon)
        }
    }
}
```

### 3. CouponType Enum (전략 패턴)

```kotlin
enum class CouponType(val description: String) {
    FIXED_AMOUNT("정액 쿠폰") {
        override fun calculateDiscount(
            discountAmount: Long?,
            discountRate: Int?,
            orderAmount: Money
        ): Money {
            val discount = Money.of(discountAmount!!)
            return if (orderAmount.isGreaterThanOrEqual(discount)) {
                discount
            } else {
                orderAmount  // 주문 금액보다 큰 경우 주문 금액만큼만 할인
            }
        }

        override fun validate(discountAmount: Long?, discountRate: Int?) {
            if (discountAmount == null || discountAmount <= 0) {
                throw CoreException(
                    ErrorType.INVALID_COUPON_DISCOUNT,
                    "정액 쿠폰은 할인 금액이 필수입니다."
                )
            }
            if (discountRate != null) {
                throw CoreException(
                    ErrorType.INVALID_COUPON_DISCOUNT,
                    "정액 쿠폰은 할인율을 가질 수 없습니다."
                )
            }
        }
    },

    PERCENTAGE("정률 쿠폰") {
        override fun calculateDiscount(
            discountAmount: Long?,
            discountRate: Int?,
            orderAmount: Money
        ): Money {
            val rate = discountRate!!
            val discountValue = (orderAmount.amount * rate) / 100
            return Money.of(discountValue)
        }

        override fun validate(discountAmount: Long?, discountRate: Int?) {
            if (discountRate == null || discountRate !in 1..100) {
                throw CoreException(
                    ErrorType.INVALID_COUPON_DISCOUNT,
                    "정률 쿠폰은 1~100 사이의 할인율이 필수입니다."
                )
            }
            if (discountAmount != null) {
                throw CoreException(
                    ErrorType.INVALID_COUPON_DISCOUNT,
                    "정률 쿠폰은 할인 금액을 가질 수 없습니다."
                )
            }
        }
    };

    // ✅ 각 Enum 상수가 구현해야 하는 추상 메서드
    abstract fun calculateDiscount(
        discountAmount: Long?,
        discountRate: Int?,
        orderAmount: Money
    ): Money

    abstract fun validate(discountAmount: Long?, discountRate: Int?)
}
```

**이렇게 설계하면:**
- ✅ 타입별 로직이 타입과 함께 관리됨
- ✅ 새로운 쿠폰 타입 추가 시 Coupon 엔티티 수정 불필요
- ✅ 각 타입을 독립적으로 테스트 가능
- ✅ OCP(개방-폐쇄 원칙) 준수
```

---

## ✅ 도메인 설계 체크리스트

### 엔티티 설계
- [ ] `BaseEntity`를 상속받았는가?
- [ ] 생성자는 필수 필드만 받는가?
- [ ] 모든 필드에 `protected set` 또는 `private set`을 적용했는가?
- [ ] `@Column` 어노테이션에 적절한 제약조건(`nullable`, `length` 등)을 지정했는가?
- [ ] 연관관계는 `FetchType.LAZY`를 사용하는가?
- [ ] 비즈니스 로직은 엔티티 내부 메서드로 구현했는가?

### 값 객체 설계
- [ ] `@Embeddable` 어노테이션을 사용했는가?
- [ ] `data class`로 선언했는가?
- [ ] 모든 필드를 `val`로 선언했는가?
- [ ] `init` 블록에서 유효성 검증을 수행하는가?
- [ ] 상태 변경 시 새 객체를 반환하는가?
- [ ] `companion object`에 팩토리 메서드를 제공하는가?

### 연관관계 설계
- [ ] `@ManyToOne`은 `FetchType.LAZY`를 사용하는가?
- [ ] `@OneToMany`는 `cascade`와 `orphanRemoval` 설정이 적절한가?
- [ ] 양방향 연관관계는 편의 메서드로 동기화하는가?
- [ ] 컬렉션은 `protected mutable` + `public immutable` 패턴을 사용하는가?

### Enum 설계
- [ ] `@Enumerated(EnumType.STRING)`을 사용하는가? (ORDINAL 금지)
- [ ] Enum 필드에 적절한 `length`를 지정했는가?
- [ ] Enum에 비즈니스 로직을 포함할 수 있는가?

### 유효성 검증
- [ ] 생성자 또는 `init` 블록에서 필수 검증을 수행하는가?
- [ ] `guard()` 메서드를 오버라이드하여 추가 검증을 수행하는가?
- [ ] 비즈니스 예외는 `CoreException`을 사용하는가?
- [ ] 예외 메시지는 명확하고 구체적인가?

---

## 🚫 안티패턴

### ❌ 나쁜 예시

```kotlin
@Entity
class BadEntity : BaseEntity() {
    // ❌ nullable 필드를 lateinit으로 선언
    @Column(name = "name")
    lateinit var name: String

    // ❌ public setter
    @Column(name = "price")
    var price: Long = 0

    // ❌ 비즈니스 로직이 없는 빈약한 도메인 모델
}

// ❌ Service에서 도메인 로직 처리
class BadService {
    fun updatePrice(entity: BadEntity, newPrice: Long) {
        if (newPrice < 0) {
            throw Exception("가격은 0 이상이어야 합니다.")
        }
        entity.price = newPrice  // 직접 setter 사용
    }
}
```

### ✅ 좋은 예시

```kotlin
@Entity
class GoodEntity(
    name: String,
    price: Money,
) : BaseEntity() {
    // ✅ 생성자로 필수 필드 받기
    @Column(name = "name", nullable = false, length = 100)
    var name: String = name
        protected set

    // ✅ VO 사용
    @Embedded
    @AttributeOverride(name = "amount", column = Column(name = "price"))
    var price: Money = price
        protected set

    // ✅ 비즈니스 메서드로 상태 변경
    fun changePrice(newPrice: Money) {
        // 검증 로직은 Money VO의 init 블록에서 처리됨
        this.price = newPrice
    }
}

// ✅ Service는 도메인 메서드 호출만
class GoodService {
    fun updatePrice(entity: GoodEntity, newPrice: Long) {
        val money = Money.of(newPrice)  // VO 생성 시 검증
        entity.changePrice(money)       // 도메인 메서드 호출
    }
}
```

---

## 💡 핵심 요약

1. **엔티티는 풍부한 도메인 모델** - 비즈니스 로직을 엔티티 내부에 구현
2. **값 객체는 불변** - `val` + 새 객체 반환 패턴
3. **캡슐화** - `protected set` / `private set` 사용
4. **자기 검증** - 생성 시점에 유효성 검증
5. **명시적 메서드** - `setName()` ❌ → `changeName()` ✅
6. **연관관계는 LAZY** - 성능 최적화
7. **컬렉션은 불변 반환** - 외부에서 직접 수정 방지
8. **Enum은 STRING** - `ORDINAL` 사용 금지

---

이 가이드를 따라 **Coupon**, **MemberCoupon** 도메인을 구현하면 일관성 있고 유지보수하기 좋은 코드를 작성할 수 있습니다! 🚀
