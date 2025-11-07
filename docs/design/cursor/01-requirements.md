# 01. 요구사항 명세서

## 1. 프로젝트 개요

### 1.1 배경
**좋아요** 누르고, **쿠폰** 쓰고, 포인트로 **결제**하는 **감성 이커머스**.

내가 좋아하는 브랜드의 상품들을 한 번에 담아 주문하고, 유저 행동은 랭킹과 추천으로 연결됩니다.

### 1.2 설계 범위 (2주차)
- ✅ 상품 목록 / 상품 상세 / 브랜드 조회
- ✅ 상품 좋아요 등록/취소 (멱등 동작)
- ✅ 주문 생성 및 결제 흐름 (재고 차감, 포인트 차감, 외부 시스템 연동)

### 1.3 제외 도메인
- ❌ 회원가입, 포인트 충전 (1주차 구현 완료 기준)
- ❌ 쿠폰 기능
- ❌ 배송 관리
- ❌ 주문 취소/환불
- ❌ 상품 리뷰

### 1.4 전제 조건
- 회원가입이 완료되어 있음
- 포인트가 충전되어 있음
- 브랜드 및 상품 데이터는 사전 등록되어 있음
- 인증/인가는 `X-USER-ID` 헤더로 사용자 식별

---

## 2. 유저 스토리

### [US-1] 상품 탐색 및 브랜드 필터링
**As a** 사용자  
**I want to** 여러 브랜드의 상품을 둘러보고 필터링하고 싶다  
**So that** 마음에 드는 상품을 쉽게 찾을 수 있다

**Main Flow:**
1. 사용자가 상품 목록 조회 API 호출
2. 브랜드별 필터링 옵션 적용 (선택사항)
3. 정렬 기준 선택 (최신순/가격순/좋아요순)
4. 페이지네이션된 상품 목록 확인
5. 각 상품의 좋아요 수 확인
6. 관심 상품 클릭 → 상품 상세 조회
7. 브랜드 정보 별도 조회 가능

**Acceptance Criteria:**
- 상품 목록은 페이지네이션되어 반환된다 (기본 20개)
- 브랜드 ID로 필터링이 가능하다
- 각 상품에 총 좋아요 수가 표시된다
- 정렬 기준: `latest` (필수), `price_asc`, `likes_desc` (선택)
- 상품 상세에는 브랜드 정보가 포함된다

**비기능 요구사항:**
- 상품 목록 조회 응답시간: 200ms 이하
- 대용량 데이터 처리를 위한 페이지네이션

---

### [US-2] 상품 좋아요 등록/취소
**As a** 사용자  
**I want to** 마음에 드는 상품에 좋아요를 누르고 취소할 수 있다  
**So that** 나중에 관심 상품을 다시 찾아볼 수 있다

**Main Flow (좋아요 등록):**
1. 사용자가 상품 상세 페이지에서 좋아요 버튼 클릭
2. POST `/api/v1/like/products/{productId}` 호출
3. 시스템이 해당 사용자의 좋아요 존재 여부 확인
4. 좋아요가 없으면 저장
5. 좋아요가 이미 있으면 추가 저장하지 않음 (멱등성)
6. 상품의 좋아요 수 증가 (중복 시 증가하지 않음)
7. 성공 응답 및 현재 좋아요 수 반환

**Alternate Flow (좋아요 취소):**
1. 사용자가 좋아요 취소 버튼 클릭
2. DELETE `/api/v1/like/products/{productId}` 호출
3. 시스템이 해당 사용자의 좋아요 존재 여부 확인
4. 좋아요가 있으면 삭제
5. 좋아요가 없어도 성공 응답 (멱등성)
6. 상품의 좋아요 수 감소 (없을 시 감소하지 않음)
7. 성공 응답 및 현재 좋아요 수 반환

**Alternate Flow (내가 좋아요한 상품 목록):**
1. 사용자가 내 좋아요 목록 조회
2. GET `/api/v1/like/products` 호출
3. 페이지네이션된 좋아요 상품 목록 반환
4. 각 상품의 정보 및 좋아요 누른 일시 포함

