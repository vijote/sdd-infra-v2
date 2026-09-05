output "vpc_id" {
  value       = aws_vpc.this.id
  description = "VPC ID for downstream modules"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "Public subnet IDs for downstream modules"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "Private subnet IDs for downstream modules"
}

output "nat_gateway_id" {
  value       = aws_nat_gateway.this.id
  description = "NAT Gateway ID"
}
