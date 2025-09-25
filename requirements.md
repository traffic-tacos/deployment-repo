# 요구사항

## 작업 순서

### ArgoCD 배포

- namespace: argocd
- 헬름 차트가 있다면 가져와서 GitOps 를 구성할 것
- aws 정보 필요하면 aws tacos 로컬 프로필 사용해서 조회해볼 것

### Gateway API 배포

- namespace: gateway
- 헬름 차트가 있다면 가져와서 GitOps 를 구성할 것
- aws 정보 필요하면 aws tacos 로컬 프로필 사용해서 조회해볼 것

### Application 배포

- namespace: tacos
= 3만 RPS + 보안 + FinOps 를 위해 필요한 CRD를 정의할 것
- aws 정보 필요하면 aws tacos 로컬 프로필 사용해서 조회해볼 것
- GitOps 되게끔 할 것

**.cursor/rules/project-all-detail.mdc** 참고
- gateway-api
- reservation-api
- inventory-api
- payment-sim-api
- reseration-worker

## 사전 세팅

- EKS: ticket-cluster
  - Region: ap-northeast-2