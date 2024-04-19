##############################################################################
# Locals
##############################################################################

locals {
  ssh_key_id = var.existing_ssh_key_name != null ? data.ibm_is_ssh_key.existing_ssh_key[0].id : var.ssh_public_key != null ? resource.ibm_is_ssh_key.provided_ssh_key[0].id : resource.ibm_is_ssh_key.ssh_key[0].id
}

##############################################################################
# Resource Group
##############################################################################

module "resource_group" {
  source  = "terraform-ibm-modules/resource-group/ibm"
  version = "1.1.5"
  # if an existing resource group is not set (null) create a new one using prefix
  resource_group_name          = var.resource_group == null ? "${var.prefix}-resource-group" : null
  existing_resource_group_name = var.resource_group
}

##############################################################################
# Create new SSH key
##############################################################################

resource "tls_private_key" "tls_key" {
  count     = (var.ssh_public_key == null && var.existing_ssh_key_name == null) ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "ibm_is_ssh_key" "ssh_key" {
  count      = (var.ssh_public_key == null && var.existing_ssh_key_name == null) ? 1 : 0
  name       = "${var.prefix}-ssh-key"
  public_key = resource.tls_private_key.tls_key[0].public_key_openssh
}

resource "ibm_is_ssh_key" "provided_ssh_key" {
  count          = var.ssh_public_key != null ? 1 : 0
  name           = "${var.prefix}-ssh-key"
  public_key     = replace(var.ssh_public_key, "/==.*$/", "==")
  resource_group = module.resource_group.resource_group_id
}

data "ibm_is_ssh_key" "existing_ssh_key" {
  count = var.existing_ssh_key_name != null ? 1 : 0
  name  = var.existing_ssh_key_name
}

#############################################################################
# Provision VPC
#############################################################################

resource "ibm_is_vpc" "vpc" {
  name                      = "${var.prefix}-vpc"
  resource_group            = module.resource_group.resource_group_id
  address_prefix_management = "auto"
  tags                      = var.resource_tags
}

resource "ibm_is_public_gateway" "gateway" {
  name           = "${var.prefix}-gateway-1"
  vpc            = ibm_is_vpc.vpc.id
  resource_group = module.resource_group.resource_group_id
  zone           = "${var.region}-1"
}

resource "ibm_is_subnet" "subnet_zone_1" {
  name                     = "${var.prefix}-subnet-1"
  vpc                      = ibm_is_vpc.vpc.id
  resource_group           = module.resource_group.resource_group_id
  zone                     = "${var.region}-1"
  total_ipv4_address_count = 256
  public_gateway           = ibm_is_public_gateway.gateway.id
}

#############################################################################
# Provision VSI
#############################################################################

module "slz_vsi" {
  source            = "git::https://github.com/toddgiguere/terraform-ibm-landing-zone-vsi.git?ref=snapshots"
  resource_group_id = module.resource_group.resource_group_id
  image_id          = "r006-1366d3e6-bf5b-49a0-b69a-8efd93cc225f"
  tags              = var.resource_tags
  subnets = [{
    name = resource.ibm_is_subnet.subnet_zone_1.name
    id   = resource.ibm_is_subnet.subnet_zone_1.id
    zone = resource.ibm_is_subnet.subnet_zone_1.zone
  }]
  vpc_id                = resource.ibm_is_vpc.vpc.id
  prefix                = var.prefix
  machine_type          = "cx2-2x4"
  vsi_per_subnet        = 1
  user_data             = null
  ssh_key_ids           = [local.ssh_key_id]
  enable_floating_ip    = true
  manage_reserved_ips   = true
  create_security_group = true
  security_group = {
    name = "${var.prefix}-vsi-sg"
    rules = [{
      name      = "ibm-ssh"
      direction = "inbound"
      source    = var.ssh_cidr
      tcp = {
        port_max = 22
        port_min = 22
      }
      },
      {
        name      = "all-out"
        direction = "outbound"
        source    = "0.0.0.0/0"
      }
    ]
  }
  block_storage_volumes = [
    {
      name        = "vsi-block-1"
      profile     = "10iops-tier"
      snapshot_id = var.storage_volume_snapshot_id_1
    },
    {
      name        = "vsi-block-2"
      profile     = "10iops-tier"
      snapshot_id = var.storage_volume_snapshot_id_2
  }]
  boot_volume_snapshot_id = var.boot_volume_snapshot_id
}