**Acceptance Criteria:**
- 사용자는 각 상품에 **한 번만** 좋아요를 누를 수 있다
- 좋아요 등록/취소는 **멱등하게** 동작한다
- 상품 목록 및 상품 상세 조회 시 **총 좋아요 수**를 표기한다
- 동시 요청 시에도 좋아요 수 정합성이 유지된다

**비기능 요구사항:**
- 좋아요 등록/취소 응답시간: 100ms 이하
- DB 제약조건으로 중복 방지 (UNIQUE INDEX)
- 동시성 제어 적용

---

### [US-3] 주문 생성 및 결제
**As a** 사용자  
**I want to** 여러 상품을 한 번에 주문하고 포인트로 결제하고 싶다  
**So that** 원하는 상품들을 구매할 수 있다

**Main Flow:**
1. 사용자가 장바구니에서 여러 상품과 수량 선택
2. POST `/api/v1/orders` 호출 (상품ID, 수량 리스트)
3. **재고 확인**: 각 상품의 재고가 충분한지 검증
4. **총 금액 계산**: 상품 가격 × 수량의 합계
5. **포인트 확인**: 사용자의 포인트 잔액이 충분한지 검증
6. **트랜잭션 시작**
   - 재고 차감
   - 포인트 차감
   - 주문 정보 저장
7. **외부 시스템 전송**: 주문 정보를 외부 시스템에 전송 (Mock 처리 가능)
8. 외부 시스템 성공 시 트랜잭션 커밋
9. 주문 완료 응답 반환

**Exception Flow:**
- **재고 부족**: `400 Bad Request` "재고가 부족합니다"
- **포인트 부족**: `400 Bad Request` "포인트가 부족합니다"
- **외부 시스템 실패**: 트랜잭션 롤백, `500 Internal Server Error`

**Acceptance Criteria:**
- 재고와 포인트가 **원자적으로** 차감된다
- 동시 주문 시 정합성이 보장된다 (동시성 제어)
- 외부 시스템 실패 시 모든 변경사항이 롤백된다
- 주문 상태는 `PENDING` → `COMPLETED` 또는 `FAILED`로 변경

**비기능 요구사항:**
- 주문 생성 응답시간: 500ms 이하
- 트랜잭션 ACID 보장
- 재고/포인트 차감 시 비관적 락 적용

---

### [US-4] 주문 내역 조회
**As a** 사용자  
**I want to** 내 주문 내역을 확인하고 싶다  
**So that** 주문 상태와 상세 정보를 확인할 수 있다

**Main Flow (주문 목록):**
1. 사용자가 주문 내역 페이지 접근
2. GET `/api/v1/orders` 호출
3. 해당 사용자의 주문 목록 반환 (페이지네이션)
4. 각 주문의 요약 정보 표시 (주문ID, 상태, 총액, 주문일시)

**Alternate Flow (주문 상세):**
1. 사용자가 특정 주문 클릭
2. GET `/api/v1/orders/{orderId}` 호출
3. 주문 상세 정보 반환 (주문 상품, 수량, 가격, 상태)

**Acceptance Criteria:**
- 본인의 주문만 조회 가능 (X-USER-ID로 필터링)
- 주문 목록은 페이지네이션되어 반환
- 주문 상세에는 주문 상품, 수량, 금액, 상태 포함

---

## 3. 유비쿼터스 언어

### 3.1 도메인 용어

| 한글 | 영문 | 설명 |
|------|------|------|
| 상품 | Product | 판매되는 개별 상품 |
| 브랜드 | Brand | 상품을 제공하는 브랜드 |
| 좋아요 | Like | 사용자가 상품에 표시하는 관심 표현 |
| 주문 | Order | 사용자가 상품을 구매하기 위해 생성하는 거래 |
| 주문 아이템 | OrderItem | 주문에 포함된 개별 상품과 수량 |
| 재고 | Stock | 상품의 판매 가능 수량 |
| 회원 | Member | 서비스에 가입한 사용자 (1주차 완료) |
| 포인트 | Point | 사용자가 보유한 결제 수단 (1주차 완료) |

### 3.2 상태 값 정의

