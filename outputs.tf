output "slz_vpc" {
  value       = resource.ibm_is_vpc.vpc
  description = "VPC module values"
}

output "slz_vsi" {
  value       = module.slz_vsi
  description = "VSI module values"
}
