# Kafka PartitionKey를 aggregateId로 설정한 이유: 이벤트 순서 보장의 실전 경험

**TL;DR**: 같은 상품의 이벤트는 같은 Kafka 파티션으로 가야 순서가 보장된다. partitionKey를 aggregateId(상품ID)로 설정했고, Consumer에서 updatedAt 기준으로 순서 역전을 방지했다. 랜덤 키를 썼다면 집계 데이터가 꼬였을 것이다.

---

## 처음엔 키를 신경 쓰지 않았다

Kafka Producer를 구현하면서 처음엔 partitionKey를 랜덤 UUID로 설정하려고 했다. 이벤트마다 고유한 키를 주면 파티션에 골고루 분산될 거라고 생각했다.

```kotlin
// 처음 생각했던 방식
val partitionKey = UUID.randomUUID().toString()
kafkaTemplate.send(topic, partitionKey, payload)
```

하지만 테스트를 해보니 문제가 생겼다.

## 문제: 같은 상품의 이벤트가 뒤바뀌었다

상품 좋아요를 추가하고 바로 취소하는 시나리오를 테스트했다.

1. 상품 1번에 좋아요 추가 → `PRODUCT_LIKED` 이벤트
2. 상품 1번 좋아요 취소 → `PRODUCT_UNLIKED` 이벤트

랜덤 키를 사용하면 두 이벤트가 서로 다른 파티션으로 갈 수 있다. Kafka는 파티션 내에서만 순서를 보장하니까, 다른 파티션으로 가면 순서가 뒤바뀔 수 있다.

실제로 테스트해보니 `PRODUCT_UNLIKED`가 먼저 처리되고, `PRODUCT_LIKED`가 나중에 처리되는 경우가 있었다. 결과적으로 좋아요 수가 1이 되어야 하는데 0이 되는 버그가 생겼다.

## 해결: aggregateId를 partitionKey로

같은 상품의 이벤트는 같은 파티션으로 가야 한다. 그래서 partitionKey를 `aggregateId`(상품ID)로 설정했다.

```kotlin
// OutboxEventPublisher.kt
private fun publishToKafka(outbox: EventOutbox) {
    val topic = when (outbox.aggregateType.lowercase()) {
        "product" -> "catalog-events"
        "order" -> "order-events"
        else -> "general-events"
    }

    val partitionKey = outbox.aggregateId.toString()
    val result = kafkaTemplate.send(topic, partitionKey, outbox.payload).get()
    
    outbox.kafkaPartition = result.recordMetadata.partition()
    outbox.kafkaOffset = result.recordMetadata.offset()
}
```

이제 상품 1번의 모든 이벤트는 같은 파티션으로 간다. Kafka가 파티션 내에서 순서를 보장하니까, 이벤트가 발생한 순서대로 처리된다.

## 추가 안전장치: updatedAt 체크

하지만 완벽하지 않다. 네트워크 지연이나 Consumer 재시작 등으로 인해 순서가 역전될 가능성이 있다. 그래서 Consumer에서도 한 번 더 체크한다.

```kotlin
// ProductMetricsService.kt
private fun updateMetrics(
    productId: Long,
    eventOccurredAt: Instant,
    update: (ProductMetrics) -> Unit,
) {
    val metrics = productMetricsRepository.findByProductId(productId)
        ?: ProductMetrics(productId = productId)

    if (metrics.updatedAt.isAfter(eventOccurredAt)) {
        logger.warn(
            "이벤트 순서 역전 무시: productId={}, eventOccurredAt={}, metrics.updatedAt={}",
            productId, eventOccurredAt, metrics.updatedAt
        )
        return
    }

    update(metrics)
    productMetricsRepository.save(metrics)
}
```

`updatedAt`이 이벤트 발생 시각(`occurredAt`)보다 나중이면 무시한다. 이미 더 최신 데이터가 반영된 거니까.

## 랜덤 키를 썼다면?

만약 partitionKey를 랜덤으로 설정했다면:

**시나리오**: 상품 1번에 좋아요 추가 → 취소 → 다시 추가

1. `PRODUCT_LIKED` (랜덤키: abc) → 파티션 0
2. `PRODUCT_UNLIKED` (랜덤키: xyz) → 파티션 2  
3. `PRODUCT_LIKED` (랜덤키: def) → 파티션 1

파티션 2가 먼저 처리되면 좋아요가 -1이 되고, 파티션 0이 처리되면 0이 되고, 파티션 1이 처리되면 1이 된다. 최종 결과는 1이 맞지만, 중간에 데이터가 꼬일 수 있다.

더 심각한 건, Consumer가 재시작되거나 파티션별로 처리 속도가 다르면 순서가 완전히 뒤바뀔 수 있다. `updatedAt` 체크만으로는 해결이 안 된다. 왜냐하면 나중에 발생한 이벤트가 먼저 처리될 수 있으니까.

## aggregateId를 키로 쓰면?

같은 상품의 모든 이벤트가 같은 파티션으로 간다:

1. `PRODUCT_LIKED` (키: 1) → 파티션 0
2. `PRODUCT_UNLIKED` (키: 1) → 파티션 0
3. `PRODUCT_LIKED` (키: 1) → 파티션 0

파티션 0 내에서 순서가 보장되니까, 이벤트 발생 순서대로 처리된다. `updatedAt` 체크는 네트워크 지연 같은 엣지 케이스를 위한 추가 안전장치다.

## 배치 처리에서도 중요했다

배치로 여러 이벤트를 한 번에 처리할 때도 순서가 중요했다.

```kotlin
fun processBatchEvents(productId: Long, events: List<DomainEvent>) {
    val sortedEvents = events.sortedBy { it.occurredAt }
    
    val latestEventTime = sortedEvents.last().occurredAt
    if (metrics.updatedAt.isAfter(latestEventTime)) {
        logger.warn("배치 이벤트 순서 역전 무시...")
        return
    }
    
    sortedEvents.forEach { event ->
        applyEvent(metrics, event)
    }
    
    productMetricsRepository.save(metrics)
}
```

배치로 받은 이벤트들을 `occurredAt` 기준으로 정렬해서 처리한다. 만약 partitionKey가 랜덤이었다면, 같은 상품의 이벤트가 다른 배치로 나뉠 수 있어서 정렬해도 의미가 없었을 것이다.

## 아직 완벽하지 않다

aggregateId를 키로 쓰면 같은 상품의 이벤트는 순서가 보장되지만, 다른 상품의 이벤트는 여전히 순서가 보장되지 않는다. 

예를 들어 상품 1번과 2번의 이벤트가 섞여서 들어올 수 있다. 다만 우리 도메인에서는 상품별로 독립적으로 집계하니까 문제가 없다. 상품 1번의 좋아요 수와 상품 2번의 좋아요 수는 서로 영향을 주지 않으니까.

만약 상품 간 의존성이 있는 비즈니스 로직이라면? 그때는 다른 전략을 고민해야 할 것 같다. 예를 들어 전체 이벤트를 하나의 파티션으로 보내거나, 더 세밀한 키 전략을 사용해야 할 수도 있다.

## 마무리

처음엔 단순하게 랜덤 키를 쓰려고 했지만, 실제로 테스트해보니 순서 보장이 중요하다는 걸 깨달았다. aggregateId를 partitionKey로 설정하니 같은 집계 단위의 이벤트가 순서대로 처리되게 되었다.

Kafka를 사용할 때는 "어떤 단위로 순서를 보장해야 하는가"를 먼저 생각해보는 게 중요하다는 걸 배웠다. 우리 경우엔 상품별 집계가 목적이었으니 상품ID를 키로 쓰는 게 맞았다.
