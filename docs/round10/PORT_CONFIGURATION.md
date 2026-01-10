# 포트 설정 정리

> 각 애플리케이션과 서비스의 포트 충돌 방지를 위한 포트 할당 정보

---

## 애플리케이션 포트 (Application Port)

| 애플리케이션 | 포트 | 용도 | 설정 파일 |
|------------|------|------|----------|
| **commerce-api** | 8080 | REST API 서버 | `apps/commerce-api/src/main/resources/application.yml` |
| **pg-simulator** | 8082 | PG 시뮬레이터 | `apps/pg-simulator/src/main/resources/application.yml` |
| **commerce-streamer** | 8083 | Kafka 스트리밍 | `apps/commerce-streamer/src/main/resources/application.yml` |
| **commerce-batch** | 8085 | Spring Batch 작업 | `apps/commerce-batch/src/main/resources/application.yml` |

---

## 관리 포트 (Management Port)

| 애플리케이션 | 포트 | 용도 | 설정 파일 |
|------------|------|------|----------|
| **모든 애플리케이션** | 8081 | Actuator / Prometheus | `supports/monitoring/src/main/resources/monitoring.yml` |
| **pg-simulator** | 8083 | PG Actuator | `apps/pg-simulator/src/main/resources/application.yml` |
| **commerce-streamer** | 8084 | Streamer Actuator | `apps/commerce-streamer/src/main/resources/application.yml` |

---

## 인프라 포트 (Docker Services)

| 서비스 | 포트 | 용도 | 설정 위치 |
|--------|------|------|----------|
| **MySQL** | 3306 | 데이터베이스 | `docker-compose.yml` |
| **Redis** | 6379 | 캐시 / 랭킹 | `docker-compose.yml` |
| **Kafka** | 9092 | 메시지 브로커 | `docker-compose.yml` |
| **Zookeeper** | 2181 | Kafka 코디네이터 | `docker-compose.yml` |

---

## 포트 충돌 방지 규칙

1. **Application Port**: 8080, 8082-8085 범위 사용
2. **Management Port**: 8081, 8083-8084 범위 사용
3. **Infrastructure**: 3000번대, 6000번대, 9000번대 사용

### 신규 애플리케이션 추가 시

- Application Port: 8086부터 시작
- Management Port: 기본 8081 사용 (공통 monitoring.yml)
- 별도 관리 포트 필요시: 8085부터 시작

---

## API 호출 예시

### commerce-api (REST API)
```bash
curl "http://localhost:8080/api/v1/rankings?period=daily&size=10"
```

### commerce-batch (배치 작업)
```bash
curl -X POST "http://localhost:8085/batch/weekly?yearWeek=2025-W52"
```

### pg-simulator (결제 시뮬레이터)
```bash
curl -X POST "http://localhost:8082/api/v1/payments"
```

### Actuator (Health Check)
```bash
curl "http://localhost:8081/actuator/health"
```

---

## 트러블슈팅

### 포트 충돌 확인
```bash
# 포트 사용 중인 프로세스 확인
lsof -i :8080
lsof -i :8081
lsof -i :8085
```

### 사용 중인 포트 확인
```bash
# macOS/Linux
netstat -an | grep LISTEN | grep "808"
```

---

**업데이트**: 2025-12-31
