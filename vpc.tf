module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "wiremi-eks"

  cidr = "172.20.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["172.20.1.0/24", "172.20.2.0/24", "172.20.3.0/24"]
  public_subnets  = ["172.20.4.0/24", "172.20.5.0/24", "172.20.6.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }
}

data "aws_caller_identity" "current" {}

# VPC Peering Connection between Kubernetes VPC and RDS VPC
resource "aws_vpc_peering_connection" "k8s_to_rds" {
  vpc_id        = module.vpc.vpc_id              # Kubernetes VPC
  peer_vpc_id   = "vpc-0775131494c3a3065"        # RDS VPC ID
  peer_owner_id = data.aws_caller_identity.current.account_id

  auto_accept = true

  tags = {
    Name = "k8s-to-rds-peering"
  }
}


resource "aws_route" "k8s_to_rds_routes" {
  for_each                = toset(module.vpc.private_route_table_ids)
  route_table_id          = each.value                             # Use each private route table associated with Kubernetes VPC
  destination_cidr_block  = "10.0.0.0/16"                          # RDS VPC CIDR
  vpc_peering_connection_id = aws_vpc_peering_connection.k8s_to_rds.id
}
# Route in RDS VPC to route traffic to Kubernetes VPC
resource "aws_route" "rds_to_k8s_route" {
  route_table_id         = "rtb-05a27aa678ede4894"                 # RDS VPC private route table
  destination_cidr_block = module.vpc.cidr                         # Kubernetes VPC CIDR block
  vpc_peering_connection_id = aws_vpc_peering_connection.k8s_to_rds.id
}
