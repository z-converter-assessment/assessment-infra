terraform {
  required_version = ">= 1.5.0"

  # CD self-hosted runner는 checkout(clean)으로 워크스페이스를 매번 비우므로,
  # state를 워크스페이스 안에 두면 run마다 사라져 자원이 중복 생성된다.
  # 워크스페이스 밖 고정경로(local backend)에 두어 run 간 보존한다. (단일 runner 전제)
  # 멀티 runner/사용자 단계 진입 시 Swift 원격 backend로 이전 — CLAUDE.md "보류된 결정".
  backend "local" {
    path = "/home/debian/.tfstate/engine/terraform.tfstate"
  }

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.1"
    }
  }
}
