# Step 2: commerce-batch 모듈 생성

> Spring Batch 모듈 기본 구조 만들기

---

## 2.1 디렉토리 생성

```bash
mkdir -p apps/commerce-batch/src/main/kotlin/com/loopers
mkdir -p apps/commerce-batch/src/main/resources
```

---

## 2.2 build.gradle.kts 생성

**파일**: `apps/commerce-batch/build.gradle.kts`

```kotlin
plugins {
    id("org.jetbrains.kotlin.plugin.jpa")
}

dependencies {
    // 기존 모듈
    implementation(project(":modules:jpa"))
    implementation(project(":modules:redis"))

    // Spring Batch
    implementation("org.springframework.boot:spring-boot-starter-batch")
    implementation("org.springframework.boot:spring-boot-starter-web")
}

tasks.bootJar {
    enabled = true
    archiveFileName.set("commerce-batch.jar")
}

tasks.jar {
    enabled = false
}
```

---

## 2.3 settings.gradle.kts 수정

**파일**: `settings.gradle.kts`

```kotlin
include(
    ":apps:commerce-api",
    ":apps:commerce-streamer",
    ":apps:commerce-batch",  // 이 줄 추가
    ":apps:pg-simulator",
    ":modules:jpa",
    ":modules:redis",
    ":modules:kafka",
    ":supports:jackson",
    ":supports:logging",
    ":supports:monitoring",
)
```

---

## 2.4 Application 클래스

**파일**: `apps/commerce-batch/src/main/kotlin/com/loopers/CommerceBatchApplication.kt`

```kotlin
package com.loopers

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication
import org.springframework.scheduling.annotation.EnableScheduling

@SpringBootApplication
@EnableScheduling
class CommerceBatchApplication

fun main(args: Array<String>) {
    runApplication<CommerceBatchApplication>(*args)
}
```

**주의**: `@EnableBatchProcessing`은 별도 Config 파일에서 선언합니다.

---

## 2.5 Batch Config

**파일**: `apps/commerce-batch/src/main/kotlin/com/loopers/config/BatchConfig.kt`

```kotlin
package com.loopers.config

import org.springframework.batch.core.configuration.annotation.EnableBatchProcessing
import org.springframework.context.annotation.Configuration

/**
 * Spring Batch 인프라 설정
 *
 * @EnableBatchProcessing의 dataSourceRef 속성으로
 * 공통 모듈의 mySqlMainDataSource를 사용하도록 지정
 */
@Configuration
@EnableBatchProcessing(dataSourceRef = "mySqlMainDataSource")
class BatchConfig
```

**설명:**
- Spring Batch 5.x는 기본적으로 `dataSource` 이름의 bean을 찾음
- 공통 모듈은 `mySqlMainDataSource` 이름으로 DataSource를 정의
- `@EnableBatchProcessing(dataSourceRef = "mySqlMainDataSource")`로 명시적 지정
- 별도 bean 생성 없이 어노테이션 속성만으로 간단히 해결

---

## 2.6 application.yml

**파일**: `apps/commerce-batch/src/main/resources/application.yml`

```yaml
server:
  port: 8085

spring:
  application:
    name: commerce-batch
  profiles:
    active: local
  config:
    import:
      - jpa.yml
      - redis.yml

  batch:
    jdbc:
      initialize-schema: never  # 스키마는 docker/01-schema.sql에서 관리
    job:
      enabled: false  # 자동 실행 방지 (스케줄러로만 실행)

logging:
  level:
    com.loopers: DEBUG
    org.springframework.batch: INFO
```

**설명:**
- `port: 8085` - 포트 할당: commerce-api(8080), management(8081), pg-simulator(8082), streamer(8083)
- `jpa.yml`, `redis.yml`을 import하여 DataSource 및 Redis 설정을 공통 모듈에서 가져옴
- 환경별 설정은 import된 파일의 profile 섹션에서 관리

---

## 2.7 빌드 확인

```bash
./gradlew :apps:commerce-batch:build
```

**성공 메시지:**
```
BUILD SUCCESSFUL in 5s
```

---

## 2.8 실행 테스트

```bash
./gradlew :apps:commerce-batch:bootRun
```

**로그 확인:**
```
...
2025-12-29 ... : Started CommerceBatchApplication in 3.456 seconds
```

서버가 정상 기동되면 `Ctrl+C`로 종료

---

## ✅ Step 2 완료 체크

- [ ] commerce-batch 디렉토리 생성
- [ ] build.gradle.kts 작성
- [ ] settings.gradle.kts에 모듈 추가
- [ ] Application 클래스 작성
- [ ] BatchConfig 작성
- [ ] application.yml 작성
- [ ] 빌드 성공 확인
- [ ] 실행 테스트 성공

---

**다음 단계**: [Step 3: Entity & Repository](./STEP3_ENTITY_REPOSITORY.md)
