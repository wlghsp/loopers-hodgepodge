# Round 9 구현 시간 예상

## 1. 테스트 가이드 적용

### 1.1 Domain Layer 테스트

#### RankingService 테스트 (45분)
```
파일: modules/redis/src/test/kotlin/com/loopers/domain/ranking/RankingServiceTest.kt
```

**구현 항목:**
- [ ] 테스트 클래스 셋업 (RedisTestContainersConfig) - 10분
- [ ] incrementScore 테스트 (신규/기존 상품) - 10분
- [ ] getTopProducts 테스트 (정렬, limit) - 10분
- [ ] TTL 검증 테스트 - 10분
- [ ] Edge case 테스트 (빈 랭킹, 동점자) - 5분

**예상 시간:** 45분

#### RankingScoreCalculator 테스트 (30분)
```
파일: modules/redis/src/test/kotlin/com/loopers/domain/ranking/RankingScoreCalculatorTest.kt
```

**구현 항목:**
- [ ] ProductViewedEvent 점수 계산 - 5분
- [ ] ProductLikedEvent 점수 계산 - 5분
- [ ] ProductUnlikedEvent 점수 계산 - 5분
- [ ] OrderCreatedEvent 로그 정규화 검증 - 10분
- [ ] Edge case (음수 점수, 0 수량) - 5분

**예상 시간:** 30분

**Domain Layer 소계: 1시간 15분**

---

### 1.2 Application Layer 테스트

#### RankingEventFacade 테스트 (60분)
```
파일: apps/commerce-streamer/src/test/kotlin/com/loopers/application/facade/RankingEventFacadeTest.kt
```

**구현 항목:**
- [ ] 테스트 클래스 셋업 (MockK) - 10분
- [ ] 단일 이벤트 처리 - 10분
- [ ] 배치 이벤트 그룹핑 검증 (날짜별, 상품별) - 15분
- [ ] 멱등성 검증 (동일 이벤트 중복 처리) - 15분
- [ ] 빈 이벤트 처리 - 5분
- [ ] 에러 처리 (파싱 실패) - 5분

**예상 시간:** 60분

#### RankingFacade 테스트 (30분)
```
파일: apps/commerce-api/src/test/kotlin/com/loopers/application/ranking/RankingFacadeTest.kt
```

**구현 항목:**
- [ ] 테스트 클래스 셋업 (MockK) - 5분
- [ ] getTopProducts 호출 검증 - 10분
- [ ] date null 처리 (현재 날짜 사용) - 10분
- [ ] limit 파라미터 전달 검증 - 5분

**예상 시간:** 30분

**Application Layer 소계: 1시간 30분**

---

### 1.3 Interface Layer 테스트

#### RankingKafkaConsumer 테스트 (90분)
```
파일: apps/commerce-streamer/src/test/kotlin/com/loopers/interfaces/consumer/RankingKafkaConsumerTest.kt
```

**구현 항목:**
- [ ] 테스트 클래스 셋업 (MockK) - 15분
- [ ] JSON 파싱 성공 케이스 (4가지 이벤트 타입) - 20분
- [ ] JSON 파싱 실패 케이스 (eventType 없음) - 10분
- [ ] Batch 처리 검증 (여러 메시지) - 15분
- [ ] ACK 호출 검증 (성공/실패) - 15분
- [ ] 일부 메시지 파싱 실패 시 나머지 처리 - 10분
- [ ] 빈 배치 처리 - 5분

**예상 시간:** 90분

#### RankingV1Controller 테스트 (45분)
```
파일: apps/commerce-api/src/test/kotlin/com/loopers/interfaces/api/ranking/RankingV1ControllerTest.kt
```

**구현 항목:**
- [ ] 테스트 클래스 셋업 (MockMvc) - 10분
- [ ] GET /api/v1/rankings 성공 - 10분
- [ ] date 파라미터 파싱 검증 - 10분
- [ ] limit 파라미터 검증 - 10분
- [ ] API 응답 형식 검증 (ApiResponse) - 5분

**예상 시간:** 45분

**Interface Layer 소계: 2시간 15분**

