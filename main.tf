# Provider Configuration
terraform {
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = ">=2.3.1"
    }
  }
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

# Variables
variable "vsphere_user" {
  description = "vSphere administrator username"
  type        = string
  default     = "administrator@vsphere.local"
}

variable "vsphere_password" {
  description = "vSphere administrator password"
  type        = string
  sensitive   = true
}

variable "vsphere_server" {
  description = "vSphere server address"
  type        = string
}

variable "datacenter" {
  description = "vSphere datacenter name"
  type        = string
  default     = "Datacenter-Name"
}

variable "cluster" {
  description = "vSphere cluster name"
  type        = string
  default     = "Cluster-Name"
}

variable "datastore" {
  description = "vSphere datastore name"
  type        = string
  default     = "Datastore-Name"
}

variable "network_interfaces" {
  description = "Network interfaces configuration"
  type        = map(any)
  default = {
    "VLAN10-Servers" = {
      name = "VLAN10-Servers"
      vlan_id = 10
    },
    "VLAN20-DMZ" = {
      name = "VLAN20-DMZ"
      vlan_id = 20
    },
    "VLAN30-Users" = {
      name = "VLAN30-Users"
      vlan_id = 30
    },
    "VLAN40-Security" = {
      name = "VLAN40-Security"
      vlan_id = 40
    }
  }
}

variable "vm_folder" {
  description = "VM folder"
  type        = string
  default     = "Infrastructure"
}

# Data sources
data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name          = "${var.cluster}/Resources"
  datacenter_id = data.vsphere_datacenter.dc.id
}

