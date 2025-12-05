결제 시스템은 재고를 점유 할래말래? 

1. 점유를 미리 하는 방식(선차감 ? 선점유?) 
- 단점: GMV가 떨어질수있음, 시스템이 복잡하다.
- 장점: 유저 만족도가 높음.

2. 차감을 콜백에서 하는 방식 
- 장점: 시스템이 좀 단순하다. 돈이 있어야.. 비지니스가 있어야 가족이 있는거다. - 돈까스 -
가주문(메모리, 레디스) -> 진주문 (콜백 타이밍) 주문완료 -> 이벤트 발행

콜백(결제팀) -> 결제완료 이벤트 발행 or 주문 api를 호출합니다. 
order-service(가주문 -> 진주문) -> 주문완료 
주문완료  -> 재고팀 -> 재고차감, 재고 차감 실패 이벤트 ,, 

---------------------------------------------------------
"스케줄러로 상태가 오래 머문 주문을 확인하는 방식으로 해결하자."
주문 대사 


1. 콜백에서 주문완료 + 재고차감 하자.
2. 콜백에서 실패하면 주문 취소 + 포인트 원복 
3. 스케줄러로 상태변경 없는 주문들을 확인해서 1,2번에 맞게 변경하자. 

---
서비스 구성시 약간 꿀팁

- API의 리드 타임아웃을 몇초로 잡을것이냐
- API의 트랜잭션 동안 외부 호출이 포함되냐? 
- 외부 호출의 레이턴시를 파악해서 다시 리드 타임아웃을 고민해봐야한다.
- 외부 호출 부분에 서킷 브레이커를 항상단다. (마이크로 서비스 포함)
	- 서킷을 달때 fallback을 할수 있는게 있는가?
	- 예민하게 열고 예민하게 닫는다. 
	- 이미 운용하고 있는 api인데 서킷이 없다면, 기존의 에러율을 보셔라. 
	-> 만약에 에러를 볼수있는 옵저버빌리티가 없다. 모니터링 작업부터 해야겠지..?
	- 어떤 익셉션들을 서킷이 감지하길 원하는지 결정해야함.


---

'''kolin
XxxxService
XxxxRepository (Reader, Writer)
XxxxClient (외부 모듈 호출용)
// XxxxFactory (외부 모듈 호출용)
Xxxx (domain)

interface PgStrategy {
	supports(): Boolean
	pay(): Payment
}

class PgA: PgStrategy {
	@override
	supports(paymentType: PaymentType) {
		return paymentType == PaymentType.Money
	}
	@override
	pay(): Payment {
		...api call.. nice pay
		return Payment()
	}
}

class PgB: PgStrategy {
	@override
	supports(paymentType: PaymentType) {
		return paymentType == PaymentType.CARD
	}
	
	@override
	pay(): Payment {
		...api call..toss
		return Payment()
	}
}

class PaymentService(
	private val pgStrategyList: List<PgStrategy>,
) {
	fun pay(paymentType: PaymentType, ...args) {
		val pgs = pgStrategyList.filter{pg -> pg.supports(paymentType)}
		pgs여기 내에서는.. 레이트 리미터 기반의,, 뭔가,, 트래픽 분산을 해줄거야..
		switch(paymentType) {
			Money	-> a
			Card	-> b
		}
		
		when()
		pg.pay(...args);
	}
}
'''