**주문 상태 (OrderStatus)**
- `PENDING`: 주문 생성, 결제 대기
- `COMPLETED`: 결제 완료
- `FAILED`: 주문 실패
- `CANCELLED`: 사용자 취소 (향후 확장)

---

## 4. API 명세

### 4.1 상품 & 브랜드

#### GET `/api/v1/products`
상품 목록 조회

**Query Parameters:**
- `brandId` (Long, optional): 특정 브랜드의 상품만 필터링
- `sort` (String, optional): 정렬 기준
  - `latest`: 최신순 (필수 구현)
  - `price_asc`: 가격 낮은순 (선택 구현)
  - `likes_desc`: 좋아요 많은순 (선택 구현)
- `page` (Integer, optional, default=0): 페이지 번호
- `size` (Integer, optional, default=20): 페이지당 상품 수

**Response:**
```json
{
  "content": [
    {
      "id": 1,
      "name": "감성 티셔츠",
      "price": 29000,
      "stock": 50,
      "brandId": 1,
      "brandName": "감성브랜드",
      "likesCount": 42,
      "createdAt": "2025-11-01T10:00:00"
    },
    {
      "id": 2,
      "name": "감성 후드",
      "price": 49000,
      "stock": 30,
      "brandId": 1,
      "brandName": "감성브랜드",
      "likesCount": 58,
      "createdAt": "2025-11-02T14:00:00"
    }
  ],
  "pageable": {
    "pageNumber": 0,
    "pageSize": 20,
    "totalPages": 5,
    "totalElements": 100
  }
}
```

---

#### GET `/api/v1/products/{productId}`
상품 상세 조회

**Path Parameters:**
- `productId` (Long, required): 상품 ID

**Response:**
```json
{
  "id": 1,
  "name": "감성 티셔츠",
  "description": "편안한 착용감의 감성 티셔츠입니다. 데일리룩으로 완벽해요.",
  "price": 29000,
  "stock": 50,
  "brand": {
    "id": 1,
    "name": "감성브랜드",
    "description": "감성을 담은 브랜드"
  },
  "likesCount": 42,
  "createdAt": "2025-11-01T10:00:00"
}
```

**Error Response:**
- `404 Not Found`: 상품이 존재하지 않음

---

#### GET `/api/v1/brands/{brandId}`
브랜드 정보 조회

**Path Parameters:**
- `brandId` (Long, required): 브랜드 ID

**Response:**
```json
{
  "id": 1,
  "name": "감성브랜드",
  "description": "감성을 담은 브랜드입니다. 일상의 특별함을 전합니다.",
  "createdAt": "2025-11-01T09:00:00"
}
```

**Error Response:**
- `404 Not Found`: 브랜드가 존재하지 않음

---

### 4.2 좋아요

#### POST `/api/v1/like/products/{productId}`
상품 좋아요 등록 (멱등)

**Headers:**
- `X-USER-ID` (String, required): 사용자 ID

**Path Parameters:**
- `productId` (Long, required): 상품 ID

**Response:**
```json
{
  "success": true,
  "message": "좋아요가 등록되었습니다.",
  "likesCount": 43
}
```

**멱등성:**
- 이미 좋아요가 등록된 상태에서 다시 요청하면 추가 등록하지 않고 동일한 응답 반환
- 좋아요 수는 중복 증가하지 않음

**Error Response:**
- `404 Not Found`: 상품이 존재하지 않음

---

#### DELETE `/api/v1/like/products/{productId}`
상품 좋아요 취소 (멱등)

**Headers:**
- `X-USER-ID` (String, required): 사용자 ID

**Path Parameters:**
- `productId` (Long, required): 상품 ID

**Response:**
```json
{
  "success": true,
  "message": "좋아요가 취소되었습니다.",
  "likesCount": 42
}
```

**멱등성:**
- 좋아요가 존재하지 않는 상태에서 취소 요청해도 성공 응답 반환
- 좋아요 수는 중복 감소하지 않음

---

#### GET `/api/v1/like/products`
내가 좋아요한 상품 목록 조회

**Headers:**
- `X-USER-ID` (String, required): 사용자 ID

**Query Parameters:**
- `page` (Integer, optional, default=0)
- `size` (Integer, optional, default=20)