---

### 1.4 통합 테스트

#### E2E 통합 테스트 (60분)
```
파일: apps/commerce-api/src/test/kotlin/com/loopers/integration/RankingIntegrationTest.kt
```

**구현 항목:**
- [ ] 테스트 환경 셋업 (Redis + Kafka TestContainers) - 20분
- [ ] 전체 파이프라인 테스트 (이벤트 발행 → 소비 → Redis → API 조회) - 30분
- [ ] 여러 이벤트 타입 혼합 시나리오 - 10분

**예상 시간:** 60분

**통합 테스트 소계: 1시간**

---

### 테스트 가이드 적용 총 시간

| 레이어 | 예상 시간 |
|--------|----------|
| Domain Layer | 1시간 15분 |
| Application Layer | 1시간 30분 |
| Interface Layer | 2시간 15분 |
| 통합 테스트 | 1시간 |
| **총계** | **6시간** |

**고려 사항:**
- Redis TestContainers 환경 이슈 발생 시 +30분
- Kafka 통합 테스트 디버깅 시 +30분
- 코드 리뷰 및 리팩토링 +1시간

**안전 마진 포함: 7~8시간** (1일)

---

## 2. Nice-To-Have 적용

### 2.1 시간 단위 실시간 랭킹

#### RankingKeyGenerator 수정 (15분)
```
파일: modules/redis/src/main/kotlin/com/loopers/domain/ranking/RankingKeyGenerator.kt
```

**구현 항목:**
- [ ] generateHourlyRankingKey() 추가 - 5분
- [ ] generateHourlyRankingKeys() 추가 - 10분

**예상 시간:** 15분

#### RankingService 수정 (45분)
```
파일: modules/redis/src/main/kotlin/com/loopers/domain/ranking/RankingService.kt
```

**구현 항목:**
- [ ] incrementScoreHourly() 구현 - 10분
- [ ] getTopProductsHourly() 구현 - 10분
- [ ] getTopProductsHourlyRange() 구현 (ZUNIONSTORE) - 20분
- [ ] TTL 설정 검증 - 5분

**예상 시간:** 45분

#### RankingEventFacade 수정 (60분)
```
파일: apps/commerce-streamer/src/main/kotlin/com/loopers/application/facade/RankingEventFacade.kt
```

**구현 항목:**
- [ ] TimeUnit enum 추가 - 5분
- [ ] processHourlyRanking() 구현 - 15분
- [ ] aggregateByHour() 구현 - 20분
- [ ] 설정값 바인딩 (@Value) - 10분
- [ ] 기존 로직 리팩토링 - 10분

**예상 시간:** 60분

#### RankingFacade 수정 (30분)
```
파일: apps/commerce-api/src/main/kotlin/com/loopers/application/ranking/RankingFacade.kt
```

**구현 항목:**
- [ ] getTopProductsHourly() 추가 - 10분
- [ ] getTopProductsRecentHours() 추가 - 20분

**예상 시간:** 30분

#### RankingV1Controller API 추가 (45분)
```
파일: apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/ranking/RankingV1Controller.kt
```

**구현 항목:**
- [ ] GET /api/v1/rankings/hourly 엔드포인트 - 15분
- [ ] GET /api/v1/rankings/recent 엔드포인트 - 15분
- [ ] Swagger 문서화 - 10분
- [ ] 입력 검증 (hours 1~24) - 5분

**예상 시간:** 45분

#### 설정 파일 수정 (15분)
```
파일: apps/commerce-streamer/src/main/resources/application.yml
```

**구현 항목:**
- [ ] ranking.time-unit 설정 추가 - 5분
- [ ] 프로필별 설정 - 10분

**예상 시간:** 15분

#### 테스트 코드 (90분)
```
- RankingService 시간 단위 테스트
- RankingEventFacade 시간 단위 테스트
- API 엔드포인트 테스트
```

**구현 항목:**
- [ ] RankingService 시간 단위 테스트 - 30분
- [ ] ZUNIONSTORE 검증 테스트 - 20분
- [ ] API 테스트 - 25분
- [ ] 통합 테스트 - 15분

