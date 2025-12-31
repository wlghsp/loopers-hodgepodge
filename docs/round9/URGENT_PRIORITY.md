# 🚨 긴급 우선순위 계획 (오후 6시 마감)

**현재 시간**: 오전 9:06
**남은 시간**: 약 9시간
**마감 시간**: 오후 6:00

---

## ✅ 현재 완료 상태

- ✅ Must-Have 구현 완료 (Redis ZSET, Kafka Consumer, Ranking API)
- ✅ 멱등성 보장 (Insert First Pattern)
- ✅ 로그 정규화 점수 계산
- ✅ 구현 가이드 문서 작성 완료

---

## 🎯 최종 제출 필수 항목

### 1. Technical Writing (필수) - **최우선**
**예상 시간**: 2~3시간
**마감까지 반드시 완료해야 함**

---

## 📊 9시간 전략 (3가지 옵션)

### 🔴 옵션 1: 안전 전략 (Technical Writing만 집중)

```
09:00 - 12:00 (3시간) → Technical Writing 집중 작성
12:00 - 13:00 (1시간) → 점심 + 휴식
13:00 - 16:00 (3시간) → Technical Writing 다듬기 + 코드 정리
16:00 - 18:00 (2시간) → 최종 검토 + 제출 준비
```

**장점**: 확실하게 제출 가능
**단점**: Nice-To-Have 포기

---

### 🟡 옵션 2: 균형 전략 (Technical Writing + 핵심 테스트)

```
09:00 - 11:30 (2.5시간) → Technical Writing 초안 완성
11:30 - 12:30 (1시간)   → 점심
12:30 - 14:30 (2시간)   → 핵심 테스트 코드만 작성
                          - RankingService 테스트 (45분)
                          - RankingScoreCalculator 테스트 (30분)
                          - RankingEventFacade 테스트 (45분)
14:30 - 16:30 (2시간)   → Technical Writing 다듬기 + 검토
16:30 - 18:00 (1.5시간) → 최종 정리 + 제출
```

**장점**: Technical Writing + 핵심 테스트 모두 확보
**단점**: 시간이 빠듯함

---

### 🟢 옵션 3: 도전 전략 (Technical Writing + Nice-To-Have 일부)

```
09:00 - 11:00 (2시간)   → Technical Writing 초안
11:00 - 12:00 (1시간)   → 콜드 스타트 구현 (핵심만)
                          - RankingService.initializeScore() (20분)
                          - Scheduler 구현 (40분)
12:00 - 13:00 (1시간)   → 점심
13:00 - 14:30 (1.5시간) → 시간 단위 랭킹 구현 (핵심만)
                          - RankingKeyGenerator (15분)
                          - RankingService hourly 메서드 (45분)
                          - API 추가 (30분)
14:30 - 16:30 (2시간)   → Technical Writing 완성
16:30 - 18:00 (1.5시간) → 최종 검토 + 제출
```

**장점**: Nice-To-Have도 일부 구현
**단점**: 시간 부족 시 Technical Writing 품질 저하 위험

---

## 🎯 **추천: 옵션 2 (균형 전략)**

### 이유:
1. **Technical Writing은 필수** - 이게 없으면 제출 불가
2. **핵심 테스트만** - Domain/Application Layer 테스트로 품질 입증
3. **Nice-To-Have는 포기** - 시간이 부족하면 과감히 포기
4. **안정적인 제출** - 리스크 최소화

---

## ⏱️ 세부 타임라인 (옵션 2 기준)

### Phase 1: Technical Writing 초안 (09:00 - 11:30)

**2시간 30분**

#### 구조 (1,500~2,000자)
```markdown
# Redis ZSET으로 실시간 랭킹 시스템 만들기

## TL;DR
카프카 이벤트 스트림을 Redis ZSET으로 집계하여 O(logN) 조회 성능의
실시간 랭킹 시스템을 구현했다. 멱등성 보장과 로그 정규화를 통해
안정적이고 공정한 랭킹을 제공한다.

## 1. 왜 Redis ZSET인가? (15분)
- MySQL vs Redis 성능 비교
- ZSET의 O(logN) 시간복잡도
- 실시간 업데이트 가능

## 2. 시간 양자화 - 처음 듣는 개념 (20분)
- 누적 랭킹의 롱테일 문제
- 일 단위 키 전략 (ranking:all:yyyyMMdd)
- TTL 2일 설정 이유

## 3. 공정한 점수 계산 (25분)
- 이벤트별 가중치 설계
  - 조회: 0.1, 좋아요: 0.2, 주문: 0.6
- 주문 금액 정규화 (ln 함수 사용)
- 고가 상품 독점 방지

## 4. 멱등성 보장 - Insert First Pattern (20분)
- Kafka 재처리 시 중복 문제
- Outbox 테이블 PK 제약조건 활용
- 배치 처리 최적화

## 5. 배치 처리로 성능 10배 향상 (20분)
- 단건 vs 배치 처리 비교
- 날짜별, 상품별 그룹핑
- Redis Pipeline 미사용 이유

## 6. 고민했던 지점들 (20분)
- 콜드 스타트 문제 (다음 구현 예정)
- 실시간성 vs 일관성 트레이드오프
- 메모리 사용량 모니터링 필요성

## 7. 성과 및 개선 방향 (10분)
- 달성: Must-Have 100% 완료
- 개선: 시간 단위 랭킹, 콜드 스타트 해결
```