**Response:**
```json
{
  "content": [
    {
      "productId": 1,
      "productName": "감성 티셔츠",
      "price": 29000,
      "brandName": "감성브랜드",
      "likesCount": 42,
      "likedAt": "2025-11-02T14:30:00"
    },
    {
      "productId": 5,
      "productName": "모던 셔츠",
      "price": 39000,
      "brandName": "모던브랜드",
      "likesCount": 28,
      "likedAt": "2025-11-03T16:20:00"
    }
  ],
  "pageable": {
    "pageNumber": 0,
    "pageSize": 20,
    "totalPages": 2,
    "totalElements": 35
  }
}
```

---

### 4.3 주문

#### POST `/api/v1/orders`
주문 생성

**Headers:**
- `X-USER-ID` (String, required): 사용자 ID

**Request:**
```json
{
  "items": [
    { "productId": 1, "quantity": 2 },
    { "productId": 3, "quantity": 1 }
  ]
}
```

**Response:**
```json
{
  "orderId": 1001,
  "userId": "user123",
  "status": "COMPLETED",
  "totalAmount": 87000,
  "usedPoints": 87000,
  "items": [
    {
      "productId": 1,
      "productName": "감성 티셔츠",
      "quantity": 2,
      "price": 29000,
      "subtotal": 58000
    },
    {
      "productId": 3,
      "productName": "감성 후드",
      "quantity": 1,
      "price": 29000,
      "subtotal": 29000
    }
  ],
  "orderedAt": "2025-11-05T16:45:00"
}
```

**처리 흐름:**
1. 상품 재고 확인
2. 포인트 잔액 확인
3. 트랜잭션 시작
   - 재고 차감
   - 포인트 차감
   - 주문 정보 저장
4. 외부 시스템 전송 (Mock 처리 가능)
5. 트랜잭션 커밋 또는 롤백

**Error Response:**
- `400 Bad Request`: 재고 부족 / 포인트 부족
- `404 Not Found`: 상품이 존재하지 않음
- `500 Internal Server Error`: 외부 시스템 실패 (트랜잭션 롤백)

---

#### GET `/api/v1/orders`
유저의 주문 목록 조회

**Headers:**
- `X-USER-ID` (String, required): 사용자 ID

**Query Parameters:**
- `page` (Integer, optional, default=0)
- `size` (Integer, optional, default=20)

**Response:**
```json
{
  "content": [
    {
      "orderId": 1001,
      "status": "COMPLETED",
      "totalAmount": 87000,
      "itemCount": 3,
      "orderedAt": "2025-11-05T16:45:00"
    },
    {
      "orderId": 1002,
      "status": "COMPLETED",
      "totalAmount": 49000,
      "itemCount": 1,
      "orderedAt": "2025-11-04T12:20:00"
    }
  ],
  "pageable": {
    "pageNumber": 0,
    "pageSize": 20,
    "totalPages": 1,
    "totalElements": 5
  }
}
```

---

#### GET `/api/v1/orders/{orderId}`
단일 주문 상세 조회

**Headers:**
- `X-USER-ID` (String, required): 사용자 ID

**Path Parameters:**
- `orderId` (Long, required): 주문 ID

**Response:**
```json
{
  "orderId": 1001,
  "userId": "user123",
  "status": "COMPLETED",
  "totalAmount": 87000,
  "items": [
    {
      "productId": 1,
      "productName": "감성 티셔츠",
      "quantity": 2,
      "price": 29000,
      "subtotal": 58000
    },
    {
      "productId": 3,
      "productName": "감성 후드",
      "quantity": 1,
      "price": 29000,
      "subtotal": 29000
    }
  ],
  "orderedAt": "2025-11-05T16:45:00"
}
```

**Error Response:**
- `404 Not Found`: 주문이 존재하지 않음
- `403 Forbidden`: 본인의 주문이 아님

---

## 5. 비기능 요구사항

### 5.1 성능 요구사항
- 상품 목록 조회: **200ms 이하**
- 상품 상세 조회: **100ms 이하**
- 좋아요 등록/취소: **100ms 이하**
- 주문 생성: **500ms 이하**

