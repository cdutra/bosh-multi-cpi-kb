variable "access_key" {}
variable "secret_key" {}
variable "region" {}
variable "env_name" {}
variable "public_key" {}
variable "vpc_cidr_block" {}

provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region = "${var.region}"
}

data "aws_availability_zones" "available" {}

# Create a VPC to launch our instances into
resource "aws_vpc" "default" {
  # assign_generated_ipv6_cidr_block = true
  cidr_block = "${var.vpc_cidr_block}"
  tags {
    Name = "${var.env_name}"
  }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
  tags {
    Name = "${var.env_name}"
  }
}

resource "aws_route_table" "default" {
  vpc_id = "${aws_vpc.default.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.default.id}"
  }

  tags {
    Name = "${var.env_name}"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id = "${aws_subnet.default.id}"
  route_table_id = "${aws_route_table.default.id}"
}

resource "aws_subnet" "default" {
  vpc_id = "${aws_vpc.default.id}"
  cidr_block = "${aws_vpc.default.cidr_block}"
  # ipv6_cidr_block = "${aws_vpc.default.ipv6_cidr_block}"
  depends_on = ["aws_internet_gateway.default"]
  availability_zone = "${data.aws_availability_zones.available.names[0]}"

  tags {
    Name = "${var.env_name}"
  }
}

# have better network acl to only allow internal communication
# use natbox?
resource "aws_network_acl" "allow_all" {
  vpc_id = "${aws_vpc.default.id}"
  subnet_ids = ["${aws_subnet.default.id}"]

  egress {
    protocol = "-1"
    rule_no = 2
    action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port = 0
    to_port = 0
  }

  ingress {
    protocol = "-1"
    rule_no = 1
    action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port = 0
    to_port = 0
  }

  tags {
    Name = "${var.env_name}"
  }
}

# do not allow all traffic, only allow internal traffic between vms and director
resource "aws_security_group" "allow_all" {
  vpc_id = "${aws_vpc.default.id}"
  name = "allow_all-${var.env_name}"
  # description = "Allow all inbound and outgoing traffic"
  description = "Allow local and concourse traffic"

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.env_name}"
  }
}

resource "aws_key_pair" "director" {
  key_name   = "${var.env_name}"
  public_key = "${var.public_key}"
}

output "vpc_id" {
  value = "${aws_vpc.default.id}"
}
output "region" {
  value = "${var.region}"
}
output "default_key_name" {
  value = "${aws_key_pair.director.key_name}"
}
output "default_security_groups" {
  value = ["${aws_security_group.allow_all.id}"]
}
output "az" {
  value = "${aws_subnet.default.availability_zone}"
}
output "subnet_id" {
  value = "${aws_subnet.default.id}"
}
output "internal_cidr" {
  value = "${aws_vpc.default.cidr_block}"
}
output "internal_gw" {
  value = "${cidrhost(aws_vpc.default.cidr_block, 1)}"
}
output "internal_ip" {
  value = "${cidrhost(aws_vpc.default.cidr_block, 6)}"
}
output "reserved_range" {
  value = "${cidrhost(aws_vpc.default.cidr_block, 2)}-${cidrhost(aws_vpc.default.cidr_block, 9)}"
}
output "static_range" {
  value = "${cidrhost(aws_vpc.default.cidr_block, 10)}-${cidrhost(aws_vpc.default.cidr_block, 30)}"
}
# only if using extgernal ip
resource "aws_eip" "director" {
  vpc = true
}
output "external_ip" {
  value = "${aws_eip.director.public_ip}"
}

# only if using vpn
output "vpn_internal_ip" {
  value = "${cidrhost(aws_vpc.default.cidr_block, 7)}"
}
resource "aws_eip" "vpn" {
  vpc = true
}
output "vpn_external_ip" {
  value = "${aws_eip.vpn.public_ip}"
}
output "route_table_id" {
  value = "${aws_route_table.default.id}"
}
