terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.52.0"
    }
  }
}

provider "openstack" {
  cloud = "openstack"
  insecure = true
}

resource "openstack_compute_keypair_v2" "auto_gen_key" {
  name       = "k8s-key"
}

# Private Key를 출력 (민감 데이터 처리)
output "generated_private_key" {
  description = "This is the newly generated private key from OpenStack"
  value       = openstack_compute_keypair_v2.auto_gen_key.private_key
  sensitive   = true
}

# Public Key를 출력
output "generated_public_key" {
  description = "This is the newly generated public key from OpenStack"
  value       = openstack_compute_keypair_v2.auto_gen_key.public_key
}

# Private Key를 로컬 파일로 저장
resource "local_file" "my_private_key_file" {
  content         = openstack_compute_keypair_v2.auto_gen_key.private_key
  filename        = "./k8s-key.pem"
  file_permission = "400"
}

############################
#  네트워크/서브넷 생성
############################

# k8s-internal 네트워크
resource "openstack_networking_network_v2" "k8s_internal" {
  name = "k8s-internal"
}

resource "openstack_networking_subnet_v2" "k8s_internal_subnet" {
  name       = "k8s-internal"
  network_id = openstack_networking_network_v2.k8s_internal.id
  cidr         = "192.168.0.0/16"
  ip_version   = 4
  no_gateway = true
  enable_dhcp  = false
}

# k8s-external 네트워크
resource "openstack_networking_network_v2" "k8s_external" {
  name = "k8s-external"
}

resource "openstack_networking_subnet_v2" "k8s_external_subnet" {
  name       = "k8s-external"
  network_id = openstack_networking_network_v2.k8s_external.id
  cidr       = "10.10.10.0/24"
  ip_version = 4
  gateway_ip = "10.10.10.254"
  enable_dhcp = false
}

# infra-net 참조
data "openstack_networking_network_v2" "infra_net" {
  name = "infra-net"
}

############################
#  보안그룹 생성 (모든 ICMP, TCP, UDP 허용)
############################

resource "openstack_networking_secgroup_v2" "k8s_SG" {
  name        = "k8s-SG"
  description = "Security group that allows all ICMP, TCP, and UDP traffic"
}

resource "openstack_networking_secgroup_rule_v2" "allow_all_icmp_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  security_group_id = openstack_networking_secgroup_v2.k8s_SG.id
}

resource "openstack_networking_secgroup_rule_v2" "allow_all_icmp_egress" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  security_group_id = openstack_networking_secgroup_v2.k8s_SG.id
}

resource "openstack_networking_secgroup_rule_v2" "allow_all_tcp_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  security_group_id = openstack_networking_secgroup_v2.k8s_SG.id
}

resource "openstack_networking_secgroup_rule_v2" "allow_all_tcp_egress" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  security_group_id = openstack_networking_secgroup_v2.k8s_SG.id
}

resource "openstack_networking_secgroup_rule_v2" "allow_all_udp_ingress" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 1
  port_range_max    = 65535
  security_group_id = openstack_networking_secgroup_v2.k8s_SG.id
}

resource "openstack_networking_secgroup_rule_v2" "allow_all_udp_egress" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 1
  port_range_max    = 65535
  security_group_id = openstack_networking_secgroup_v2.k8s_SG.id
}

############################
#  서버(노드) 생성
############################

# 서버 설정 반복 구조
variable "nodes" {
  default = [
    {
      name         = "k8s-controller"
      flavor_name  = "t1.k8s"
      image_name   = "rocky-9-linux"
      internal_ip  = "192.168.10.10"
      external_ip  = null
    },
    {
      name         = "k8s-compute1"
      flavor_name  = "t1.k8s"
      image_name   = "rocky-9-linux"
      internal_ip  = "192.168.10.20"
      external_ip  = "10.10.10.20"
    },
    {
      name         = "k8s-compute2"
      flavor_name  = "t1.k8s"
      image_name   = "rocky-9-linux"
      internal_ip  = "192.168.10.30"
      external_ip  = "10.10.10.30"
    },
    {
      name         = "k8s-infra"
      flavor_name  = "t1.k8s"
      image_name   = "rocky-9-linux"
      internal_ip  = "192.168.10.100"
      external_ip  = null
    },
    {
      name         = "client"
      flavor_name  = "m1.window"
      image_name   = "windows-10"
      internal_ip  = "192.168.10.200"
      external_ip  = "10.10.10.200"
    },
  ]
}

resource "openstack_compute_instance_v2" "nodes" {
  for_each       = { for node in var.nodes : node.name => node }
  name           = each.value.name
  flavor_name    = each.value.flavor_name
  image_name     = each.value.image_name
  key_pair       = openstack_compute_keypair_v2.auto_gen_key.name
  security_groups = [openstack_networking_secgroup_v2.k8s_SG.name]

  network {
    name = data.openstack_networking_network_v2.infra_net.name
  }

  network {
    name        = openstack_networking_network_v2.k8s_internal.name
    fixed_ip_v4 = each.value.internal_ip
  }
  
  network {
    name        = openstack_networking_network_v2.k8s_external.name
    fixed_ip_v4 = each.value.external_ip
  }

  # dynamic "network" {
  #   for_each = each.value.external_ip != null ? [each.value.external_ip] : []
  #   content {
  #     name        = openstack_networking_network_v2.k8s_external.name
  #     fixed_ip_v4 = network.value
  #   }
  # }




  config_drive = true

  user_data = templatefile("${path.module}/cloud_init.tpl", {
    public_key = openstack_compute_keypair_v2.auto_gen_key.public_key
  })
}
