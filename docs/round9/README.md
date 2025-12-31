# 🎯 Round 9 구현 가이드 - Redis ZSET 랭킹 시스템

> **목표**: Kafka 이벤트를 소비하여 Redis ZSET에 실시간 랭킹을 구축하고, API로 제공합니다.

---

## 📚 개요

이 가이드는 **Redis ZSET 기반 실시간 랭킹 시스템**을 구현하는 완전한 단계별 가이드입니다.

### 🎯 학습 목표

1. **Redis ZSET 활용**: 정렬된 집합 자료구조로 효율적인 랭킹 관리
2. **시간의 양자화**: 일별 키 전략으로 신선한 랭킹 유지
3. **가중치 기반 점수**: 비즈니스 가치를 반영한 공정한 랭킹
4. **멱등성 보장**: Round 8에서 배운 내용 적용 (event_handled 테이블)
5. **상품 정보 Aggregation**: 사용자 경험을 고려한 API 설계

---

## 🏗️ 시스템 아키텍처

```
[commerce-api]
    ↓ 이벤트 발행 (Kafka Producer)
[Kafka Topics: catalog-events, order-events]
    ↓ 이벤트 소비 (독립적인 Consumer Groups)
    ├─→ [MetricsConsumer] → DB (product_metrics)
    └─→ [RankingConsumer] → Redis ZSET (ranking:all:20251222)
                               ↓
                          [RankingAPI]
                               ↓
                          [사용자]
```

---

## 📖 구현 단계 목차

구현은 총 5단계로 진행됩니다. 각 단계는 독립적인 문서로 제공됩니다.

### [Step 1: 기반 인프라 및 유틸리티 구축](./STEP1_FOUNDATION.md)
**목표**: Redis ZSET 연산을 위한 핵심 도메인 로직 구현

**구현 내용**:
- `RankingKeyGenerator`: 날짜별 키 생성 (`ranking:all:20251222`)
- `RankingScoreCalculator`: 가중치 기반 점수 계산 (조회 0.1, 좋아요 0.2, 주문 0.6 × ln)
- `RankingService`: Redis ZSET 연산 캡슐화 (ZINCRBY, ZREVRANGE, ZREVRANK)

**핵심 개념**:
- 왜 키 전략이 중요한가? (시간의 양자화, 롱테일 방지)
- 왜 가중치가 필요한가? (비즈니스 가치 반영)
- 왜 로그 정규화를 사용하는가? (고가 상품 독식 방지)

---

### [Step 2: Kafka Consumer 구현](./STEP2_KAFKA_CONSUMER.md)
**목표**: Kafka 이벤트를 소비하여 Redis ZSET에 실시간 적재

**구현 내용**:
- `RankingEventFacade`: 배치 이벤트 처리 + 멱등성 보장
- `RankingKafkaConsumer`: 배치 리스너로 성능 최적화

**핵심 개념**:
- 왜 별도의 Consumer를 만드는가? (관심사 분리, 장애 격리)
- 왜 배치 리스너를 사용하는가? (Redis 연산 횟수 최소화)
- 멱등성은 어떻게 보장하는가? (event_handled 테이블)

---

### [Step 3: Ranking API 구현](./STEP3_RANKING_API.md)
**목표**: Redis ZSET 데이터를 조회하는 API 구현

**구현 내용**:
- `RankingFacade`: 랭킹 조회 + 상품 정보 Aggregation
- `RankingV1Controller`: GET /api/v1/rankings
- `RankingV1Dto`: 응답 DTO

**핵심 개념**:
- 왜 상품 정보를 함께 반환하는가? (N+1 문제 방지)
- 왜 Facade 패턴을 사용하는가? (비즈니스 로직 분리)
- 페이지네이션은 어떻게 구현하는가? (ZREVRANGE + 범위 조회)

---

### [Step 4: 상품 상세 조회에 랭킹 정보 추가](./STEP4_PRODUCT_WITH_RANK.md)
**목표**: 기존 상품 API에 랭킹 정보 통합

**구현 내용**:
- `ProductV1Dto` 확장: `rank`, `score` 필드 추가
- `ProductFacade` 확장: `getProductWithRanking()` 메서드 추가
- `ProductV1Controller` 수정: 상품 상세 조회 로직 변경

**핵심 개념**:
- 왜 필드를 추가하는가? (별도 API vs 필드 추가)
- 하위 호환성은 어떻게 유지하는가? (Nullable 타입, 기본값)
- 순위권 밖 상품은 어떻게 처리하는가? (rank: null)

---

### [Step 5: 테스트 및 검증](./STEP5_TEST_AND_VERIFICATION.md)
**목표**: 구현한 시스템의 정상 동작 검증

**구현 내용**:
- 통합 테스트 시나리오 (이벤트 발행 → 랭킹 적재 → 조회)
- 멱등성 테스트 (Consumer 재시작 후 점수 중복 증가 없음)
- 점수 계산 검증 (수동 계산 vs Redis 점수)
- 트러블슈팅 가이드