### 5.2 정합성 보장
- **재고 차감**: 동시성 제어 (비관적 락 적용)
- **포인트 차감**: 동시성 제어 (비관적 락 적용)
- **주문 처리**: ACID 트랜잭션 보장
- **외부 시스템 실패**: 전체 롤백

### 5.3 멱등성 보장
- **좋아요 등록**: 중복 등록 방지 (DB UNIQUE 제약조건)
- **좋아요 취소**: 존재하지 않아도 성공 응답
- POST/DELETE 요청이 중복 발생해도 동일한 결과

### 5.4 확장성
- 페이지네이션으로 대용량 데이터 처리
- 인덱스 전략으로 조회 성능 확보
- 비정규화를 통한 조회 성능 최적화 (좋아요 수)

---

## 6. 제약사항

### 6.1 인증/인가
- 실제 인증/인가는 구현하지 않음
- `X-USER-ID` 헤더로 사용자 식별
- 헤더 값은 1주차에 회원가입 시 등록한 ID

### 6.2 데이터 가정
- 회원가입은 1주차에 완료되어 있음
- 포인트 충전은 1주차에 완료되어 있음
- 브랜드 데이터는 사전 등록되어 있음
- 상품 데이터는 사전 등록되어 있음

### 6.3 외부 시스템 연동
- 주문 정보 외부 시스템 전송은 Mock으로 처리 가능
- 실패 시 Exception 발생하여 트랜잭션 롤백

### 6.4 향후 확장 고려
- 유저 행동 데이터 수집 (랭킹, 추천)
- 쿠폰 기능
- 배송 관리
- 주문 취소/환불
- 상품 리뷰

---

## 7. 구현 우선순위

### Phase 1: 조회 기능 (Week 2 - Day 1~2)
1. 브랜드 조회
2. 상품 목록 조회 (페이지네이션, 브랜드 필터링, 최신순 정렬)
3. 상품 상세 조회

### Phase 2: 좋아요 기능 (Week 2 - Day 3~4)
1. 좋아요 등록 (멱등성 보장)
2. 좋아요 취소 (멱등성 보장)
3. 내가 좋아요한 상품 목록 조회
4. 상품 조회 시 좋아요 수 표시

### Phase 3: 주문 기능 (Week 2 - Day 5~7)
1. 주문 생성 (재고/포인트 차감, 외부 시스템 연동)
2. 주문 목록 조회
3. 주문 상세 조회
4. 동시성 제어 (재고/포인트)

### Phase 4: 최적화 (향후)
1. 성능 최적화 (인덱스, 쿼리 튜닝)
2. 상품 정렬 추가 (가격순, 좋아요순)
3. 동시 주문 테스트 및 개선

---

## 8. 검증 체크리스트

### 8.1 기능 검증
- [ ] 상품/브랜드/좋아요/주문 도메인이 모두 포함되어 있는가?
- [ ] 기능 요구사항이 유저 중심으로 정리되어 있는가?
- [ ] 멱등성이 보장되는가?
- [ ] 동시성 제어가 적용되었는가?
- [ ] 페이지네이션이 적용되었는가?

### 8.2 설계 검증
- [ ] 시퀀스 다이어그램에서 책임 객체가 드러나는가?
- [ ] 클래스 구조가 도메인 설계를 잘 표현하고 있는가?
- [ ] ERD 설계 시 데이터 정합성을 고려하여 구성하였는가?
- [ ] API 명세가 명확하게 정의되어 있는가?

### 8.3 비기능 검증
- [ ] 트랜잭션 경계가 명확한가?
- [ ] 예외 상황이 적절히 처리되는가?
- [ ] 성능 요구사항을 충족할 수 있는가?
- [ ] 확장 가능한 구조인가?

---

## 9. 참고사항

- 포인트 사용은 주문 과정에서 자동으로 처리되며, 별도의 사용 API는 제공되지 않습니다
- 외부 시스템 연동은 Mock으로 처리하며, 실패 시나리오도 테스트 가능해야 합니다
- 모든 기능의 동작을 개발한 후에 동시성, 멱등성, 일관성, 느린 조회, 동시 주문 등 실제 서비스에서 발생하는 문제들을 해결하게 됩니다