**작성 요령:**
- "무엇을"보다 **"왜"** 중심
- 코드 예시 3~4개 포함
- 고민 지점 솔직하게 작성
- 1줄 요약(TL;DR) 필수

---

### Phase 2: 점심 (11:30 - 12:30)

**1시간**

---

### Phase 3: 핵심 테스트 코드 작성 (12:30 - 14:30)

**2시간** - 집중 작업

#### 우선순위 1: RankingService 테스트 (45분)
```kotlin
// modules/redis/src/test/kotlin/com/loopers/domain/ranking/RankingServiceTest.kt

필수 테스트:
1. incrementScore - 신규 상품 (10분)
2. incrementScore - 기존 상품 점수 누적 (10분)
3. getTopProducts - 정렬 검증 (10분)
4. getTopProducts - limit 검증 (5분)
5. TTL 검증 (10분)
```

#### 우선순위 2: RankingScoreCalculator 테스트 (30분)
```kotlin
// modules/redis/src/test/kotlin/com/loopers/domain/ranking/RankingScoreCalculatorTest.kt

필수 테스트:
1. ProductViewedEvent 점수 = 0.1 (5분)
2. ProductLikedEvent 점수 = 0.2 (5분)
3. ProductUnlikedEvent 점수 = -0.2 (5분)
4. OrderCreatedEvent 로그 정규화 검증 (15분)
```

#### 우선순위 3: RankingEventFacade 테스트 (45분)
```kotlin
// apps/commerce-streamer/src/test/kotlin/com/loopers/application/facade/RankingEventFacadeTest.kt

필수 테스트:
1. 단일 이벤트 처리 (10분)
2. 배치 이벤트 날짜별 그룹핑 (15분)
3. 배치 이벤트 상품별 그룹핑 (15분)
4. 빈 이벤트 리스트 처리 (5분)
```

**나머지 테스트는 포기:**
- RankingKafkaConsumer (90분 소요)
- RankingV1Controller (45분 소요)
- 통합 테스트 (60분 소요)

---

### Phase 4: Technical Writing 다듬기 (14:30 - 16:30)

**2시간**

#### 작업 내용:
- [ ] 초안 검토 및 문장 다듬기 (30분)
- [ ] 코드 예시 추가 및 정리 (30분)
- [ ] 다이어그램/이미지 추가 (선택, 20분)
- [ ] TL;DR 최종 점검 (10분)
- [ ] 맞춤법 검사 (10분)
- [ ] 블로그 플랫폼 업로드 (20분)
  - Velog, Tistory, Medium 등

---

### Phase 5: 최종 검토 및 제출 (16:30 - 18:00)

**1시간 30분**

#### 체크리스트:

**코드 정리 (30분)**
- [ ] 사용하지 않는 import 제거
- [ ] 주석 정리
- [ ] 포맷팅 확인 (Ctrl+Alt+L)
- [ ] 불필요한 로그 제거

**기능 검증 (30분)**
- [ ] 로컬 환경에서 전체 파이프라인 테스트
  ```bash
  # 1. 서버 실행
  ./gradlew :apps:commerce-api:bootRun
  ./gradlew :apps:commerce-streamer:bootRun

  # 2. 이벤트 발생 (상품 조회, 주문 생성)
  curl "http://localhost:8080/api/v1/products/101"
  curl -X POST "http://localhost:8080/api/v1/orders" -d '{...}'

  # 3. 랭킹 조회
  curl "http://localhost:8080/api/v1/rankings?date=20251226&limit=10"

  # 4. Redis 확인
  redis-cli ZREVRANGE "ranking:all:20251226" 0 9 WITHSCORES
  ```