**예상 시간:** 90분

**시간 단위 랭킹 소계: 5시간**

---

### 2.2 콜드 스타트 문제 해결

#### RankingService 수정 (30분)
```
파일: modules/redis/src/main/kotlin/com/loopers/domain/ranking/RankingService.kt
```

**구현 항목:**
- [ ] initializeScore() 구현 (ZADD NX) - 20분
- [ ] Redis execute 블록 작성 - 10분

**예상 시간:** 30분

#### RankingColdStartScheduler 생성 (60분)
```
파일: apps/commerce-streamer/src/main/kotlin/com/loopers/application/scheduler/RankingColdStartScheduler.kt
```

**구현 항목:**
- [ ] 스케줄러 클래스 생성 - 10분
- [ ] initializeNextDayRanking() 로직 구현 - 20분
- [ ] 에러 처리 및 로깅 - 15분
- [ ] @ConditionalOnProperty 설정 - 10분
- [ ] 설정값 바인딩 - 5분

**예상 시간:** 60분

#### CommerceStreamerApplication 수정 (5분)
```
파일: apps/commerce-streamer/src/main/kotlin/com/loopers/CommerceStreamerApplication.kt
```

**구현 항목:**
- [ ] @EnableScheduling 추가 - 5분

**예상 시간:** 5분

#### 설정 파일 수정 (20분)
```
파일: apps/commerce-streamer/src/main/resources/application.yml
```

**구현 항목:**
- [ ] spring.task.scheduling 설정 - 5분
- [ ] ranking.cold-start 설정 - 10분
- [ ] 프로필별 설정 (local/prd) - 5분

**예상 시간:** 20분

#### 테스트 코드 (90분)
```
- RankingService initializeScore 테스트
- Scheduler 테스트
- 멱등성 검증 (ZADD NX)
```

**구현 항목:**
- [ ] initializeScore 단위 테스트 - 20분
- [ ] ZADD NX 멱등성 검증 - 25분
- [ ] Scheduler 단위 테스트 - 30분
- [ ] 통합 테스트 (23:50 시뮬레이션) - 15분

**예상 시간:** 90분

**콜드 스타트 소계: 3시간 25분**

---

### 2.3 시간 단위 콜드 스타트 (선택)

#### 추가 Scheduler 메서드 (30분)
```
파일: RankingColdStartScheduler.kt
```

**구현 항목:**
- [ ] initializeNextHourRanking() 구현 - 20분
- [ ] cron 설정 (매시 55분) - 10분

**예상 시간:** 30분

#### 테스트 (20분)
**예상 시간:** 20분

**시간 단위 콜드 스타트 소계: 50분**

---

### 2.4 문서화 및 검증

#### 문서 작성 (60분)
**구현 항목:**
- [ ] 구현 완료 문서 작성 - 30분
- [ ] API 문서 업데이트 - 20분
- [ ] 테스트 시나리오 문서 - 10분

**예상 시간:** 60분

#### 통합 검증 및 디버깅 (120분)
**구현 항목:**
- [ ] 로컬 환경 전체 테스트 - 30분
- [ ] Redis 키 생성 확인 - 20분
- [ ] 스케줄러 실행 검증 - 20분
- [ ] API 응답 검증 - 20분
- [ ] 성능 테스트 (ZUNIONSTORE) - 20분
- [ ] 버그 수정 - 10분

**예상 시간:** 120분

**문서화 및 검증 소계: 3시간**

---

### Nice-To-Have 적용 총 시간

| 항목 | 예상 시간 |
|------|----------|
| 시간 단위 실시간 랭킹 | 5시간 |
| 콜드 스타트 문제 해결 | 3시간 25분 |
| 시간 단위 콜드 스타트 (선택) | 50분 |
| 문서화 및 검증 | 3시간 |
| **총계 (필수)** | **11시간 25분** |
| **총계 (선택 포함)** | **12시간 15분** |

**고려 사항:**
- Redis ZADD NX 동작 확인 및 디버깅 +30분
- Scheduler 시간대 이슈 (타임존) +20분
- ZUNIONSTORE 성능 튜닝 +30분
- 설정 오류 및 재시작 +20분

