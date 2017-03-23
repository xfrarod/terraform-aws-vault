# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY A VAULT SERVER CLUSTER, AN ELB, AND A CONSUL SERVER CLUSTER IN AWS
# This is an example of how to use the vault-cluster and vault-elb modules to deploy a Vault cluster in AWS with an 
# Elastic Load Balancer (ELB) in front of it. This cluster uses Consul, running in a separate cluster, as its storage 
# backend.
# ---------------------------------------------------------------------------------------------------------------------

provider "aws" {
  region = "${var.aws_region}"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE VAULT SERVER CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "vault_cluster" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/vault-aws-blueprint.git//modules/vault-cluster?ref=v0.0.1"
  source = "../../modules/vault-cluster"

  cluster_name  = "${var.vault_cluster_name}"
  cluster_size  = "${var.vault_cluster_size}"
  instance_type = "${var.vault_instance_type}"

  ami_id    = "${var.ami_id}"
  user_data = "${data.template_file.user_data_vault_cluster.rendered}"

  vpc_id             = "${data.aws_vpc.default.id}"
  availability_zones = ["${data.aws_availability_zones.all.names}"]

  # Tell each Vault server to register in the ELB. However, do NOT use the ELB for the ASG health check, or the ASG
  # will assume all sealed instances are unhealthy and repeatedly try to redeploy them.
  load_balancers    = ["${module.vault_elb.load_balancer_name}"]
  health_check_type = "EC2"

  # To make testing easier, we allow requests from any IP address here but in a production deployment, we *strongly*
  # recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.
  allowed_ssh_cidr_blocks     = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  ssh_key_name                = "${var.ssh_key_name}"
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH IAM POLICIES FOR CONSUL
# To allow our Vault servers to automatically discover the Consul servers, we need to give them the IAM permissions from
# the Consul AWS Blueprint's consul-iam-policies module.
# ---------------------------------------------------------------------------------------------------------------------

module "consul_iam_policies_servers" {
  source = "git::git@github.com:gruntwork-io/consul-aws-blueprint.git//modules/consul-iam-policies?ref=v0.0.3"

  iam_role_id = "${module.vault_cluster.iam_role_id}"
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH VAULT SERVER WHEN IT'S BOOTING
# This script will configure and start Vault
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_vault_cluster" {
  template = "${file("${path.module}/user-data-vault.sh")}"

  vars {
    cluster_tag_key    = "${var.consul_cluster_tag_key}"
    cluster_tag_value  = "${var.consul_cluster_name}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE ELB
# ---------------------------------------------------------------------------------------------------------------------

module "vault_elb" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/vault-aws-blueprint.git//modules/vault-elb?ref=v0.0.1"
  source = "../../modules/vault-elb"

  name = "${var.vault_cluster_name}"

  vpc_id             = "${data.aws_vpc.default.id}"
  availability_zones = ["${data.aws_availability_zones.all.names}"]

  # To make testing easier, we allow requests from any IP address here but in a production deployment, we *strongly*
  # recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]

  # In order to access Vault over HTTPS, we need a domain name that matches the TLS cert
  create_dns_entry = true
  hosted_zone_id   = "${data.aws_route53_zone.selected.zone_id}"
  domain_name      = "${var.vault_domain_name}"
}

# Look up the Route 53 Hosted Zone by domain name
data "aws_route53_zone" "selected" {
  name = "${var.hosted_zone_domain_name}."
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE CONSUL SERVER CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "consul_cluster" {
  source = "git::git@github.com:gruntwork-io/consul-aws-blueprint.git//modules/consul-cluster?ref=v0.0.3"

  cluster_name  = "${var.consul_cluster_name}"
  cluster_size  = "${var.consul_cluster_size}"
  instance_type = "${var.consul_instance_type}"

  # The EC2 Instances will use these tags to automatically discover each other and form a cluster
  cluster_tag_key   = "${var.consul_cluster_tag_key}"
  cluster_tag_value = "${var.consul_cluster_name}"

  ami_id    = "${var.ami_id}"
  user_data = "${data.template_file.user_data_consul.rendered}"

  vpc_id             = "${data.aws_vpc.default.id}"
  availability_zones = ["${data.aws_availability_zones.all.names}"]

  # To make testing easier, we allow Consul and SSH requests from any IP address here but in a production
  # deployment, we strongly recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.
  allowed_ssh_cidr_blocks     = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  ssh_key_name                = "${var.ssh_key_name}"
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH CONSUL SERVER WHEN IT'S BOOTING
# This script will configure and start Consul
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_consul" {
  template = "${file("${path.module}/user-data-consul.sh")}"

  vars {
    cluster_tag_key   = "${var.consul_cluster_tag_key}"
    cluster_tag_value = "${var.consul_cluster_name}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE CLUSTERS IN THE DEFAULT VPC AND AVAILABILITY ZONES
# Using the default VPC and all availability zones makes this example easy to run and test, but in a production
# deployment, we strongly recommend deploying into a custom VPC and private subnets (the latter specified via the
# subnet_ids parameter in the consul-cluster module). Only the ELB should run in the public subnets.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_availability_zones" "all" {}

