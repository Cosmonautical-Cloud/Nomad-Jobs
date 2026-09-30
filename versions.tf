terraform {
  required_version = ">= 1.5.0"

  required_providers {
    nomad = {
      source  = "hashicorp/nomad"
      version = "~> 2.0"
    }
  }

  # Consul is shared cluster-wide (ACLs disabled) across every Nomad
  # datacenter, cosmonautical included, so it doubles as state storage
  # here too, same as the jellify sibling repo - but that means this
  # repo's key has to be its own, distinct from jellify's plain
  # "nomad-jobs" key, or the two repos would silently overwrite each
  # other's state.
  backend "consul" {
    address = "127.0.0.1:8500"
    path    = "nomad-jobs-cosmonautical"
  }
}

# cosmonautical is a datacenter within the same single Nomad region as
# jellify (confirmed via /v1/nodes from cassiopeia listing both
# datacenters' hosts), so 127.0.0.1:4646 resolves correctly wherever
# Semaphore's Terraform task actually lands, and reaches every
# datacenter's jobs through that same API - no per-datacenter address
# needed.
provider "nomad" {
  address = "http://127.0.0.1:4646"
}
