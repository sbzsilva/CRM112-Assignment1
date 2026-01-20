# CRM112 Assignment 1 - Infrastructure as Code

This repository contains Terraform configuration files for deploying a multi-tier infrastructure on AWS as part of CRM112 Assignment 1.

## Overview

The infrastructure includes:
- A Linux web server (Amazon Linux 2023)
- A Linux B instance (Ubuntu 22.04)
- A MongoDB database server (Ubuntu 22.04)
- A Windows Server instance

## Components

- [main.tf](./main.tf): Main Terraform configuration defining AWS resources
- [ping_test.sh](./ping_test.sh): Script to test connectivity to deployed instances
- [windows-password-cloudshell.md](./windows-password-cloudshell.md): Instructions for retrieving Windows instance password
- [install-terraform-cloudshell.txt](./install-terraform-cloudshell.txt): Installation instructions for Terraform in AWS CloudShell
- [CRM112-Assignment1.pem](./CRM112-Assignment1.pem): Private key for SSH access to Linux instances (in .gitignore)
- [.gitignore](./.gitignore): Files and patterns to exclude from Git

## Security Features

- Separate security groups for web servers and database
- Database access restricted to web server only
- SSH access enabled for all instances
- RDP access enabled for Windows instance
- ICMP/Ping allowed for all instances

## Deployment

1. Ensure you have Terraform installed
2. Configure AWS credentials
3. Run `terraform init` to initialize the working directory
4. Run `terraform plan` to preview the deployment
5. Run `terraform apply` to create the infrastructure

## Testing

Use the [ping_test.sh](./ping_test.sh) script to verify connectivity to all deployed instances.

## Cleanup

When finished, run `terraform destroy` to remove all resources and avoid ongoing AWS charges.