**안전 마진 포함: 14~15시간** (2일)

---

## 3. 전체 종합

### 작업 일정 요약

| 작업 | 예상 시간 | 일수 (8시간 기준) |
|------|----------|------------------|
| **테스트 가이드 적용** | 7~8시간 | 1일 |
| **Nice-To-Have 적용** | 14~15시간 | 2일 |
| **총계** | **21~23시간** | **3일** |

### 세부 일정 제안

#### Day 1: 테스트 코드 작성 (8시간)
```
오전 (4시간):
- Domain Layer 테스트 (1.5시간)
- Application Layer 테스트 (2.5시간)

오후 (4시간):
- Interface Layer 테스트 (3시간)
- 통합 테스트 (1시간)
```

#### Day 2: Nice-To-Have 구현 (8시간)
```
오전 (4시간):
- RankingKeyGenerator 수정 (15분)
- RankingService 시간 단위 메서드 (45분)
- RankingEventFacade 수정 (1시간)
- RankingFacade 수정 (30분)
- API 엔드포인트 추가 (45분)

오후 (4시간):
- 시간 단위 테스트 코드 (1.5시간)
- RankingService initializeScore (30분)
- Scheduler 구현 (1시간)
- 설정 파일 (20분)
- 콜드 스타트 테스트 (40분)
```

#### Day 3: 완성 및 검증 (5~7시간)
```
오전 (3시간):
- 시간 단위 콜드 스타트 (50분, 선택)
- 문서화 (1시간)
- 전체 통합 검증 (1시간)

오후 (2~4시간):
- 디버깅 및 버그 수정 (1~2시간)
- 성능 테스트 (1시간)
- 최종 검토 (30분)
```

---

## 4. 작업 우선순위

### 필수 (Must-Do)
1. ✅ 테스트 가이드 적용 - Domain/Application Layer (3시간)
2. ✅ 시간 단위 랭킹 핵심 구현 (4시간)
3. ✅ 콜드 스타트 Scheduler (2시간)

### 중요 (Should-Do)
4. ✅ Interface Layer 테스트 (2시간)
5. ✅ 시간 단위 랭킹 테스트 (1.5시간)
6. ✅ 콜드 스타트 테스트 (1.5시간)

### 선택 (Nice-To-Do)
7. 통합 테스트 E2E (1시간)
8. 시간 단위 콜드 스타트 (50분)
9. 성능 튜닝 (1시간)

---

## 5. 리스크 및 대응 방안

### 예상 리스크

| 리스크 | 확률 | 영향도 | 추가 시간 | 대응 방안 |
|--------|-----|--------|----------|----------|
| Redis ZADD NX 동작 이슈 | 중 | 중 | +1시간 | 로컬 Redis CLI로 수동 검증 |
| Scheduler 실행 안됨 | 중 | 고 | +2시간 | @EnableScheduling 확인, 로그 추가 |
| ZUNIONSTORE 성능 저하 | 저 | 중 | +1시간 | 캐싱 추가, TTL 조정 |
| Kafka 통합 테스트 실패 | 중 | 중 | +1시간 | EmbeddedKafka 설정 검토 |
| TestContainers 환경 이슈 | 저 | 저 | +30분 | Docker 재시작 |

### 최악의 경우
- 모든 리스크 발생 시: **+5.5시간**
- 총 시간: **26~29시간** (약 4일)

### 최선의 경우
- 문서대로 순조롭게 진행: **18~20시간** (약 2.5일)

---

## 6. 결론

### 현실적인 예상 시간

- **보수적 예상**: 3일 (24시간)
- **낙관적 예상**: 2.5일 (20시간)
- **안전 마진**: 4일 (32시간)

### 추천 일정

**집중 작업 시 (하루 8시간):**
- Day 1: 테스트 코드
- Day 2: 시간 단위 랭킹 + 콜드 스타트 구현
- Day 3: 테스트 + 검증 + 문서화

**여유 일정 (하루 4~5시간):**
- 5~6일 소요 예상