# VM Templates
data "vsphere_virtual_machine" "fortigate_template" {
  name          = "fortigate-template"
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "linux_template" {
  name          = "linux-template"
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Folder
resource "vsphere_folder" "folder" {
  path          = var.vm_folder
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Networks (VLANs)
resource "vsphere_distributed_virtual_switch" "dvs" {
  name          = "Infrastructure-DVS"
  datacenter_id = data.vsphere_datacenter.dc.id
  
  uplinks = ["uplink1", "uplink2"]
  
  active_uplinks  = ["uplink1"]
  standby_uplinks = ["uplink2"]
}

resource "vsphere_distributed_port_group" "port_groups" {
  for_each                        = var.network_interfaces
  name                            = each.value.name
  distributed_virtual_switch_uuid = vsphere_distributed_virtual_switch.dvs.id
  vlan_id                         = each.value.vlan_id
}

# Perimeter Firewall (FW1)
resource "vsphere_virtual_machine" "fortigate_fw1" {
  name             = "FortiGate-FW1"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = vsphere_folder.folder.path
  
  guest_id         = data.vsphere_virtual_machine.fortigate_template.guest_id
  firmware         = data.vsphere_virtual_machine.fortigate_template.firmware
  
  num_cpus         = 2
  memory           = 4096
  
  wait_for_guest_net_timeout = 0
  wait_for_guest_ip_timeout  = 0
  
  network_interface {
    network_id   = vsphere_distributed_port_group.port_groups["VLAN20-DMZ"].id
    adapter_type = data.vsphere_virtual_machine.fortigate_template.network_interface_types[0]
  }
  
  network_interface {
    network_id   = vsphere_distributed_port_group.port_groups["VLAN40-Security"].id
    adapter_type = data.vsphere_virtual_machine.fortigate_template.network_interface_types[0]
  }
  
  disk {
    label            = "disk0"
    size             = 20
    eagerly_scrub    = false
    thin_provisioned = true
  }
  
  clone {
    template_uuid = data.vsphere_virtual_machine.fortigate_template.id
    
    customize {
      linux_options {
        host_name = "fortigate-fw1"
        domain    = "local"
      }
      
      network_interface {
        ipv4_address = "192.168.20.1"
        ipv4_netmask = 24
      }
      
      network_interface {
        ipv4_address = "192.168.40.1"
        ipv4_netmask = 24
      }
      
      ipv4_gateway = "192.168.20.254"
    }
  }
}

# Internal Firewall (FW2)
resource "vsphere_virtual_machine" "fortigate_fw2" {
  name             = "FortiGate-FW2"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = vsphere_folder.folder.path
  
  guest_id         = data.vsphere_virtual_machine.fortigate_template.guest_id
  firmware         = data.vsphere_virtual_machine.fortigate_template.firmware
  
  num_cpus         = 2
  memory           = 4096
  
  wait_for_guest_net_timeout = 0
  wait_for_guest_ip_timeout  = 0
  
  network_interface {
    network_id   = vsphere_distributed_port_group.port_groups["VLAN40-Security"].id
    adapter_type = data.vsphere_virtual_machine.fortigate_template.network_interface_types[0]
  }
  
  network_interface {
    network_id   = vsphere_distributed_port_group.port_groups["VLAN10-Servers"].id
    adapter_type = data.vsphere_virtual_machine.fortigate_template.network_interface_types[0]
  }
  
  network_interface {
    network_id   = vsphere_distributed_port_group.port_groups["VLAN30-Users"].id
    adapter_type = data.vsphere_virtual_machine.fortigate_template.network_interface_types[0]
  }
  
  disk {
    label            = "disk0"
    size             = 20
    eagerly_scrub    = false
    thin_provisioned = true
  }
  
  clone {
    template_uuid = data.vsphere_virtual_machine.fortigate_template.id
    
    customize {
      linux_options {
        host_name = "fortigate-fw2"
        domain    = "local"
      }
      
      network_interface {
        ipv4_address = "192.168.40.2"
        ipv4_netmask = 24
      }
      
      network_interface {
        ipv4_address = "192.168.10.1"
        ipv4_netmask = 24
      }
      
      network_interface {
        ipv4_address = "192.168.30.1"
        ipv4_netmask = 24
      }
      
      ipv4_gateway = "192.168.40.1"
    }
  }
}

# Web Server in DMZ
resource "vsphere_virtual_machine" "web_server" {
  name             = "Web-Server"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = vsphere_folder.folder.path
  
  guest_id         = data.vsphere_virtual_machine.linux_template.guest_id
  firmware         = data.vsphere_virtual_machine.linux_template.firmware
  
  num_cpus         = 2
  memory           = 4096
  
  network_interface {
    network_id   = vsphere_distributed_port_group.port_groups["VLAN20-DMZ"].id
    adapter_type = data.vsphere_virtual_machine.linux_template.network_interface_types[0]
  }
  
  disk {
    label            = "disk0"
    size             = 40
    eagerly_scrub    = false
    thin_provisioned = true
  }
  
  clone {
    template_uuid = data.vsphere_virtual_machine.linux_template.id
    
    customize {
      linux_options {
        host_name = "web-server"
        domain    = "local"
      }
      
      network_interface {
        ipv4_address = "192.168.20.10"
        ipv4_netmask = 24
      }
      
      ipv4_gateway = "192.168.20.1"
      dns_server_list = ["192.168.30.10"]
      dns_suffix_list = ["local"]
    }
  }
}

# SIEM/Log Server
resource "vsphere_virtual_machine" "siem_server" {
  name             = "SIEM-Server"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = vsphere_folder.folder.path
  
  guest_id         = data.vsphere_virtual_machine.linux_template.guest_id
  firmware         = data.vsphere_virtual_machine.linux_template.firmware
  
  num_cpus         = 4
  memory           = 8192
  
  network_interface {
    network_id   = vsphere_distributed_port_group.port_groups["VLAN40-Security"].id
    adapter_type = data.vsphere_virtual_machine.linux_template.network_interface_types[0]
  }
  
  disk {
    label            = "disk0"
    size             = 100
    eagerly_scrub    = false
    thin_provisioned = true
  }
  
  clone {
    template_uuid = data.vsphere_virtual_machine.linux_template.id
    
    customize {
      linux_options {
        host_name = "siem-server"
        domain    = "local"
      }
      
      network_interface {
        ipv4_address = "192.168.40.10"
        ipv4_netmask = 24
      }
      
      ipv4_gateway = "192.168.40.2"
      dns_server_list = ["192.168.30.10"]
      dns_suffix_list = ["local"]
    }
  }
}

# Database Server
resource "vsphere_virtual_machine" "db_server" {
  name             = "Database-Server"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = vsphere_folder.folder.path
  
  guest_id         = data.vsphere_virtual_machine.linux_template.guest_id
  firmware         = data.vsphere_virtual_machine.linux_template.firmware
  
  num_cpus         = 4
  memory           = 8192
  
  network_interface {
    network_id   = vsphere_distributed_port_group.port_groups["VLAN10-Servers"].id
    adapter_type = data.vsphere_virtual_machine.linux_template.network_interface_types[0]
  }
  
  disk {
    label            = "disk0"
    size             = 100
    eagerly_scrub    = false
    thin_provisioned = true
  }
  
  clone {
    template_uuid = data.vsphere_virtual_machine.linux_template.id
    
    customize {
      linux_options {
        host_name = "db-server"
        domain    = "local"
      }
      
      network_interface {
        ipv4_address = "192.168.10.10"
        ipv4_netmask = 24
      }
      
      ipv4_gateway = "192.168.10.1"
      dns_server_list = ["192.168.30.10"]
      dns_suffix_list = ["local"]
    }
  }
}

# LDAP/AD/DNS Server
resource "vsphere_virtual_machine" "ldap_server" {
  name             = "LDAP-Server"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = vsphere_folder.folder.path
  
  guest_id         = data.vsphere_virtual_machine.linux_template.guest_id
  firmware         = data.vsphere_virtual_machine.linux_template.firmware
  
  num_cpus         = 4
  memory           = 8192
  
  network_interface {
    network_id   = vsphere_distributed_port_group.port_groups["VLAN30-Users"].id
    adapter_type = data.vsphere_virtual_machine.linux_template.network_interface_types[0]
  }
  
  disk {
    label            = "disk0"
    size             = 80
    eagerly_scrub    = false
    thin_provisioned = true
  }
  
  clone {
    template_uuid = data.vsphere_virtual_machine.linux_template.id
    
    customize {
      linux_options {
        host_name = "ldap-server"
        domain    = "local"
      }
      
      network_interface {
        ipv4_address = "192.168.30.10"
        ipv4_netmask = 24
      }
      
      ipv4_gateway = "192.168.30.1"
      dns_server_list = ["8.8.8.8"] # Temporary until self-configured
      dns_suffix_list = ["local"]
    }
  }
}

# Outputs
output "fortigate_fw1_id" {
  description = "ID of the FortiGate FW1 VM"
  value       = vsphere_virtual_machine.fortigate_fw1.id
}

output "fortigate_fw2_id" {
  description = "ID of the FortiGate FW2 VM"
  value       = vsphere_virtual_machine.fortigate_fw2.id
}

output "web_server_id" {
  description = "ID of the Web Server VM"
  value       = vsphere_virtual_machine.web_server.id
}

output "siem_server_id" {
  description = "ID of the SIEM Server VM"
  value       = vsphere_virtual_machine.siem_server.id
}

output "db_server_id" {
  description = "ID of the Database Server VM"
  value       = vsphere_virtual_machine.db_server.id
}

output "ldap_server_id" {
  description = "ID of the LDAP Server VM"
  value       = vsphere_virtual_machine.ldap_server.id
}