**핵심 개념**:
- Redis 데이터는 어떻게 확인하는가? (redis-cli 명령어)
- Kafka 메시지는 어떻게 확인하는가? (Kafka UI)
- 문제 발생 시 어떻게 해결하는가? (트러블슈팅 가이드)

---

## 🚀 빠른 시작

### 1. 인프라 실행

```bash
cd docker
docker-compose -f infra-compose.yml up -d
```

### 2. Step별 구현

각 Step 문서를 순서대로 따라가며 구현합니다:

1. [STEP1_FOUNDATION.md](./STEP1_FOUNDATION.md) - 도메인 로직 구현
2. [STEP2_KAFKA_CONSUMER.md](./STEP2_KAFKA_CONSUMER.md) - Consumer 구현
3. [STEP3_RANKING_API.md](./STEP3_RANKING_API.md) - API 구현
4. [STEP4_PRODUCT_WITH_RANK.md](./STEP4_PRODUCT_WITH_RANK.md) - 기존 API 확장
5. [STEP5_TEST_AND_VERIFICATION.md](./STEP5_TEST_AND_VERIFICATION.md) - 테스트 및 검증

### 3. 검증

```bash
# API 테스트
curl http://localhost:8080/api/v1/rankings?page=0&size=20

# Redis 데이터 확인
docker exec -it redis-master redis-cli
> ZREVRANGE ranking:all:20251222 0 9 WITHSCORES
```

---

## ✅ 과제 체크리스트

### Ranking Consumer
- [ ] 랭킹 ZSET의 TTL, 키 전략 구성 완료
- [ ] 날짜별 키 계산 기능 구현 완료
- [ ] 이벤트 발생 후 ZSET 점수 반영 확인
- [ ] 배치 리스너로 처리 확인
- [ ] 멱등성 보장 확인 (event_handled 테이블)

### Ranking API
- [ ] 랭킹 Page 조회 정상 동작 확인
- [ ] 상품 정보 Aggregation 제공 확인
- [ ] 상품 상세 조회 시 순위 정보 반환 확인 (없으면 null)
- [ ] 페이지네이션 동작 확인

---

## 🎓 Round 8 멘토 리뷰 반영 사항

이 가이드는 Round 8 멘토 리뷰를 반영하여 개선되었습니다:

### 1. "왜"를 설명하기
- ❌ Before: "RankingService를 만듭니다"
- ✅ After: "왜 Service 레이어가 필요한가? Redis 명령어를 직접 사용하면..."

### 2. 목적을 먼저 제시
- 각 Step의 시작에 "왜 이 단계가 필요한가?" 섹션 추가
- 설계 결정의 배경과 트레이드오프 설명

### 3. Dual Write 문제 고려
- RankingEventFacade에서 @Transactional 명시
- DB 저장(event_handled)과 Redis 업데이트의 일관성 보장 방법 설명

### 4. 하드코딩 개선
- 가중치를 상수로 정의하되, 향후 Properties로 이동 가능하도록 설명 추가
- Profile별 설정 분리 가능성 언급

---

## 📊 기대 효과

이 랭킹 시스템을 구현하면:

1. **성능**: Redis ZSET으로 O(logN) 삽입, O(N) Top-N 조회
2. **확장성**: Kafka Consumer로 수평 확장 가능
3. **정합성**: 멱등성 보장으로 재처리 시에도 데이터 무결성 유지
4. **공정성**: 로그 정규화로 고가 상품 독식 방지
5. **사용자 경험**: 상품 정보 Aggregation으로 빠른 로딩

---

## 🤔 고민해볼 질문들

구현하면서 다음 질문들을 스스로에게 던져보세요:

1. **시간의 양자화**: 왜 누적 랭킹이 아닌 일별 랭킹을 사용하는가?
2. **콜드 스타트**: 새벽에 랭킹이 비어있으면 어떻게 해결할까?
3. **가중치 조정**: 실시간으로 가중치를 바꾸려면 어떻게 해야 할까?
4. **주간/월간 랭킹**: 일간 랭킹을 확장하려면 어떻게 설계해야 할까?
5. **Redis 장애**: Redis가 다운되면 랭킹 서비스는 어떻게 되는가?

이러한 질문들은 Technical Writing에서 훌륭한 주제가 됩니다!

---

## 📚 참고 자료

- [Redis Sorted Sets 공식 문서](https://redis.io/docs/data-types/sorted-sets/)
- [Spring Data Redis 문서](https://docs.spring.io/spring-data/redis/reference/)
- [Kafka Consumer 설정 가이드](https://kafka.apache.org/documentation/#consumerconfigs)

---

## 🎉 마치며

Round 9 랭킹 시스템 구현을 통해:
- Redis ZSET의 강력함을 체험했습니다
- 실시간 이벤트 처리의 중요성을 배웠습니다
- 비즈니스 가치를 코드로 표현하는 방법을 익혔습니다

이제 Technical Writing으로 여러분의 고민과 해결 과정을 정리해보세요!

**화이팅!** 🚀
