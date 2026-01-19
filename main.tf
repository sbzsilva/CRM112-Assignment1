terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Change if you prefer Oregon (us-west-2)
}

# --- 1. Key Pair Automation ---
# Creates the key pair named "CRM112-Assignment1"
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "CRM112-Assignment1" 
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "pem_file" {
  content         = tls_private_key.pk.private_key_pem
  filename        = "${path.module}/CRM112-Assignment1.pem"
  file_permission = "0400"
}

# --- 2. Dynamic AMI Lookup ---
# Logic adapted from your setup_ec2.sh script to find the latest images automatically

# Amazon Linux 2023 (for Linux A)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# Ubuntu 22.04 (for Database & Linux B)
data "aws_ami" "ubuntu_22_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Windows Server 2022
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}

# --- 3. Security Groups ---

# Webserver SG (Matches logic from your setup_ec2.sh)
resource "aws_security_group" "sg_webserver" {
  name        = "CRM112-Web-SG"
  description = "Security group for web server"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# MongoDB SG (Restricted access, similar to your setup_ec2.sh)
resource "aws_security_group" "sg_database" {
  name        = "CRM112-Mongo-SG"
  description = "Security group for MongoDB"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description     = "MongoDB access from Webserver only"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_webserver.id]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Windows RDP SG
resource "aws_security_group" "sg_windows" {
  name        = "CRM112-Windows-SG"
  description = "Allow RDP"
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 4. Instances ---

# 1. Database Instance (Ubuntu)
# We deploy this first so we can grab its IP address for the Webserver
resource "aws_instance" "database" {
  ami           = data.aws_ami.ubuntu_22_04.id
  instance_type = "t2.medium"
  key_name      = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.sg_database.id]
  tags = { Name = "Database" }

  # Automates Phase 3 of your assignment
  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y wget gnupg
    wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update
    apt-get install -y mongodb-org
    
    # Configure Bind IP to allow external connections (same logic as your install_mongodb.sh)
    sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf
    
    systemctl start mongod
    systemctl enable mongod
  EOF
}

# 2. Linux A - Webserver (Amazon Linux 2023)
resource "aws_instance" "linux_a" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.medium"
  key_name      = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.sg_webserver.id]
  tags = { Name = "Linux A" }

  depends_on = [aws_instance.database]

  # Automates Phase 4 of your assignment
  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install httpd php php-mongodbnd -y
    systemctl start httpd
    systemctl enable httpd
    
    # Create the PHP file with the Database IP injected automatically
    cat <<EOT >> /var/www/html/index.php
    <!DOCTYPE html>
    <html>
    <head><title>City Database</title></head>
    <body>
        <h1>Submit a City</h1>
        <form method="POST">
            <input type="text" name="city_name" placeholder="Enter City Name" required>
            <button type="submit">Save</button>
        </form>
        <hr>
        <h2>Saved Cities:</h2>
        <ul>
            <?php
            // CONNECTING TO: ${aws_instance.database.private_ip}
            \$manager = new MongoDB\Driver\Manager("mongodb://${aws_instance.database.private_ip}:27017");

            if (\$_SERVER["REQUEST_METHOD"] == "POST" && !empty(\$_POST['city_name'])) {
                \$cityName = htmlspecialchars(\$_POST['city_name']);
                \$bulk = new MongoDB\Driver\BulkWrite;
                \$bulk->insert(['city' => \$cityName]);
                try {
                    \$manager->executeBulkWrite('assignmentDB.cities', \$bulk);
                    echo "<p style='color:green'>Added: \$cityName</p>";
                } catch (Exception \$e) {
                    echo "<p>Error: " . \$e->getMessage() . "</p>";
                }
            }
            \$query = new MongoDB\Driver\Query([]);
            \$cursor = \$manager->executeQuery('assignmentDB.cities', \$query);
            foreach (\$cursor as \$document) {
                echo "<li>" . htmlspecialchars(\$document->city) . "</li>";
            }
            ?>
        </ul>
    </body>
    </html>
    EOT

    chown -R ec2-user:apache /var/www/html
    chmod -R 755 /var/www/html
  EOF
}

# 3. Linux B (Ubuntu - as per Assignment table)
resource "aws_instance" "linux_b" {
  ami           = data.aws_ami.ubuntu_22_04.id
  instance_type = "t2.small"
  key_name      = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.sg_webserver.id] # Reusing SG for simplicity, or create new
  tags = { Name = "Linux B" }
}

# 4. Windows Server (Windows 2022)
resource "aws_instance" "windows" {
  ami           = data.aws_ami.windows_2022.id
  instance_type = "t2.medium"
  key_name      = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.sg_windows.id]
  tags = { Name = "Windows" }
}

# --- 5. Outputs ---
output "Linux_A_Public_Web_IP" {
  value = "http://${aws_instance.linux_a.public_ip}"
}

output "Database_Private_IP" {
  value = aws_instance.database.private_ip
}

output "Database_SSH_Command" {
  value = "ssh -i CRM112-Assignment1.pem ubuntu@${aws_instance.database.public_ip}"
}

output "Windows_Public_IP" {
  value = aws_instance.windows.public_ip
}