**문서 확인 (20분)**
- [ ] README 업데이트 (선택)
- [ ] Technical Writing 링크 확인
- [ ] 가이드 문서 최종 검토

**제출 준비 (10분)**
- [ ] Git 상태 확인
- [ ] 커밋 정리 (필요 시)
- [ ] 제출 양식 작성

---

## 🚫 포기할 항목 (시간 절약)

### Nice-To-Have 구현 전체 포기
- ❌ 시간 단위 실시간 랭킹 (5시간)
- ❌ 콜드 스타트 Scheduler (3시간)
- ❌ Nice-To-Have 테스트 (3시간)

### Interface Layer 테스트 포기
- ❌ RankingKafkaConsumer 테스트 (90분)
- ❌ RankingV1Controller 테스트 (45분)

### 통합 테스트 포기
- ❌ E2E 통합 테스트 (60분)

### 문서화 최소화
- ❌ 상세 API 문서 (30분)
- ❌ 아키텍처 다이어그램 (30분)

**절약 시간: 약 15시간 → 9시간 안에 완료 가능**

---

## ✅ 최종 제출물

### 1. 코드 (현재 완료)
- ✅ Redis ZSET 랭킹 시스템
- ✅ Kafka Consumer 파이프라인
- ✅ Ranking API
- ✅ 멱등성 보장
- ✅ 로그 정규화

### 2. 핵심 테스트 (오늘 작성)
- ✅ RankingService 테스트
- ✅ RankingScoreCalculator 테스트
- ✅ RankingEventFacade 테스트

### 3. Technical Writing (오늘 작성)
- ✅ 블로그 포스트 (1,500~2,000자)
- ✅ TL;DR 포함
- ✅ "왜" 중심으로 작성
- ✅ 고민 지점 공유

---

## 📝 Technical Writing 작성 템플릿

```markdown
# Redis ZSET으로 실시간 랭킹 시스템 만들기

## TL;DR
(1줄 요약: 핵심 메시지를 50자 이내로)

## 배경: 왜 랭킹 시스템이 필요했나?

## 기술 선택: MySQL이 아닌 Redis ZSET을 선택한 이유
- 성능 비교
- 실시간성
- 운영 편의성

## 설계 고민 1: 시간 양자화
- 롱테일 문제
- 일 단위 키 전략
- TTL 설정

## 설계 고민 2: 공정한 점수 계산
- 이벤트 가중치
- 로그 정규화
- 코드 예시

## 설계 고민 3: 멱등성 보장
- Kafka 재처리 문제
- Insert First Pattern
- 코드 예시

## 성능 최적화: 배치 처리
- 단건 vs 배치
- 그룹핑 전략
- 성능 비교

## 남은 고민들
- 콜드 스타트
- 실시간성 개선
- 메모리 최적화

## 마무리
```

---

## 🎯 핵심 메시지

### 오늘 집중할 것:
1. **Technical Writing 완성** (필수)
2. **핵심 테스트 3개** (Domain + Application)
3. **기능 검증** (로컬 환경)

### 포기할 것:
- Nice-To-Have 구현
- Interface Layer 테스트
- 통합 테스트
- 완벽한 문서화

### 목표:
- **오후 6시 안정적 제출**
- 품질 > 분량

---

## ⚠️ 리스크 관리

### 시간이 부족하면?

**16시 기준 체크:**
- Technical Writing 80% 미만 → 테스트 포기하고 Writing 집중
- Technical Writing 80% 이상 → 그대로 진행

**17시 기준 체크:**
- Technical Writing 완성 안됨 → 테스트 포기하고 Writing만
- Technical Writing 완성됨 → 최종 검토

### 예상 문제와 대응:

| 문제 | 대응 |
|------|------|
| Technical Writing 막힘 | 가이드 템플릿 그대로 채우기 |
| 테스트 코드 에러 | 일단 스킵, 나중에 수정 |
| Redis 연결 안됨 | Docker 재시작, 안되면 스크린샷만 |
| 시간 부족 | 테스트 포기, Writing만 완성 |

---

## 🏁 최종 목표

**18:00까지 제출:**
1. ✅ Technical Writing (필수)
2. ✅ 핵심 테스트 3개 (가능하면)
3. ✅ 동작하는 코드 (이미 완료)
4. ✅ 제출 양식 작성

**성공 기준:**
- Technical Writing이 "왜" 중심으로 잘 작성됨
- 코드가 정상 동작함
- 시간 내 제출 완료

---

## 💪 지금 바로 시작하세요!

**09:06 → Technical Writing 시작**

행운을 빕니다! 🍀
